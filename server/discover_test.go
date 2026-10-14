package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

type discoverUser struct {
	id, token string
}

func discoverSignup(t *testing.T, a *testAPI, campus string) discoverUser {
	t.Helper()
	v := a.session(campus)
	return discoverUser{id: v["user"].(map[string]any)["id"].(string), token: a.token}
}
func discoverDeck(t *testing.T, a *testAPI, query string) discoverResponse {
	t.Helper()
	w := a.req("GET", "/api/v1/discover"+query, nil)
	if w.Code != 200 {
		t.Fatalf("discover: %d %s", w.Code, w.Body.String())
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("discover is cacheable")
	}
	return decode[discoverResponse](t, w)
}
func deckIDs(d discoverResponse) []string {
	ids := []string{}
	for _, item := range d.Items {
		ids = append(ids, item.ID)
	}
	return ids
}
func swipe(t *testing.T, a *testAPI, target, action string) *httptest.ResponseRecorder {
	t.Helper()
	return a.req("POST", "/api/v1/discover/"+target+"/swipe", map[string]any{"action": action})
}
func count(t *testing.T, a *testAPI, query string, args ...any) int {
	t.Helper()
	var n int
	if err := a.s.db.QueryRow(query, args...).Scan(&n); err != nil {
		t.Fatal(query, err)
	}
	return n
}

