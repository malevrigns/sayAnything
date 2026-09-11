package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func nearbyUser(t *testing.T, a *testAPI, campus string) (string, string) {
	t.Helper()
	v := a.session(campus)
	return v["user"].(map[string]any)["id"].(string), a.token
}
func nearbyPut(t *testing.T, a *testAPI, lat, lon float64) {
	t.Helper()
	status := decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
	w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": lat, "longitude": lon, "revision": status["revision"]})
	if w.Code != 200 {
		t.Fatalf("location: %d %s", w.Code, w.Body.String())
	}
}

func TestNearbyRevisionRejectsLatePublish(t *testing.T) {
	for _, action := range []string{"delete without previous location", "delete active location", "DM off and on"} {
		t.Run(action, func(t *testing.T) {
			a := newTestAPI(t)
			nearbyUser(t, a, "QA campus")
			if action != "delete without previous location" {
				nearbyPut(t, a, 30, 110)
			}
			before := decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
			revision, ok := before["revision"].(float64)
			if !ok {
				t.Fatal("owner revision missing", before)
			}
			if action == "DM off and on" {
				a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false})
				a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": true})
			} else if w := a.req("DELETE", "/api/v1/nearby/location", nil); w.Code != 204 {
				t.Fatal(w.Code)
			}
			after := decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
			if after["revision"] != revision+1 || after["enabled"] != false {
				t.Fatal("revoke did not advance revision", before, after)
			}
			w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 30, "longitude": 110, "revision": revision})
			if w.Code != 409 {
				t.Fatal("late publish accepted", w.Code, w.Body.String())
			}
			after = decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
			if after["enabled"] != false {
				t.Fatal("late publish restored visibility")
			}
		})
	}
}

