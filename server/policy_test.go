package main

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

type publishedPolicy struct {
	Categories []string `json:"categories"`
	Limits     struct {
		Post    int `json:"postCharacters"`
		Message int `json:"messageCharacters"`
		Campus  int `json:"campusCharacters"`
		Alias   int `json:"aliasCharacters"`
	} `json:"limits"`
	Media struct {
		Count  int      `json:"maxAttachments"`
		Image  int64    `json:"maxImageBytes"`
		Video  int64    `json:"maxVideoBytes"`
		Total  int64    `json:"maxTotalBytes"`
		Images []string `json:"imageExtensions"`
		Videos []string `json:"videoExtensions"`
	} `json:"media"`
}

func TestPublicPolicyMatchesWriteValidation(t *testing.T) {
	a := newTestAPI(t)
	w := a.req("GET", "/api/v1/config", nil)
	if w.Code != 200 {
		t.Fatalf("public config: %d %s", w.Code, w.Body.String())
	}
	p := decode[publishedPolicy](t, w)
	if !reflect.DeepEqual(p.Categories, []string{"校园日常", "心事树洞", "搭子集合", "恋爱碎碎念", "学习交流"}) || p.Limits.Post != 1000 || p.Limits.Message != 2000 || p.Limits.Campus != 80 || p.Limits.Alias != 40 || p.Media.Count != 4 || p.Media.Image != 10<<20 || p.Media.Video != 50<<20 || p.Media.Total != 50<<20 || !reflect.DeepEqual(p.Media.Images, []string{"jpg", "jpeg", "png", "webp"}) || !reflect.DeepEqual(p.Media.Videos, []string{"mp4", "webm"}) {
		t.Fatalf("unexpected policy: %s", w.Body.String())
	}
	if w := a.req("POST", "/api/v1/session", map[string]any{"campus": strings.Repeat("校", p.Limits.Campus+1)}); w.Code != 400 {
		t.Fatalf("campus overflow: %d", w.Code)
	}
	owner := a.session(strings.Repeat("校", p.Limits.Campus))["user"].(map[string]any)["id"].(string)
	ownerToken := a.token
	peer := a.session(strings.Repeat("校", p.Limits.Campus))["user"].(map[string]any)["id"].(string)
	cid := seedPolicyConversation(t, a, owner, peer, "")
	a.token = ownerToken
	for _, n := range []int{p.Limits.Alias, p.Limits.Alias + 1} {
		want := 200
		if n > p.Limits.Alias {
			want = 400
		}
		if w := a.req("PATCH", "/api/v1/me", map[string]any{"alias": strings.Repeat("名", n)}); w.Code != want {
			t.Fatalf("alias %d: %d %s", n, w.Code, w.Body.String())
		}
	}
	var pid string
	for _, c := range append(append([]string{}, p.Categories...), "unknown") {
		want := 201
		if c == "unknown" {
			want = 400
		}
		w := a.req("POST", "/api/v1/posts", map[string]any{"body": strings.Repeat("文", p.Limits.Post), "category": c})
		if w.Code != want {
			t.Fatalf("category %q: %d %s", c, w.Code, w.Body.String())
		}
		if want == 201 {
			pid = decode[map[string]any](t, w)["id"].(string)
		}
	}
	if w := a.req("POST", "/api/v1/posts", map[string]any{"body": strings.Repeat("文", p.Limits.Post+1), "category": p.Categories[0]}); w.Code != 400 {
		t.Fatalf("post overflow: %d", w.Code)
	}
	for _, path := range []string{"/api/v1/posts/" + pid + "/comments", "/api/v1/rooms/treehole/messages", "/api/v1/conversations/" + cid + "/messages"} {
		for _, n := range []int{p.Limits.Message, p.Limits.Message + 1} {
			want := 201
			if n > p.Limits.Message {
				want = 400
			}
			if w := a.req("POST", path, map[string]any{"body": strings.Repeat("文", n)}); w.Code != want {
				t.Fatalf("message %s %d: %d %s", path, n, w.Code, w.Body.String())
			}
		}
	}
	ids := make([]string, p.Media.Count+1)
	if w := a.req("POST", "/api/v1/posts", map[string]any{"body": "x", "category": p.Categories[0], "mediaIds": ids}); w.Code != 400 {
		t.Fatalf("attachment count overflow: %d", w.Code)
	}
}