func TestDiscoverCampusIsolationSelfAndSwipeExclusion(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peer := discoverSignup(t, a, "QA campus")
	a.token = peer.token
	a.req("PATCH", "/api/v1/me", map[string]any{"gender": "female"})
	stranger := discoverSignup(t, a, "Other campus")
	if d := discoverDeck(t, a, ""); len(d.Items) != 0 {
		t.Fatal("other campus sees QA campus profiles", d.Items)
	}
	if w := swipe(t, a, peer.id, "like"); w.Code != 403 {
		t.Fatalf("cross-campus swipe accepted: %d %s", w.Code, w.Body.String())
	}
	a.token = me.token
	d := discoverDeck(t, a, "")
	if !reflect.DeepEqual(deckIDs(d), []string{peer.id}) || d.LikesMe != 0 || d.LikesLeft != discoverDailyLikes {
		t.Fatalf("deck=%v likesMe=%d likesLeft=%d", deckIDs(d), d.LikesMe, d.LikesLeft)
	}
	item := d.Items[0]
	if item.Alias == "" || item.Gender != "female" || item.Campus != "QA campus" || item.Tags == nil || item.DistanceLabel != "" {
		t.Fatalf("unexpected item: %+v", item)
	}
	for _, secret := range []string{"latitude", "longitude", "allowDM", "createdAt", stranger.id} {
		if w := a.req("GET", "/api/v1/discover", nil); strings.Contains(w.Body.String(), secret) {
			t.Fatal("leak", secret, w.Body.String())
		}
	}
	if w := swipe(t, a, me.id, "like"); w.Code != 400 {
		t.Fatalf("self swipe accepted: %d", w.Code)
	}
	if w := swipe(t, a, stranger.id, "like"); w.Code != 403 {
		t.Fatalf("cross-campus target accepted: %d", w.Code)
	}
	if w := swipe(t, a, "missing", "like"); w.Code != 403 {
		t.Fatalf("missing target accepted: %d", w.Code)
	}
	for _, body := range []any{map[string]any{}, map[string]any{"action": "superlike"}, map[string]any{"action": "like", "extra": 1}} {
		if w := a.req("POST", "/api/v1/discover/"+peer.id+"/swipe", body); w.Code != 400 {
			t.Fatalf("invalid body %v accepted: %d", body, w.Code)
		}
	}
	if w := a.req("GET", "/api/v1/discover?gender=other", nil); w.Code != 400 {
		t.Fatalf("invalid gender filter: %d", w.Code)
	}
	if d := discoverDeck(t, a, "?gender=male"); len(d.Items) != 0 {
		t.Fatal("gender filter ignored", d.Items)
	}
	if d := discoverDeck(t, a, "?gender=female"); len(d.Items) != 1 {
		t.Fatal("gender filter dropped match", d.Items)
	}
	if w := swipe(t, a, peer.id, "pass"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != false {
		t.Fatalf("pass: %d %s", w.Code, w.Body.String())
	}
	if d := discoverDeck(t, a, ""); len(d.Items) != 0 || d.LikesLeft != discoverDailyLikes {
		t.Fatal("passed profile still in deck or pass charged quota", d)
	}
	if count(t, a, `SELECT count(*) FROM conversations`) != 0 || count(t, a, `SELECT count(*) FROM matches`) != 0 {
		t.Fatal("pass created conversation or match")
	}
	// A pass is forgotten after 30 days so the profile can resurface, and a
	// fresh pass on the resurfaced profile hides it again.
	if _, err := a.s.db.Exec(`UPDATE swipes SET updated_at=? WHERE actor_id=?`, time.Now().UTC().Add(-31*24*time.Hour).Format(time.RFC3339Nano), me.id); err != nil {
		t.Fatal(err)
	}
	if d := discoverDeck(t, a, ""); !reflect.DeepEqual(deckIDs(d), []string{peer.id}) {
		t.Fatal("expired pass still hides profile", deckIDs(d))
	}
	if w := swipe(t, a, peer.id, "pass"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if d := discoverDeck(t, a, ""); len(d.Items) != 0 {
		t.Fatal("renewed pass ignored", deckIDs(d))
	}
	a.s.cleanupDiscover()
	if count(t, a, `SELECT count(*) FROM swipes`) != 1 {
		t.Fatal("cleanup removed a fresh pass")
	}
	if _, err := a.s.db.Exec(`UPDATE swipes SET updated_at=?`, time.Now().UTC().Add(-31*24*time.Hour).Format(time.RFC3339Nano)); err != nil {
		t.Fatal(err)
	}
	a.s.cleanupDiscover()
	if count(t, a, `SELECT count(*) FROM swipes`) != 0 {
		t.Fatal("cleanup kept an expired pass")
	}
}

func TestDiscoverBlocksAndDMConsent(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peer := discoverSignup(t, a, "QA campus")
	a.token = me.token
	if len(discoverDeck(t, a, "").Items) != 1 {
		t.Fatal("peer missing before block")
	}
	for _, direction := range []string{"me blocks", "peer blocks"} {
		blocker, blocked := me, peer
		if direction == "peer blocks" {
			blocker, blocked = peer, me
		}
		a.token = blocker.token
		if w := a.req("POST", "/api/v1/blocks", map[string]any{"userId": blocked.id}); w.Code != 201 {
			t.Fatal(w.Code, w.Body.String())
		}
		for _, viewer := range []discoverUser{me, peer} {
			a.token = viewer.token
			if d := discoverDeck(t, a, ""); len(d.Items) != 0 {
				t.Fatalf("%s: %s still visible", direction, viewer.id)
			}
			other := peer
			if viewer == peer {
				other = me
			}
			if w := swipe(t, a, other.id, "like"); w.Code != 403 {
				t.Fatalf("%s: swipe on blocked user accepted: %d", direction, w.Code)
			}
		}
		a.token = blocker.token
		if w := a.req("DELETE", "/api/v1/blocks/"+blocked.id, nil); w.Code != 204 {
			t.Fatal(w.Code)
		}
	}
	// Blocked users also vanish from "likes me" and "matches" after the fact.
	a.token = peer.token
	if w := swipe(t, a, me.id, "like"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	a.token = me.token
	if d := discoverDeck(t, a, ""); d.LikesMe != 1 {
		t.Fatal("likesMe", d.LikesMe)
	}
	if w := swipe(t, a, peer.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := a.req("GET", "/api/v1/discover/matches", nil); len(decode[[]matchItem](t, w)) != 1 {
		t.Fatal(w.Body.String())
	}
	if w := a.req("POST", "/api/v1/blocks", map[string]any{"userId": peer.id}); w.Code != 201 {
		t.Fatal(w.Code)
	}
	if w := a.req("GET", "/api/v1/discover/matches", nil); len(decode[[]matchItem](t, w)) != 0 {
		t.Fatal("blocked match listed", w.Body.String())
	}
	a.token = peer.token
	if w := a.req("GET", "/api/v1/discover/matches", nil); len(decode[[]matchItem](t, w)) != 0 {
		t.Fatal("match visible to blocked side", w.Body.String())
	}
	a.token = me.token
	a.req("DELETE", "/api/v1/blocks/"+peer.id, nil)
	// A peer who turned direct messages off is invisible and cannot be swiped.
	third := discoverSignup(t, a, "QA campus")
	a.token = me.token
	if d := discoverDeck(t, a, ""); !reflect.DeepEqual(deckIDs(d), []string{third.id}) {
		t.Fatal(deckIDs(d))
	}
	a.token = third.token
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false})
	// A liker who cannot receive private messages would end in a one-sided
	// conversation, so a like is refused with the same hint nearby uses; a
	// pass has no side effect and stays allowed.
	if w := swipe(t, a, me.id, "like"); w.Code != 403 || !strings.Contains(w.Body.String(), "请先开启接收私信") {
		t.Fatal("sender with DM off could like", w.Code, w.Body.String())
	}
	if w := swipe(t, a, me.id, "pass"); w.Code != 200 {
		t.Fatal("sender with DM off could not pass", w.Code, w.Body.String())
	}
	if _, err := a.s.db.Exec(`DELETE FROM swipes WHERE actor_id=?`, third.id); err != nil {
		t.Fatal(err)
	}
	a.token = me.token
	if d := discoverDeck(t, a, ""); len(d.Items) != 0 || d.LikesMe != 0 {
		t.Fatal("DM-disabled peer visible", d)
	}
	if w := a.req("GET", "/api/v1/discover/likes", nil); len(decode[[]discoverItem](t, w)) != 0 {
		t.Fatal("DM-disabled liker listed", w.Body.String())
	}
	if w := swipe(t, a, third.id, "like"); w.Code != 403 {
		t.Fatalf("swipe on DM-disabled peer accepted: %d %s", w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM swipes WHERE actor_id=?`, me.id) != 1 || count(t, a, `SELECT count(*) FROM discover_likes WHERE user_id=?`, me.id) != 1 {
		t.Fatal("denied swipe persisted")
	}
	// Stale auth context must not bypass the in-transaction visibility check.
	r := httptest.NewRequest(http.MethodPost, "/api/v1/discover/"+third.id+"/swipe", strings.NewReader(`{"action":"like"}`))
	r.SetPathValue("id", third.id)
	r = r.WithContext(context.WithValue(r.Context(), userKey, User{ID: me.id, Campus: "QA campus", AllowDM: true}))
	w := httptest.NewRecorder()
	a.s.discoverSwipe(w, r)
	if w.Code != 403 {
		t.Fatalf("stale auth bypassed consent: %d %s", w.Code, w.Body.String())
	}
}

func TestDiscoverMutualLikeCreatesOneMatchAndIsIdempotent(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peer := discoverSignup(t, a, "QA campus")
	// peer liked me and has a filled-out profile; lurker is plain, so the deck
	// must rank liker first and the complete profile ahead of the plain one.
	a.token = peer.token
	a.req("PATCH", "/api/v1/me", map[string]any{"bio": "喜欢摄影", "grade": "junior", "tags": []string{"摄影", "旅行"}})
	lurker := discoverSignup(t, a, "QA campus")
	a.s.db.Exec(`UPDATE users SET alias='Z peer' WHERE id=?`, peer.id)
	a.s.db.Exec(`UPDATE users SET alias='A lurker' WHERE id=?`, lurker.id)
	a.token = peer.token
	if w := swipe(t, a, me.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != false {
		t.Fatal(w.Code, w.Body.String())
	}
	a.token = me.token
	d := discoverDeck(t, a, "")
	// The person who liked me leads the deck, then the plain profile.
	if !reflect.DeepEqual(deckIDs(d), []string{peer.id, lurker.id}) || d.LikesMe != 1 {
		t.Fatalf("deck=%v likesMe=%d", deckIDs(d), d.LikesMe)
	}
	if d.Items[0].Bio != "喜欢摄影" || d.Items[0].Grade != "junior" || !reflect.DeepEqual(d.Items[0].Tags, []string{"摄影", "旅行"}) {
		t.Fatalf("profile fields missing: %+v", d.Items[0])
	}
	w := a.req("GET", "/api/v1/discover/likes", nil)
	if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal(w.Code, w.Header())
	}
	likes := decode[[]discoverItem](t, w)
	if len(likes) != 1 || likes[0].ID != peer.id || likes[0].Bio != "喜欢摄影" {
		t.Fatalf("likes: %s", w.Body.String())
	}
	var responses []*httptest.ResponseRecorder
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			w := swipe(t, a, peer.id, "like")
			mu.Lock()
			responses = append(responses, w)
			mu.Unlock()
		}()
	}
	wg.Wait()
	var cid string
	for _, w := range responses {
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		v := decode[map[string]any](t, w)
		c, _ := v["conversation"].(map[string]any)
		if v["matched"] != true || c == nil || c["id"] == "" || c["alias"] == nil || c["unread"] == nil {
			t.Fatalf("match response: %s", w.Body.String())
		}
		if cid == "" {
			cid = c["id"].(string)
		}
		if c["id"] != cid {
			t.Fatal("different conversations for the same match")
		}
	}
	if count(t, a, `SELECT count(*) FROM matches`) != 1 || count(t, a, `SELECT count(*) FROM conversations`) != 1 || count(t, a, `SELECT count(*) FROM swipes WHERE actor_id=?`, me.id) != 1 {
		t.Fatal("duplicate match, conversation or swipe rows")
	}
	first, second := ordered(me.id, peer.id)
	if count(t, a, `SELECT count(*) FROM conversations WHERE id=? AND user1_id=? AND user2_id=?`, cid, first, second) != 1 {
		t.Fatal("conversation pair not in canonical order")
	}
	if count(t, a, `SELECT count FROM discover_likes WHERE user_id=?`, me.id) != 1 {
		t.Fatal("repeated like consumed extra quota")
	}
	d = discoverDeck(t, a, "")
	if !reflect.DeepEqual(deckIDs(d), []string{lurker.id}) || d.LikesMe != 0 || d.LikesLeft != discoverDailyLikes-1 {
		t.Fatalf("after match deck=%v likesMe=%d likesLeft=%d", deckIDs(d), d.LikesMe, d.LikesLeft)
	}
	if w := a.req("GET", "/api/v1/discover/likes", nil); len(decode[[]discoverItem](t, w)) != 0 {
		t.Fatal("answered like still listed", w.Body.String())
	}
	for _, viewer := range []discoverUser{me, peer} {
		a.token = viewer.token
		w := a.req("GET", "/api/v1/discover/matches", nil)
		if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal(w.Code)
		}
		matches := decode[[]matchItem](t, w)
		want := peer.id
		if viewer == peer {
			want = me.id
		}
		if len(matches) != 1 || matches[0].ID != want || matches[0].ConversationID != cid || matches[0].MatchedAt == "" || matches[0].Alias == "" {
			t.Fatalf("matches for %s: %s", viewer.id, w.Body.String())
		}
		if w := a.req("GET", "/api/v1/conversations", nil); len(decode[[]map[string]any](t, w)) != 1 {
			t.Fatal("match conversation missing from inbox", w.Body.String())
		}
	}
	// The conversation is a normal one: both sides can message in it.
	if w := a.req("POST", "/api/v1/conversations/"+cid+"/messages", map[string]any{"body": "hi"}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	// The other side liking again is a replay: no second match or conversation.
	if w := swipe(t, a, me.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM matches`) != 1 || count(t, a, `SELECT count(*) FROM conversations`) != 1 {
		t.Fatal("replay duplicated match")
	}
}

func TestDiscoverPassThenLikeAndLikeThenPass(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peer := discoverSignup(t, a, "QA campus")
	if w := swipe(t, a, me.id, "like"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	a.token = me.token
	if w := swipe(t, a, peer.id, "pass"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != false {
		t.Fatal(w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM matches`) != 0 || count(t, a, `SELECT count(*) FROM discover_likes WHERE user_id=?`, me.id) != 0 {
		t.Fatal("pass matched or charged quota")
	}
	if d := discoverDeck(t, a, ""); len(d.Items) != 0 || d.LikesMe != 0 {
		t.Fatal("passed liker still pending", d)
	}
	if w := swipe(t, a, peer.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM matches`) != 1 || count(t, a, `SELECT count(*) FROM conversations`) != 1 || count(t, a, `SELECT count FROM discover_likes WHERE user_id=?`, me.id) != 1 {
		t.Fatal("changing pass to like misbehaved")
	}
	var action string
	if err := a.s.db.QueryRow(`SELECT action FROM swipes WHERE actor_id=? AND target_id=?`, me.id, peer.id).Scan(&action); err != nil || action != "like" {
		t.Fatal(action, err)
	}
	// Like then pass changes the recorded decision without refunding or
	// duplicating anything; liking again charges one more credit but still
	// reuses the single match and conversation.
	if w := swipe(t, a, peer.id, "pass"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != false {
		t.Fatal(w.Code, w.Body.String())
	}
	if err := a.s.db.QueryRow(`SELECT action FROM swipes WHERE actor_id=? AND target_id=?`, me.id, peer.id).Scan(&action); err != nil || action != "pass" {
		t.Fatal(action, err)
	}
	if w := swipe(t, a, peer.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM matches`) != 1 || count(t, a, `SELECT count(*) FROM conversations`) != 1 || count(t, a, `SELECT count(*) FROM swipes`) != 2 {
		t.Fatal("decision change duplicated rows")
	}
}

func TestDiscoverDailyLikeQuota(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peers := make([]string, discoverDailyLikes+2)
	for i := range peers {
		peers[i] = discoverSignup(t, a, "QA campus").id
	}
	a.token = me.token
	if d := discoverDeck(t, a, ""); len(d.Items) != discoverDeckSize {
		t.Fatalf("deck cap: %d", len(d.Items))
	}
	for i := 0; i < discoverDailyLikes; i++ {
		if w := swipe(t, a, peers[i], "like"); w.Code != 200 {
			t.Fatalf("like %d: %d %s", i, w.Code, w.Body.String())
		}
	}
	if d := discoverDeck(t, a, ""); d.LikesLeft != 0 || len(d.Items) != 2 {
		t.Fatalf("likesLeft=%d items=%d", d.LikesLeft, len(d.Items))
	}
	w := swipe(t, a, peers[discoverDailyLikes], "like")
	if w.Code != 429 || decode[map[string]string](t, w)["error"] != "今天的心动次数已用完，请明天再试" {
		t.Fatalf("quota: %d %s", w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count(*) FROM swipes WHERE target_id=?`, peers[discoverDailyLikes]) != 0 {
		t.Fatal("rejected like persisted")
	}
	// Replays of an earlier like and passes are free even when exhausted.
	if w := swipe(t, a, peers[0], "like"); w.Code != 200 {
		t.Fatal("replay blocked by quota", w.Code, w.Body.String())
	}
	if w := swipe(t, a, peers[discoverDailyLikes+1], "pass"); w.Code != 200 {
		t.Fatal("pass blocked by quota", w.Code, w.Body.String())
	}
	if count(t, a, `SELECT count FROM discover_likes WHERE user_id=?`, me.id) != discoverDailyLikes {
		t.Fatal("quota counter drifted")
	}
	// A fresh UTC day restores the quota, and yesterday's counter is cleaned up.
	if _, err := a.s.db.Exec(`UPDATE discover_likes SET day='2000-01-01' WHERE user_id=?`, me.id); err != nil {
		t.Fatal(err)
	}
	if d := discoverDeck(t, a, ""); d.LikesLeft != discoverDailyLikes {
		t.Fatal("quota not reset", d.LikesLeft)
	}
	a.s.cleanupDiscover()
	if count(t, a, `SELECT count(*) FROM discover_likes`) != 0 {
		t.Fatal("stale quota row kept")
	}
	if w := swipe(t, a, peers[discoverDailyLikes], "like"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
}

func TestDiscoverConcurrentQuotaIsExact(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	peers := make([]string, discoverDailyLikes+6)
	for i := range peers {
		peers[i] = discoverSignup(t, a, "QA campus").id
	}
	a.token = me.token
	var wg sync.WaitGroup
	codes := make(chan int, len(peers))
	for _, peer := range peers {
		wg.Add(1)
		go func(peer string) { defer wg.Done(); codes <- swipe(t, a, peer, "like").Code }(peer)
	}
	wg.Wait()
	close(codes)
	ok, limited := 0, 0
	for code := range codes {
		switch code {
		case 200:
			ok++
		case 429:
			limited++
		default:
			t.Fatal("unexpected status", code)
		}
	}
	if ok != discoverDailyLikes || limited != 6 || count(t, a, `SELECT count(*) FROM swipes WHERE actor_id=?`, me.id) != discoverDailyLikes {
		t.Fatal(ok, limited)
	}
}

func TestDiscoverDistanceOnlyWithLiveCoarseLocations(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	peer := discoverSignup(t, a, "QA campus")
	a.token = me.token
	if d := discoverDeck(t, a, ""); d.Items[0].DistanceLabel != "" {
		t.Fatal("distance without peer location", d.Items[0].DistanceLabel)
	}
	// Beyond the nearby radius nothing is said at all; inside it only the same
	// coarse label the nearby page shows, never a number.
	a.token = peer.token
	nearbyPut(t, a, 30.06, 110)
	a.token = me.token
	if d := discoverDeck(t, a, ""); d.Items[0].DistanceLabel != "" {
		t.Fatal("distance beyond nearby radius reported", d.Items[0].DistanceLabel)
	}
	a.token = peer.token
	nearbyPut(t, a, 30.03, 110)
	a.token = me.token
	d := discoverDeck(t, a, "")
	if d.Items[0].DistanceLabel != "3–5 公里" {
		t.Fatalf("distance: %+v", d.Items[0])
	}
	w := a.req("GET", "/api/v1/discover", nil)
	for _, secret := range []string{"latitude", "longitude", "30.03", "110", "distanceKm", "3.3"} {
		if strings.Contains(w.Body.String(), `"`+secret) || strings.Contains(w.Body.String(), ":"+secret) {
			t.Fatal("coordinate leak", w.Body.String())
		}
	}
	if _, err := a.s.db.Exec(`UPDATE nearby_locations SET expires_at=? WHERE user_id=?`, time.Now().Add(-time.Second).UnixMilli(), peer.id); err != nil {
		t.Fatal(err)
	}
	if d := discoverDeck(t, a, ""); d.Items[0].DistanceLabel != "" {
		t.Fatal("expired peer location used")
	}
	a.req("DELETE", "/api/v1/nearby/location", nil)
	a.token = peer.token
	nearbyPut(t, a, 30.03, 110)
	a.token = me.token
	if d := discoverDeck(t, a, ""); d.Items[0].DistanceLabel != "" {
		t.Fatal("distance without own location")
	}
}

func TestDiscoverOrderingPrefersLikersThenCompleteProfiles(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	plain := discoverSignup(t, a, "QA campus")
	a.s.db.Exec(`UPDATE users SET alias='A plain' WHERE id=?`, plain.id)
	complete := discoverSignup(t, a, "QA campus")
	a.req("PATCH", "/api/v1/me", map[string]any{"tags": []string{"音乐"}})
	a.s.db.Exec(`UPDATE users SET alias='Z complete' WHERE id=?`, complete.id)
	liker := discoverSignup(t, a, "QA campus")
	a.s.db.Exec(`UPDATE users SET alias='Z liker' WHERE id=?`, liker.id)
	swipe(t, a, me.id, "like")
	a.token = me.token
	d := discoverDeck(t, a, "")
	if !reflect.DeepEqual(deckIDs(d), []string{liker.id, complete.id, plain.id}) {
		t.Fatal(deckIDs(d))
	}
	if again := discoverDeck(t, a, ""); !reflect.DeepEqual(deckIDs(again), deckIDs(d)) {
		t.Fatal("ordering unstable")
	}
}

func TestProfilePatchValidatesBioGradeAndTags(t *testing.T) {
	a := newTestAPI(t)
	v := a.session("QA campus")
	u := v["user"].(map[string]any)
	if u["bio"] != "" || u["grade"] != "" || !reflect.DeepEqual(u["tags"], []any{}) {
		t.Fatalf("new user profile defaults: %v", u)
	}
	for _, tc := range []struct {
		name string
		body map[string]any
		want int
	}{
		{"bio at limit", map[string]any{"bio": strings.Repeat("简", maxBioCharacters)}, 200},
		{"bio overflow", map[string]any{"bio": strings.Repeat("简", maxBioCharacters+1)}, 400},
		{"unknown grade", map[string]any{"grade": "phd"}, 400},
		{"grade", map[string]any{"grade": "senior"}, 200},
		{"unknown tag", map[string]any{"tags": []string{"运动", "量子力学"}}, 400},
		{"too many tags", map[string]any{"tags": profileTags[:maxProfileTags+1]}, 400},
		{"duplicate tags", map[string]any{"tags": []string{"运动", "运动"}}, 400},
		{"max tags", map[string]any{"tags": profileTags[:maxProfileTags]}, 200},
		{"wrong types", map[string]any{"tags": "运动"}, 400},
		{"wrong grade type", map[string]any{"grade": 3}, 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := a.req("PATCH", "/api/v1/me", tc.body)
			if w.Code != tc.want {
				t.Fatalf("%d %s", w.Code, w.Body.String())
			}
			if tc.want == 400 && !strings.ContainsAny(decode[map[string]string](t, w)["error"], "简介年级标签请求") {
				t.Fatalf("untranslated error: %s", w.Body.String())
			}
		})
	}
	me := decode[User](t, a.req("GET", "/api/v1/me", nil))
	if me.Bio != strings.Repeat("简", maxBioCharacters) || me.Grade != "senior" || !reflect.DeepEqual(me.Tags, profileTags[:maxProfileTags]) {
		t.Fatalf("profile not persisted: %+v", me)
	}
	// Tags keep the submitted order, and a partial PATCH leaves the rest alone.
	w := a.req("PATCH", "/api/v1/me", map[string]any{"tags": []string{profileTags[2], profileTags[0]}})
	if w.Code != 200 || !reflect.DeepEqual(decode[User](t, w).Tags, []string{profileTags[2], profileTags[0]}) {
		t.Fatal(w.Body.String())
	}
	me = decode[User](t, a.req("PATCH", "/api/v1/me", map[string]any{"alias": "Still"}))
	if me.Alias != "Still" || me.Grade != "senior" || len(me.Tags) != 2 || me.Bio == "" {
		t.Fatalf("partial PATCH wiped profile: %+v", me)
	}
	// Empty values clear each field.
	me = decode[User](t, a.req("PATCH", "/api/v1/me", map[string]any{"bio": "  ", "grade": "", "tags": []string{}}))
	if me.Bio != "" || me.Grade != "" || me.Tags == nil || len(me.Tags) != 0 {
		t.Fatalf("clear failed: %+v", me)
	}
	if count(t, a, `SELECT count(*) FROM user_tags`) != 0 {
		t.Fatal("cleared tags persisted")
	}
	// Blocks list carries the same profile fields, with tags as an empty list.
	a.req("PATCH", "/api/v1/me", map[string]any{"tags": []string{"阅读"}, "bio": "hi"})
	firstToken := a.token
	peer := discoverSignup(t, a, "QA campus").id
	a.token = firstToken
	if w := a.req("POST", "/api/v1/blocks", map[string]any{"userId": peer}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	blocks := decode[[]User](t, a.req("GET", "/api/v1/blocks", nil))
	if len(blocks) != 1 || blocks[0].ID != peer || blocks[0].Bio != "" || len(blocks[0].Tags) != 0 || blocks[0].Tags == nil {
		t.Fatalf("blocks DTO: %+v", blocks)
	}
}

func TestProfilePatchMergesStaleAuthWithProfileFields(t *testing.T) {
	a := newTestAPI(t)
	discoverSignup(t, a, "QA campus")
	stale := decode[User](t, a.req("GET", "/api/v1/me", nil))
	if w := a.req("PATCH", "/api/v1/me", map[string]any{"bio": "first", "tags": []string{"运动"}, "allowDM": false}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	r := httptest.NewRequest("PATCH", "/api/v1/me", strings.NewReader(`{"grade":"freshman"}`))
	r = r.WithContext(context.WithValue(r.Context(), userKey, stale))
	w := httptest.NewRecorder()
	a.s.me(w, r)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	u := decode[User](t, w)
	if u.AllowDM || u.Bio != "first" || u.Grade != "freshman" || !reflect.DeepEqual(u.Tags, []string{"运动"}) {
		t.Fatalf("stale auth overwrote profile: %+v", u)
	}
	u = decode[User](t, a.req("GET", "/api/v1/me", nil))
	if u.AllowDM || u.Bio != "first" || u.Grade != "freshman" || !reflect.DeepEqual(u.Tags, []string{"运动"}) {
		t.Fatalf("%+v", u)
	}
}

func TestDiscoverDeleteAccountCascadesAndMigrationIsAdditive(t *testing.T) {
	a := newTestAPI(t)
	me := discoverSignup(t, a, "QA campus")
	a.req("PATCH", "/api/v1/me", map[string]any{"tags": []string{"运动"}, "bio": "bye"})
	peer := discoverSignup(t, a, "QA campus")
	swipe(t, a, me.id, "like")
	a.token = me.token
	if w := swipe(t, a, peer.id, "like"); w.Code != 200 || decode[map[string]any](t, w)["matched"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	third := discoverSignup(t, a, "QA campus")
	a.token = me.token
	swipe(t, a, third.id, "pass")
	// Restart on the same database: the migration must be a no-op that keeps
	// every row, and the quota must survive.
	path := a.s.cfg.DBPath
	a.s.Close()
	s, err := NewServer(Config{DBPath: path, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	a.s, a.h = s, s.Handler()
	// me liked once (peer) and passed once (third): one credit spent.
	for query, want := range map[string]int{`SELECT count(*) FROM swipes`: 3, `SELECT count(*) FROM matches`: 1, `SELECT count(*) FROM user_tags`: 1, `SELECT count FROM discover_likes WHERE user_id='` + me.id + `'`: 1} {
		if got := count(t, a, query); got != want {
			t.Fatalf("%s after restart: %d", query, got)
		}
	}
	if d := discoverDeck(t, a, ""); d.LikesLeft != discoverDailyLikes-1 {
		t.Fatal("quota lost on restart", d.LikesLeft)
	}
	if w := a.req("DELETE", "/api/v1/me", nil); w.Code != 204 {
		t.Fatal(w.Code, w.Body.String())
	}
	for _, query := range []string{`SELECT count(*) FROM swipes WHERE actor_id=? OR target_id=?`, `SELECT count(*) FROM matches WHERE user1_id=? OR user2_id=?`, `SELECT count(*) FROM discover_likes WHERE user_id=? OR user_id=?`, `SELECT count(*) FROM user_tags WHERE user_id=? OR user_id=?`} {
		if n := count(t, a, query, me.id, me.id); n != 0 {
			t.Fatalf("cascade %s: %d", query, n)
		}
	}
	if count(t, a, `SELECT count(*) FROM swipes`) != 0 || count(t, a, `SELECT count(*) FROM matches`) != 0 {
		t.Fatal("deleted account left discover rows behind")
	}
	a.token = peer.token
	if w := a.req("GET", "/api/v1/discover/matches", nil); w.Code != 200 || len(decode[[]matchItem](t, w)) != 0 {
		t.Fatal(w.Code, w.Body.String())
	}
	if d := discoverDeck(t, a, ""); !reflect.DeepEqual(deckIDs(d), []string{third.id}) {
		t.Fatal(deckIDs(d))
	}
}

type publishedProfilePolicy struct {
	Profile struct {
		Bio     int           `json:"bioCharacters"`
		MaxTags int           `json:"maxTags"`
		Tags    []string      `json:"tags"`
		Grades  []gradeOption `json:"grades"`
	} `json:"profile"`
	Discover struct {
		DailyLikes int `json:"dailyLikes"`
	} `json:"discover"`
}

func TestPublicProfilePolicyMatchesWriteValidation(t *testing.T) {
	a := newTestAPI(t)
	w := a.req("GET", "/api/v1/config", nil)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	p := decode[publishedProfilePolicy](t, w)
	if p.Profile.Bio != maxBioCharacters || p.Profile.MaxTags != maxProfileTags || !reflect.DeepEqual(p.Profile.Tags, profileTags) || !reflect.DeepEqual(p.Profile.Grades, profileGrades) || p.Discover.DailyLikes != discoverDailyLikes {
		t.Fatalf("policy drift: %s", w.Body.String())
	}
	if len(p.Profile.Tags) < 6 || len(p.Profile.Tags) > 10 || len(p.Profile.Grades) != 4 {
		t.Fatalf("tags=%d grades=%d", len(p.Profile.Tags), len(p.Profile.Grades))
	}
	a.session("QA campus")
	for _, n := range []int{p.Profile.Bio, p.Profile.Bio + 1} {
		want := 200
		if n > p.Profile.Bio {
			want = 400
		}
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"bio": strings.Repeat("字", n)}); w.Code != want {
			t.Fatalf("bio %d: %d %s", n, w.Code, w.Body.String())
		}
	}
	for _, tag := range append(append([]string{}, p.Profile.Tags...), "未知") {
		want := 200
		if tag == "未知" {
			want = 400
		}
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"tags": []string{tag}}); w.Code != want {
			t.Fatalf("tag %q: %d %s", tag, w.Code, w.Body.String())
		}
	}
	for _, n := range []int{p.Profile.MaxTags, p.Profile.MaxTags + 1} {
		want := 200
		if n > p.Profile.MaxTags {
			want = 400
		}
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"tags": p.Profile.Tags[:n]}); w.Code != want {
			t.Fatalf("%d tags: %d %s", n, w.Code, w.Body.String())
		}
	}
	for _, g := range p.Profile.Grades {
		if g.ID == "" || g.Label == "" {
			t.Fatal("grade option missing id or label", g)
		}
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"grade": g.ID}); w.Code != 200 {
			t.Fatalf("grade %q: %d %s", g.ID, w.Code, w.Body.String())
		}
	}
	if w := a.req("PATCH", "/api/v1/me", map[string]any{"grade": "unknown"}); w.Code != 400 {
		t.Fatal("unknown grade accepted")
	}
	// The published daily quota is the one the swipe endpoint enforces.
	owner := a.token
	peers := make([]string, p.Discover.DailyLikes+1)
	for i := range peers {
		peers[i] = discoverSignup(t, a, "QA campus").id
	}
	a.token = owner
	for i, peer := range peers {
		want := 200
		if i == p.Discover.DailyLikes {
			want = 429
		}
		if w := swipe(t, a, peer, "like"); w.Code != want {
			t.Fatalf("like %d of %d: %d %s", i, p.Discover.DailyLikes, w.Code, w.Body.String())
		}
	}
	if d := discoverDeck(t, a, ""); d.LikesLeft != 0 {
		t.Fatal(d.LikesLeft)
	}
}