func TestProfilePatchPreservesConcurrentDistinctFieldUpdates(t *testing.T) {
	a := newTestAPI(t)
	nearbyUser(t, a, "QA campus")
	stale := decode[User](t, a.req("GET", "/api/v1/me", nil))
	if w := a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false, "alias": "Updated"}); w.Code != 200 {
		t.Fatal(w.Code)
	}
	r := httptest.NewRequest("PATCH", "/api/v1/me", strings.NewReader(`{"gender":"female"}`))
	r = r.WithContext(context.WithValue(r.Context(), userKey, stale))
	w := httptest.NewRecorder()
	a.s.me(w, r)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	u := decode[User](t, w)
	if u.AllowDM || u.Gender != "female" || u.Alias != "Updated" {
		t.Fatal("stale auth overwrote current fields", u)
	}
	u = decode[User](t, a.req("GET", "/api/v1/me", nil))
	if u.AllowDM || u.Gender != "female" || u.Alias != "Updated" {
		t.Fatal(u)
	}
}
func nearbyItems(t *testing.T, a *testAPI) []map[string]any {
	t.Helper()
	w := a.req("GET", "/api/v1/nearby", nil)
	if w.Code != 200 {
		t.Fatalf("nearby: %d %s", w.Code, w.Body.String())
	}
	var v struct{ Items []map[string]any }
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	return v.Items
}
func TestGenderMigrationAndValidation(t *testing.T) {
	p := filepath.Join(t.TempDir(), "old.db")
	db, e := sql.Open("sqlite", p)
	if e != nil {
		t.Fatal(e)
	}
	_, e = db.Exec(`CREATE TABLE users(id TEXT PRIMARY KEY,alias TEXT NOT NULL,campus TEXT NOT NULL,avatar INTEGER NOT NULL,allow_dm INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL); INSERT INTO users VALUES('old','Old','A',0,1,'2020-01-01T00:00:00Z')`)
	if e != nil {
		t.Fatal(e)
	}
	_, e = db.Exec(`CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires_at TEXT NOT NULL); INSERT INTO sessions VALUES(?,?,?)`, sha256String("legacy-token"), "old", timeAdd(30))
	if e != nil {
		t.Fatal(e)
	}
	db.Close()
	s, e := NewServer(Config{DBPath: p, RateLimit: 10000})
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	var gender string
	if e = s.db.QueryRow(`SELECT gender FROM users WHERE id='old'`).Scan(&gender); e != nil || gender != "undisclosed" {
		t.Fatalf("old user gender=%q err=%v", gender, e)
	}
	var revision int64
	if e = s.db.QueryRow(`SELECT nearby_revision FROM users WHERE id='old'`).Scan(&revision); e != nil || revision != 0 {
		t.Fatal("legacy revision migration", revision, e)
	}
	a := &testAPI{t: t, h: s.Handler(), s: s}
	a.token = "legacy-token"
	w := a.req("GET", "/api/v1/me", nil)
	if w.Code != 200 {
		t.Fatal("legacy session lost", w.Code, w.Body.String())
	}
	old := decode[map[string]any](t, w)
	if old["id"] != "old" || old["alias"] != "Old" || old["gender"] != "undisclosed" {
		t.Fatal("legacy identity changed", old)
	}
	v := a.session("A")
	if v["user"].(map[string]any)["gender"] != "undisclosed" {
		t.Fatal(v)
	}
	for _, g := range []any{"male", "female", "undisclosed"} {
		w := a.req("PATCH", "/api/v1/me", map[string]any{"gender": g})
		if w.Code != 200 || decode[map[string]any](t, w)["gender"] != g {
			t.Fatal(w.Code, w.Body.String())
		}
		w = a.req("GET", "/api/v1/me", nil)
		if decode[map[string]any](t, w)["gender"] != g {
			t.Fatal(w.Body.String())
		}
	}
	for _, g := range []any{"unknown", "", nil, 12, true} {
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"gender": g}); w.Code != 400 {
			t.Fatal("accepted invalid gender", g, w.Code)
		}
	}
}
func TestNearbyVisibilityPrivacyAndDeletion(t *testing.T) {
	a := newTestAPI(t)
	id, tok := nearbyUser(t, a, "QA campus")
	w := a.req("GET", "/api/v1/nearby", nil)
	if w.Code != 200 {
		t.Fatalf("nearby route: %d", w.Code)
	}
	v := decode[map[string]any](t, w)
	if v["enabled"] != false || len(v["items"].([]any)) != 0 {
		t.Fatal(v)
	}
	nearbyPut(t, a, 30.123456, 110.123456)
	var lat, lon float64
	var exp int64
	if e := a.s.db.QueryRow(`SELECT latitude,longitude,expires_at FROM nearby_locations WHERE user_id=?`, id).Scan(&lat, &lon, &exp); e != nil || lat != 30.12 || lon != 110.12 || exp < time.Now().Add(29*time.Minute).UnixMilli() || exp > time.Now().Add(31*time.Minute).UnixMilli() {
		t.Fatalf("grid/expiry %v %v %v %v", lat, lon, exp, e)
	}
	peer, ptok := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30.13, 110.12)
	a.req("PATCH", "/api/v1/me", map[string]any{"gender": "female"})
	_, _ = nearbyUser(t, a, "Different campus")
	nearbyPut(t, a, 30.12, 110.12)
	_, _ = nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 31.12, 110.12)
	a.token = tok
	items := nearbyItems(t, a)
	if len(items) != 1 || items[0]["id"] != peer || items[0]["gender"] != "female" || len(items[0]) != 4 {
		t.Fatal(items)
	}
	w = a.req("GET", "/api/v1/nearby", nil)
	for _, secret := range []string{"latitude", "longitude", "30.13", "110.12", "createdAt", "distanceKm"} {
		if strings.Contains(w.Body.String(), secret) {
			t.Fatal("location leak", w.Body.String())
		}
	}
	a.token = ptok
	a.req("POST", "/api/v1/blocks", map[string]any{"userId": id})
	a.token = tok
	if len(nearbyItems(t, a)) != 0 {
		t.Fatal("blocked peer visible")
	}
	a.token = ptok
	a.req("DELETE", "/api/v1/blocks/"+id, nil)
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false})
	a.token = tok
	if len(nearbyItems(t, a)) != 0 {
		t.Fatal("disabled DM peer visible")
	}
	a.token = ptok
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": true})
	nearbyPut(t, a, 30.13, 110.12)
	a.s.db.Exec(`UPDATE nearby_locations SET expires_at=? WHERE user_id=?`, time.Now().Add(-time.Second).UnixMilli(), peer)
	a.token = tok
	if len(nearbyItems(t, a)) != 0 {
		t.Fatal("expired peer visible")
	}
	if w = a.req("DELETE", "/api/v1/nearby/location", nil); w.Code != 204 {
		t.Fatal(w.Code)
	}
	var n int
	a.s.db.QueryRow(`SELECT count(*) FROM nearby_locations WHERE user_id=?`, id).Scan(&n)
	if n != 0 {
		t.Fatal("location retained")
	}
}
func TestNearbyInvalidLocation(t *testing.T) {
	a := newTestAPI(t)
	nearbyUser(t, a, "QA campus")
	for _, body := range []any{map[string]any{}, map[string]any{"latitude": 0}, map[string]any{"latitude": nil, "longitude": 0}, map[string]any{"latitude": 91, "longitude": 0}, map[string]any{"latitude": 0, "longitude": 181}} {
		body.(map[string]any)["revision"] = 0
		if w := a.req("PUT", "/api/v1/nearby/location", body); w.Code != 400 {
			t.Fatalf("accepted %v: %d", body, w.Code)
		}
	}
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false})
	if w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 0, "longitude": 0, "revision": 1}); w.Code != 403 {
		t.Fatal(w.Code)
	}
}