func seedPolicyConversation(t *testing.T, a *testAPI, u1, u2, body string) string {
	t.Helper()
	u1, u2 = ordered(u1, u2)
	id := randomID()
	if _, err := a.s.db.Exec(`INSERT INTO conversations(id,user1_id,user2_id,updated_at) VALUES(?,?,?,?)`, id, u1, u2, now()); err != nil {
		t.Fatal(err)
	}
	if body != "" {
		if _, err := a.s.db.Exec(`INSERT INTO dm_messages(id,conversation_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, randomID(), id, u2, body, "2020-01-01T00:00:00Z"); err != nil {
			t.Fatal(err)
		}
	}
	return id
}

func TestConversationSearchScopeHistoryLiteralAndUnread(t *testing.T) {
	a := newTestAPI(t)
	if w := a.req("GET", "/api/v1/conversations?q=secret", nil); w.Code != 401 {
		t.Fatalf("anonymous search: %d", w.Code)
	}
	users := make([]string, 5)
	tokens := make([]string, 5)
	for i := range users {
		campus := "A"
		if i == 4 {
			campus = "B"
		}
		v := a.session(campus)
		users[i] = v["user"].(map[string]any)["id"].(string)
		tokens[i] = a.token
	}
	if _, err := a.s.db.Exec(`UPDATE users SET alias=? WHERE id=?`, "PeerAliasÉ", users[1]); err != nil {
		t.Fatal(err)
	}
	cid := seedPolicyConversation(t, a, users[0], users[1], strings.Repeat("前", 300)+"needle café 100% a_b <tag>"+strings.Repeat("后", 300))
	seedPolicyConversation(t, a, users[0], users[2], "unrelated")
	seedPolicyConversation(t, a, users[2], users[3], "private-only needle")
	seedPolicyConversation(t, a, users[3], users[4], "other-campus-only needle")
	tx, err := a.s.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 505; i++ {
		if _, err = tx.Exec(`INSERT INTO dm_messages(id,conversation_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, randomID(), cid, users[1], "recent unrelated", fmt.Sprintf("2030-01-01T00:%02d:%02dZ", i/60, i%60)); err != nil {
			tx.Rollback()
			t.Fatal(err)
		}
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	a.token = tokens[0]
	for _, tc := range []struct {
		q     string
		count int
	}{{"needle", 1}, {"NEEDLE", 1}, {"CAFÉ", 1}, {"PeerAlias", 1}, {"peeraliasé", 1}, {"%", 1}, {"_", 1}, {"100%", 1}, {"a_b", 1}, {"missing", 0}, {"private-only", 0}, {"other-campus-only", 0}, {"%_", 0}} {
		t.Run(tc.q, func(t *testing.T) {
			w := a.req("GET", "/api/v1/conversations?q="+url.QueryEscape(tc.q), nil)
			if w.Code != 200 {
				t.Fatalf("search: %d %s", w.Code, w.Body.String())
			}
			got := decode[[]map[string]any](t, w)
			if len(got) != tc.count {
				t.Fatalf("query %q: %s", tc.q, w.Body.String())
			}
			if tc.count == 1 {
				snippet, _ := got[0]["matchSnippet"].(string)
				if got[0]["id"] != cid || !strings.Contains(strings.ToLower(snippet), strings.ToLower(tc.q)) || len([]rune(snippet)) > 160 || got[0]["lastMessage"] != "recent unrelated" {
					t.Fatalf("invalid match: %v", got[0])
				}
				if got[0]["unread"].(float64) < 505 {
					t.Fatalf("search read messages: %v", got[0])
				}
			}
		})
	}
	var reads int
	if err := a.s.db.QueryRow(`SELECT count(*) FROM reads WHERE user_id=?`, users[0]).Scan(&reads); err != nil || reads != 0 {
		t.Fatalf("search wrote read state: %d %v", reads, err)
	}
	w := a.req("GET", "/api/v1/conversations?q=", nil)
	list := decode[[]map[string]any](t, w)
	if len(list) != 2 {
		t.Fatalf("empty query: %s", w.Body.String())
	}
	for _, c := range list {
		if _, ok := c["matchSnippet"]; ok {
			t.Fatal("empty query changed DTO")
		}
	}
	for _, pair := range [][2]string{{users[0], users[1]}, {users[1], users[0]}} {
		if _, err := a.s.db.Exec(`INSERT INTO blocks(blocker_id,blocked_id) VALUES(?,?)`, pair[0], pair[1]); err != nil {
			t.Fatal(err)
		}
		w := a.req("GET", "/api/v1/conversations?q=needle", nil)
		if len(decode[[]map[string]any](t, w)) != 0 {
			t.Fatalf("blocked search: %s", w.Body.String())
		}
		if _, err := a.s.db.Exec(`DELETE FROM blocks`); err != nil {
			t.Fatal(err)
		}
	}
}

func TestAggregateMediaLimitAllWritePaths(t *testing.T) {
	for _, kind := range []string{"post", "comment", "room", "dm"} {
		t.Run(kind, func(t *testing.T) {
			a := newTestAPI(t)
			v := a.session("A")
			owner := v["user"].(map[string]any)["id"].(string)
			token := a.token
			w := a.req("POST", "/api/v1/posts", map[string]any{"body": "parent", "category": "校园日常"})
			if w.Code != 201 {
				t.Fatal(w.Body.String())
			}
			pid := decode[map[string]any](t, w)["id"].(string)
			other := a.session("A")["user"].(map[string]any)["id"].(string)
			cid := seedPolicyConversation(t, a, owner, other, "")
			a.token = token
			path := map[string]string{"post": "/api/v1/posts", "comment": "/api/v1/posts/" + pid + "/comments", "room": "/api/v1/rooms/treehole/messages", "dm": "/api/v1/conversations/" + cid + "/messages"}[kind]
			ids := []string{randomID(), randomID()}
			for _, id := range ids {
				if _, err := a.s.db.Exec(`INSERT INTO media(id,owner_id,kind,mime_type,size,path,created_at) VALUES(?,?,'video','video/mp4',?,?,?)`, id, owner, int64(25<<20)+1, "fixture-"+id, now()); err != nil {
					t.Fatal(err)
				}
			}
			body := map[string]any{"body": "limit check", "mediaIds": ids, "clientId": "retry-after-size-fix"}
			if kind == "post" {
				body["category"] = "校园日常"
			}
			w = a.req("POST", path, body)
			if w.Code != 413 {
				t.Fatalf("aggregate overflow bypass: %d %s", w.Code, w.Body.String())
			}
			for _, query := range []string{`SELECT count(*) FROM attachments`, `SELECT count(*) FROM client_requests`, `SELECT count(*) FROM posts WHERE body='limit check'`, `SELECT count(*) FROM comments`, `SELECT count(*) FROM room_messages`, `SELECT count(*) FROM dm_messages`} {
				var n int
				if err := a.s.db.QueryRow(query).Scan(&n); err != nil || n != 0 {
					t.Fatalf("failed transaction persisted: %s = %d (%v)", query, n, err)
				}
			}
			if _, err := a.s.db.Exec(`UPDATE media SET size=?`, int64(25<<20)); err != nil {
				t.Fatal(err)
			}
			w = a.req("POST", path, body)
			if w.Code != 201 {
				t.Fatalf("exact aggregate boundary/retry: %d %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestDownloadVariantsUseExplicitAllowlist(t *testing.T) {
	a := newTestAPI(t)
	a.s.cfg.DownloadDir = t.TempDir()
	files := map[string]string{"android": "sayanything-android.apk", "androidArm64": "sayanything-android-arm64.apk", "androidArmv7": "sayanything-android-armv7.apk", "androidX64": "sayanything-android-x64.apk", "windows": "sayanything-windows.zip"}
	w := a.req("GET", "/api/downloads", nil)
	flags := decode[map[string]bool](t, w)
	for key, file := range files {
		if flag, ok := flags[key]; !ok || flag {
			t.Errorf("missing/incorrect absent flag %s: %v", key, flags)
		}
		if err := os.WriteFile(filepath.Join(a.s.cfg.DownloadDir, file), []byte(file), 0600); err != nil {
			t.Fatal(err)
		}
	}
	w = a.req("GET", "/api/downloads", nil)
	flags = decode[map[string]bool](t, w)
	for key, file := range files {
		if !flags[key] {
			t.Errorf("missing available flag %s", key)
		}
		w = a.req("GET", "/downloads/"+file, nil)
		if w.Code != 200 || w.Body.String() != file {
			t.Errorf("download %s: %d %s", file, w.Code, w.Body.String())
		}
	}
	if err := os.WriteFile(filepath.Join(a.s.cfg.DownloadDir, "private.apk"), []byte("private"), 0600); err != nil {
		t.Fatal(err)
	}
	if w := a.req("GET", "/downloads/private.apk", nil); w.Code != 404 {
		t.Fatalf("allowlist bypass: %d", w.Code)
	}
}
