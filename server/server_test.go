package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type testAPI struct {
	t     *testing.T
	h     http.Handler
	s     *Server
	token string
}

func newTestAPI(t *testing.T) *testAPI {
	t.Helper()
	s, err := NewServer(Config{DBPath: filepath.Join(t.TempDir(), "test.db"), RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return &testAPI{t: t, h: s.Handler(), s: s}
}
func (a *testAPI) req(method, path string, body any) *httptest.ResponseRecorder {
	var b bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&b).Encode(body); err != nil {
			a.t.Fatal(err)
		}
	}
	r := httptest.NewRequest(method, path, &b)
	r.Header.Set("Content-Type", "application/json")
	if a.token != "" {
		r.Header.Set("Authorization", "Bearer "+a.token)
	}
	w := httptest.NewRecorder()
	a.h.ServeHTTP(w, r)
	return w
}
func (a *testAPI) session(campus string) map[string]any {
	w := a.req("POST", "/api/v1/session", map[string]any{"campus": campus})
	if w.Code != 201 {
		a.t.Fatalf("session: %d %s", w.Code, w.Body.String())
	}
	var v map[string]any
	json.Unmarshal(w.Body.Bytes(), &v)
	a.token = v["token"].(string)
	return v
}
func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestHealthSessionAndProfile(t *testing.T) {
	a := newTestAPI(t)
	w := a.req("GET", "/api/v1/me", nil)
	if w.Code != http.StatusUnauthorized || decode[map[string]string](t, w)["error"] != "请先登录" {
		t.Fatalf("unexpected authentication error: %d %s", w.Code, w.Body.String())
	}
	if w := a.req("GET", "/health", nil); w.Code != 200 {
		t.Fatal(w.Code)
	}
	v := a.session("Test University")
	if v["token"] == "" {
		t.Fatal("empty token")
	}
	if !strings.HasPrefix(v["user"].(map[string]any)["alias"].(string), "同学") {
		t.Fatalf("unexpected generated alias: %v", v["user"])
	}
	var expires string
	h := sha256String(v["token"].(string))
	if err := a.s.db.QueryRow(`SELECT expires_at FROM sessions WHERE token_hash=?`, h).Scan(&expires); err != nil {
		t.Fatal(err)
	}
	expiry, _ := time.Parse(time.RFC3339Nano, expires)
	if remaining := time.Until(expiry); remaining < 29*24*time.Hour || remaining > 31*24*time.Hour {
		t.Fatalf("unexpected session lifetime: %v", remaining)
	}
	w = a.req("PATCH", "/api/v1/me", map[string]any{"alias": "Leaf", "allowDM": false})
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	u := decode[map[string]any](t, w)
	if u["alias"] != "Leaf" || u["allowDM"] != false {
		t.Fatalf("%v", u)
	}
}

func TestRejectsUnknownReportTarget(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	w := a.req("POST", "/api/v1/reports", map[string]any{"targetType": "post", "targetId": "missing", "reason": "spam"})
	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d %s", w.Code, w.Body.String())
	}
}