func TestNearbyRevisionConcurrentCASAndRestart(t *testing.T) {
	a := newTestAPI(t)
	nearbyUser(t, a, "QA campus")
	var wg sync.WaitGroup
	responses := make(chan int, 16)
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			responses <- a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 30, "longitude": 110, "revision": 0}).Code
		}()
	}
	wg.Wait()
	close(responses)
	published, conflicts := 0, 0
	for code := range responses {
		switch code {
		case 200:
			published++
		case 409:
			conflicts++
		default:
			t.Fatal("unexpected publish status", code)
		}
	}
	if published != 1 || conflicts != 15 {
		t.Fatal("CAS failed", published, conflicts)
	}
	status := decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
	if status["revision"] != float64(1) {
		t.Fatal(status)
	}
	a.req("DELETE", "/api/v1/nearby/location", nil)
	a.req("DELETE", "/api/v1/nearby/location", nil)
	path := a.s.cfg.DBPath
	a.s.Close()
	s, err := NewServer(Config{DBPath: path, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	a.s = s
	a.h = s.Handler()
	status = decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
	if status["revision"] != float64(3) || status["enabled"] != false {
		t.Fatal("restart lost tombstone", status)
	}
	if w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 30, "longitude": 110, "revision": 1}); w.Code != 409 {
		t.Fatal("restart permitted stale publish", w.Code)
	}
	nearbyPut(t, a, 30, 110)
	status = decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
	if status["revision"] != float64(4) || status["enabled"] != true {
		t.Fatal("fresh publication failed", status)
	}
}

func TestNearbyRevisionRequiredAndValidated(t *testing.T) {
	a := newTestAPI(t)
	nearbyUser(t, a, "QA campus")
	for _, revision := range []any{nil, -1, 0.5, "0", true} {
		w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 30, "longitude": 110, "revision": revision})
		if w.Code != 400 {
			t.Fatal("invalid revision accepted", revision, w.Code)
		}
	}
	if w := a.req("PUT", "/api/v1/nearby/location", map[string]any{"latitude": 30, "longitude": 110}); w.Code != 400 {
		t.Fatal("missing revision accepted", w.Code)
	}
	status := decode[map[string]any](t, a.req("GET", "/api/v1/nearby", nil))
	if status["revision"] != float64(0) || status["enabled"] != false {
		t.Fatal("invalid requests mutated state", status)
	}
}
func TestNearbyGreetingConcurrencyAndQuota(t *testing.T) {
	a := newTestAPI(t)
	sender, tok := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	peer, ptok := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	a.token = tok
	var wg sync.WaitGroup
	responses := make(chan *httptest.ResponseRecorder, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); responses <- a.req("POST", "/api/v1/nearby/"+peer+"/greet", map[string]any{}) }()
	}
	wg.Wait()
	close(responses)
	cid := ""
	created := 0
	for w := range responses {
		if w.Code != 200 && w.Code != 201 {
			t.Fatal(w.Code, w.Body.String())
		}
		if w.Code == 201 {
			created++
		}
		c := decode[map[string]any](t, w)
		if cid == "" {
			cid = c["id"].(string)
		}
		if c["id"] != cid {
			t.Fatal("different conversations")
		}
	}
	if created != 1 {
		t.Fatal("created", created)
	}
	a.token = ptok
	w := a.req("GET", "/api/v1/conversations/"+cid+"/messages", nil)
	messages := decode[[]map[string]any](t, w)
	if len(messages) != 1 || messages[0]["body"] != "你好，方便聊聊吗？" || messages[0]["authorId"] != sender {
		t.Fatal(messages)
	}
	for i := 0; i < 10; i++ {
		p, _ := nearbyUser(t, a, "QA campus")
		nearbyPut(t, a, 30, 110)
		a.token = tok
		w = a.req("POST", "/api/v1/nearby/"+p+"/greet", map[string]any{})
		want := 201
		if i == 9 {
			want = 429
		}
		if w.Code != want {
			t.Fatalf("greeting %d: %d %s", i, w.Code, w.Body.String())
		}
	}
	if w = a.req("POST", "/api/v1/nearby/"+peer+"/greet", map[string]any{}); w.Code != 200 {
		t.Fatal("repeat blocked by quota", w.Code)
	}
	p := a.s.cfg.DBPath
	a.s.Close()
	s, e := NewServer(Config{DBPath: p, RateLimit: 10000})
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	a.h = s.Handler()
	a.s = s
	p2, _ := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	a.token = tok
	if w = a.req("POST", "/api/v1/nearby/"+p2+"/greet", map[string]any{}); w.Code != 429 {
		t.Fatal("quota lost after restart", w.Code)
	}
	if w = a.req("DELETE", "/api/v1/me", nil); w.Code != 204 {
		t.Fatal(w.Code)
	}
	for _, table := range []string{"nearby_locations", "nearby_greetings"} {
		var n int
		column := "user_id"
		if table == "nearby_greetings" {
			column = "sender_id"
		}
		e = s.db.QueryRow(fmt.Sprintf("SELECT count(*) FROM %s WHERE %s=?", table, column), sender).Scan(&n)
		if e != nil || n != 0 {
			t.Fatalf("cascade %s: %d %v", table, n, e)
		}
	}
}

func TestNearbyGreetChecksCurrentPermissionsEvenForExistingConversation(t *testing.T) {
	for _, scenario := range []string{"no sender location", "no peer location", "expired sender", "expired peer", "outside radius", "other campus", "sender DM disabled", "peer DM disabled", "sender blocks", "peer blocks", "missing peer"} {
		t.Run(scenario, func(t *testing.T) {
			a := newTestAPI(t)
			sender, tok := nearbyUser(t, a, "QA campus")
			nearbyPut(t, a, 30, 110)
			peer, _ := nearbyUser(t, a, "QA campus")
			nearbyPut(t, a, 30, 110)
			a.token = tok
			w := a.req("POST", "/api/v1/nearby/"+peer+"/greet", map[string]any{})
			if w.Code != 201 {
				t.Fatal(w.Code, w.Body.String())
			}
			var err error
			switch scenario {
			case "no sender location":
				_, err = a.s.db.Exec(`DELETE FROM nearby_locations WHERE user_id=?`, sender)
			case "no peer location":
				_, err = a.s.db.Exec(`DELETE FROM nearby_locations WHERE user_id=?`, peer)
			case "expired sender":
				_, err = a.s.db.Exec(`UPDATE nearby_locations SET expires_at=? WHERE user_id=?`, time.Now().Add(-time.Second).UnixMilli(), sender)
			case "expired peer":
				_, err = a.s.db.Exec(`UPDATE nearby_locations SET expires_at=? WHERE user_id=?`, time.Now().Add(-time.Second).UnixMilli(), peer)
			case "outside radius":
				_, err = a.s.db.Exec(`UPDATE nearby_locations SET latitude=31 WHERE user_id=?`, peer)
			case "other campus":
				_, err = a.s.db.Exec(`UPDATE users SET campus='Other QA campus' WHERE id=?`, peer)
			case "sender DM disabled":
				_, err = a.s.db.Exec(`UPDATE users SET allow_dm=0 WHERE id=?`, sender)
			case "peer DM disabled":
				_, err = a.s.db.Exec(`UPDATE users SET allow_dm=0 WHERE id=?`, peer)
			case "sender blocks":
				_, err = a.s.db.Exec(`INSERT INTO blocks VALUES(?,?)`, sender, peer)
			case "peer blocks":
				_, err = a.s.db.Exec(`INSERT INTO blocks VALUES(?,?)`, peer, sender)
			case "missing peer":
				peer = "missing"
			}
			if err != nil {
				t.Fatal(err)
			}
			// Deliberately supply stale auth data to prove the transaction rereads consent.
			r := httptest.NewRequest(http.MethodPost, "/api/v1/nearby/"+peer+"/greet", strings.NewReader("{}"))
			r.SetPathValue("id", peer)
			r = r.WithContext(context.WithValue(r.Context(), userKey, User{ID: sender, Campus: "QA campus", AllowDM: true}))
			w = httptest.NewRecorder()
			a.s.nearbyGreet(w, r)
			if w.Code != 403 {
				t.Fatalf("expected denial, got %d %s", w.Code, w.Body.String())
			}
			var n int
			if err = a.s.db.QueryRow(`SELECT count(*) FROM dm_messages`).Scan(&n); err != nil || n != 1 {
				t.Fatal("denied request mutated messages", n, err)
			}
		})
	}
}