func TestPostsCommentsLikesSavesAndIsolation(t *testing.T) {
	a := newTestAPI(t)
	sa := a.session("A")
	aid := sa["user"].(map[string]any)["id"].(string)
	w := a.req("POST", "/api/v1/posts", map[string]any{"body": "hello", "category": "校园日常"})
	if w.Code != 201 {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	p := decode[map[string]any](t, w)
	pid := p["id"].(string)
	if w = a.req("POST", "/api/v1/posts/"+pid+"/like", nil); w.Code != 200 || decode[map[string]any](t, w)["active"] != true {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/posts/"+pid+"/save", nil); w.Code != 200 {
		t.Fatal(w.Code)
	}
	if w = a.req("POST", "/api/v1/posts/"+pid+"/comments", map[string]any{"body": "reply"}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = a.req("GET", "/api/v1/posts?saved=1&mine=1", nil); w.Code != 200 || len(decode[[]map[string]any](t, w)) != 1 {
		t.Fatal(w.Code, w.Body.String())
	}
	a.token = ""
	sb := a.session("B")
	if sb["user"].(map[string]any)["id"] == aid {
		t.Fatal("same id")
	}
	if w = a.req("GET", "/api/v1/posts", nil); len(decode[[]map[string]any](t, w)) != 0 {
		t.Fatal("cross-campus post visible")
	}
}

func TestRoomsDMBlocksReportsDeleteAndPersistence(t *testing.T) {
	db := filepath.Join(t.TempDir(), "persist.db")
	s, err := NewServer(Config{DBPath: db, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	a := &testAPI{t: t, h: s.Handler()}
	ua := a.session("A")
	tokA := a.token
	w := a.req("GET", "/api/v1/rooms", nil)
	rooms := decode[[]map[string]any](t, w)
	if len(rooms) != 4 {
		t.Fatalf("rooms=%d", len(rooms))
	}
	rid := rooms[0]["id"].(string)
	if w = a.req("POST", "/api/v1/rooms/"+rid+"/messages", map[string]any{"body": "room hi"}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	for i := 0; i < 205; i++ {
		at := fmt.Sprintf("2030-01-01T00:%02d:%02dZ", i/60, i%60)
		if _, err := s.db.Exec(`INSERT INTO room_messages(id,room_id,campus,author_id,body,created_at) VALUES(?,?,?,?,?,?)`, fmt.Sprintf("room-%03d", i), rid, "A", ua["user"].(map[string]any)["id"], fmt.Sprintf("room %03d", i), at); err != nil {
			t.Fatal(err)
		}
	}
	if w = a.req("GET", "/api/v1/rooms/"+rid+"/messages", nil); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	} else if messages := decode[[]map[string]any](t, w); len(messages) != 200 || messages[0]["body"] != "room 005" || messages[199]["body"] != "room 204" {
		t.Fatalf("unexpected room window: len=%d first=%v last=%v", len(messages), messages[0], messages[len(messages)-1])
	}
	if w = a.req("GET", "/api/v1/rooms/"+rid+"/messages?after=2030-01-01T00:03:23Z", nil); len(decode[[]map[string]any](t, w)) != 1 {
		t.Fatalf("room cursor: %s", w.Body.String())
	}
	a.token = ""
	ub := a.session("A")
	bid := ub["user"].(map[string]any)["id"].(string)
	a.token = tokA
	if w = a.req("POST", "/api/v1/posts", map[string]any{"body": "dm me", "category": "校园日常"}); w.Code != 201 {
		t.Fatal(w.Code)
	}
	pid := decode[map[string]any](t, w)["id"].(string)
	a.token = ub["token"].(string)
	if w = a.req("POST", "/api/v1/conversations", map[string]any{"postId": pid}); w.Code != 201 {
		t.Fatalf("conv %d %s", w.Code, w.Body.String())
	}
	cid := decode[map[string]any](t, w)["id"].(string)
	if w = a.req("POST", "/api/v1/conversations/"+cid+"/messages", map[string]any{"body": "hi"}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	for i := 0; i < 505; i++ {
		at := fmt.Sprintf("2031-01-01T00:%02d:%02dZ", i/60, i%60)
		if _, err := s.db.Exec(`INSERT INTO dm_messages(id,conversation_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, fmt.Sprintf("dm-%03d", i), cid, bid, fmt.Sprintf("dm %03d", i), at); err != nil {
			t.Fatal(err)
		}
	}
	if w = a.req("GET", "/api/v1/conversations/"+cid+"/messages", nil); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	} else if messages := decode[[]map[string]any](t, w); len(messages) != 500 || messages[0]["body"] != "dm 005" || messages[499]["body"] != "dm 504" {
		t.Fatalf("unexpected dm window: len=%d first=%v last=%v", len(messages), messages[0], messages[len(messages)-1])
	}
	if w = a.req("GET", "/api/v1/conversations/"+cid+"/messages?after=2031-01-01T00:08:23Z", nil); len(decode[[]map[string]any](t, w)) != 1 {
		t.Fatalf("dm cursor: %s", w.Body.String())
	}
	if w = a.req("GET", "/api/v1/conversations", nil); w.Code != 200 || len(decode[[]map[string]any](t, w)) != 1 {
		t.Fatalf("list conversations: %d %s", w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/blocks", map[string]any{"userId": ua["user"].(map[string]any)["id"]}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/conversations/"+cid+"/messages", map[string]any{"body": "blocked"}); w.Code != 403 {
		t.Fatalf("want 403 got %d", w.Code)
	}
	if w = a.req("POST", "/api/v1/reports", map[string]any{"targetType": "user", "targetId": bid, "reason": "test"}); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	s.Close()
	s2, err := NewServer(Config{DBPath: db, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	a.h = s2.Handler()
	a.token = tokA
	if w = a.req("GET", "/api/v1/rooms/"+rid+"/messages", nil); len(decode[[]map[string]any](t, w)) != 200 {
		t.Fatal(w.Body.String())
	}
	if w = a.req("DELETE", "/api/v1/me", nil); w.Code != 204 {
		t.Fatal(w.Code, w.Body.String())
	}
	var orphanReads int
	if err := s2.db.QueryRow(`SELECT count(*) FROM reads`).Scan(&orphanReads); err != nil || orphanReads != 0 {
		t.Fatalf("orphaned read markers after account deletion: count=%d err=%v", orphanReads, err)
	}
	if w = a.req("GET", "/api/v1/me", nil); w.Code != 401 {
		t.Fatalf("token survived: %d", w.Code)
	}
}