func TestNearbyConcurrentDailyLimit(t *testing.T) {
	a := newTestAPI(t)
	sender, tok := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	peers := []string{}
	for i := 0; i < 16; i++ {
		peer, _ := nearbyUser(t, a, "QA campus")
		nearbyPut(t, a, 30, 110)
		peers = append(peers, peer)
	}
	a.token = tok
	var wg sync.WaitGroup
	responses := make(chan int, len(peers))
	for _, peer := range peers {
		wg.Add(1)
		go func(peer string) {
			defer wg.Done()
			responses <- a.req("POST", "/api/v1/nearby/"+peer+"/greet", map[string]any{}).Code
		}(peer)
	}
	wg.Wait()
	close(responses)
	created, limited := 0, 0
	for code := range responses {
		switch code {
		case 201:
			created++
		case 429:
			limited++
		default:
			t.Fatal("unexpected response", code)
		}
	}
	if created != 10 || limited != 6 {
		t.Fatal(created, limited)
	}
	var n int
	err := a.s.db.QueryRow(`SELECT count(*) FROM dm_messages WHERE author_id=?`, sender).Scan(&n)
	if err != nil || n != 10 {
		t.Fatal(n, err)
	}
}

func TestNearbyConsentClearingAndSelfGreeting(t *testing.T) {
	a := newTestAPI(t)
	id, _ := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 0, 0)
	if w := a.req("POST", "/api/v1/nearby/"+id+"/greet", map[string]any{}); w.Code != 400 {
		t.Fatal(w.Code)
	}
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": false})
	a.req("PATCH", "/api/v1/me", map[string]any{"allowDM": true})
	w := a.req("GET", "/api/v1/nearby", nil)
	if decode[map[string]any](t, w)["enabled"] != false {
		t.Fatal("reenabling DM republished location")
	}
	for _, raw := range []string{`{"latitude":NaN,"longitude":0}`, `{"latitude":1e999,"longitude":0}`, `{"latitude":0,"longitude":-181}`, `{"latitude":-91,"longitude":0}`} {
		r := httptest.NewRequest("PUT", "/api/v1/nearby/location", strings.NewReader(raw))
		r.Header.Set("Authorization", "Bearer "+a.token)
		w := httptest.NewRecorder()
		a.h.ServeHTTP(w, r)
		if w.Code != 400 {
			t.Fatal("invalid coordinate accepted", raw, w.Code)
		}
	}
	nearbyPut(t, a, 30, 110)
	a.s.db.Exec(`UPDATE nearby_locations SET expires_at=?`, time.Now().Add(-time.Second).UnixMilli())
	w = a.req("GET", "/api/v1/nearby", nil)
	if decode[map[string]any](t, w)["enabled"] != false {
		t.Fatal("expired own location active")
	}
	var n int
	a.s.db.QueryRow(`SELECT count(*) FROM nearby_locations`).Scan(&n)
	if n != 0 {
		t.Fatal("expired locations not removed")
	}
}

func TestNearbyReusesNormalConversationWithoutGreetingOrQuota(t *testing.T) {
	a := newTestAPI(t)
	sender, tok := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	peer, _ := nearbyUser(t, a, "QA campus")
	nearbyPut(t, a, 30, 110)
	first, second := ordered(sender, peer)
	_, err := a.s.db.Exec(`INSERT INTO conversations VALUES('normal',?,?,?)`, first, second, now())
	if err != nil {
		t.Fatal(err)
	}
	a.token = tok
	w := a.req("POST", "/api/v1/nearby/"+peer+"/greet", map[string]any{})
	if w.Code != 200 || decode[map[string]any](t, w)["id"] != "normal" {
		t.Fatal(w.Code, w.Body.String())
	}
	var n int
	for _, table := range []string{"dm_messages", "nearby_greetings"} {
		err = a.s.db.QueryRow("SELECT count(*) FROM " + table).Scan(&n)
		if err != nil || n != 0 {
			t.Fatal("existing conversation mutated", table, n, err)
		}
	}
}
