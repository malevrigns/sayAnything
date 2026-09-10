package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"testing"
	"time"
)

func pngFixture(t *testing.T) []byte {
	t.Helper()
	im := image.NewRGBA(image.Rect(0, 0, 3, 2))
	im.Set(0, 0, color.RGBA{R: 255, A: 255})
	var b bytes.Buffer
	if err := png.Encode(&b, im); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func jpegFixture(t *testing.T) []byte {
	t.Helper()
	im := image.NewRGBA(image.Rect(0, 0, 2, 3))
	im.Set(0, 0, color.RGBA{G: 255, A: 255})
	var b bytes.Buffer
	if err := jpeg.Encode(&b, im, nil); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func mp4Fixture() []byte {
	b := make([]byte, 24)
	binary.BigEndian.PutUint32(b, 24)
	copy(b[4:], "ftyp")
	copy(b[8:], "isom")
	copy(b[12:], []byte{0, 0, 0, 1})
	copy(b[16:], "isommp42")
	return b
}

func (a *testAPI) upload(name string, data []byte) *httptest.ResponseRecorder {
	return a.uploadKey(name, data, "")
}
func (a *testAPI) uploadKey(name string, data []byte, key string) *httptest.ResponseRecorder {
	var b bytes.Buffer
	mw := multipart.NewWriter(&b)
	f, err := mw.CreateFormFile("file", name)
	if err != nil {
		a.t.Fatal(err)
	}
	if _, err = f.Write(data); err != nil {
		a.t.Fatal(err)
	}
	if err = mw.Close(); err != nil {
		a.t.Fatal(err)
	}
	r := httptest.NewRequest("POST", "/api/v1/media", &b)
	r.Header.Set("Content-Type", mw.FormDataContentType())
	r.Header.Set("Authorization", "Bearer "+a.token)
	if key != "" {
		r.Header.Set("X-Upload-Id", key)
	}
	w := httptest.NewRecorder()
	a.h.ServeHTTP(w, r)
	return w
}

func firstCategory() string {
	for k := range postCategories {
		return k
	}
	return ""
}

func TestMediaUploadBindTicketRangeAndDelete(t *testing.T) {
	d := t.TempDir()
	s, err := NewServer(Config{DBPath: filepath.Join(d, "test.db"), MediaDir: filepath.Join(d, "media"), RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	a := &testAPI{t: t, h: s.Handler(), s: s}
	a.session("A")
	w := a.upload("actually.png", pngFixture(t))
	if w.Code != 201 {
		t.Fatalf("upload: %d %s", w.Code, w.Body.String())
	}
	m := decode[Media](t, w)
	if m.Kind != "image" || m.MIMEType != "image/png" || m.Width != 3 || m.Height != 2 || m.Name == "" {
		t.Fatalf("bad media: %+v", m)
	}
	category := firstCategory()
	if w = a.req("POST", "/api/v1/posts", map[string]any{"body": "", "category": category, "mediaIds": []string{m.ID}, "clientId": "post-one"}); w.Code != 201 {
		t.Fatalf("bind: %d %s", w.Code, w.Body.String())
	}
	p := decode[map[string]any](t, w)
	if len(p["attachments"].([]any)) != 1 {
		t.Fatalf("attachments: %v", p)
	}
	pid := p["id"].(string)
	if w = a.req("POST", "/api/v1/posts", map[string]any{"body": "", "category": category, "mediaIds": []string{m.ID}, "clientId": "post-one"}); w.Code != 200 || decode[map[string]any](t, w)["id"] != pid {
		t.Fatalf("retry: %d %s", w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/media/"+m.ID+"/ticket", nil); w.Code != 200 {
		t.Fatalf("ticket: %d %s", w.Code, w.Body.String())
	}
	ticket := decode[map[string]any](t, w)["url"].(string)
	r := httptest.NewRequest("GET", ticket, nil)
	r.Header.Set("Range", "bytes=0-7")
	w = httptest.NewRecorder()
	a.h.ServeHTTP(w, r)
	if w.Code != http.StatusPartialContent || w.Header().Get("Cache-Control") != "private, no-store" || len(w.Body.Bytes()) != 8 {
		t.Fatalf("range: %d %v %d", w.Code, w.Header(), w.Body.Len())
	}
	if w = a.req("DELETE", "/api/v1/media/"+m.ID, nil); w.Code != 409 {
		t.Fatalf("bound delete: %d %s", w.Code, w.Body.String())
	}
	if w = a.req("DELETE", "/api/v1/posts/"+pid, nil); w.Code != 204 {
		t.Fatalf("post delete: %d", w.Code)
	}
	if _, err := os.Stat(filepath.Join(d, "media", m.ID)); !os.IsNotExist(err) {
		t.Fatalf("physical media survived deletion: %v", err)
	}
}

func TestMediaRejectsSpoofAndEnforcesVisibility(t *testing.T) {
	a := newTestAPI(t)
	ua := a.session("A")
	tokA := a.token
	if w := a.upload("fake.png", []byte("<html>bad</html>")); w.Code != 415 {
		t.Fatalf("spoof=%d %s", w.Code, w.Body.String())
	}
	w := a.upload("clip.bin", mp4Fixture())
	if w.Code != 201 {
		t.Fatalf("mp4=%d %s", w.Code, w.Body.String())
	}
	m := decode[Media](t, w)
	w = a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"mediaIds": []string{m.ID}, "clientId": "room-one"})
	if w.Code != 201 {
		t.Fatalf("pure attachment=%d %s", w.Code, w.Body.String())
	}
	a.token = ""
	a.session("B")
	if w = a.req("POST", "/api/v1/media/"+m.ID+"/ticket", nil); w.Code != 404 {
		t.Fatalf("cross campus ticket=%d %s", w.Code, w.Body.String())
	}
	a.token = tokA
	if w = a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"body": "changed", "mediaIds": []string{m.ID}, "clientId": "room-one"}); w.Code != 409 {
		t.Fatalf("idempotency conflict=%d %s", w.Code, w.Body.String())
	}
	_ = ua
}

func TestMediaPersistsAcrossRestartAndQuota(t *testing.T) {
	d := t.TempDir()
	db := filepath.Join(d, "db.sqlite")
	md := filepath.Join(d, "files")
	s, err := NewServer(Config{DBPath: db, MediaDir: md, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	a := &testAPI{t: t, h: s.Handler(), s: s}
	a.session("A")
	tok := a.token
	w := a.upload("x.png", pngFixture(t))
	if w.Code != 201 {
		t.Fatal(w.Body.String())
	}
	id := decode[Media](t, w).ID
	s.Close()
	s, err = NewServer(Config{DBPath: db, MediaDir: md, RateLimit: 10000})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	a.h = s.Handler()
	a.s = s
	a.token = tok
	if w = a.req("POST", "/api/v1/media/"+id+"/ticket", nil); w.Code != 200 {
		t.Fatalf("restart ticket=%d %s", w.Code, w.Body.String())
	}
	var payload map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &payload)
}

func TestJPEGAndUploadIdempotency(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	w := a.uploadKey("wrong.bin", jpegFixture(t), "stable-upload")
	if w.Code != 201 {
		t.Fatalf("jpeg %d %s", w.Code, w.Body.String())
	}
	first := decode[Media](t, w)
	if first.MIMEType != "image/jpeg" || first.Width != 2 || first.Height != 3 {
		t.Fatalf("%+v", first)
	}
	w = a.uploadKey("different.png", pngFixture(t), "stable-upload")
	if w.Code != 200 || decode[Media](t, w).ID != first.ID {
		t.Fatalf("upload retry %d %s", w.Code, w.Body.String())
	}
}

func TestMediaOwnerBindingAndBlockVisibility(t *testing.T) {
	a := newTestAPI(t)
	ua := a.session("A")
	tokA := a.token
	aid := ua["user"].(map[string]any)["id"].(string)
	w := a.upload("x.png", pngFixture(t))
	if w.Code != 201 {
		t.Fatal(w.Body.String())
	}
	m := decode[Media](t, w)
	a.token = ""
	a.session("A")
	tokB := a.token
	if w = a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"mediaIds": []string{m.ID}}); w.Code != 403 {
		t.Fatalf("foreign bind %d %s", w.Code, w.Body.String())
	}
	a.token = tokA
	if w = a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"mediaIds": []string{m.ID}}); w.Code != 201 {
		t.Fatalf("owner bind %d %s", w.Code, w.Body.String())
	}
	a.token = tokB
	if w = a.req("POST", "/api/v1/media/"+m.ID+"/ticket", nil); w.Code != 200 {
		t.Fatalf("visible ticket %d %s", w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/blocks", map[string]any{"userId": aid}); w.Code != 201 {
		t.Fatalf("block %d %s", w.Code, w.Body.String())
	}
	if w = a.req("POST", "/api/v1/media/"+m.ID+"/ticket", nil); w.Code != 404 {
		t.Fatalf("blocked media %d %s", w.Code, w.Body.String())
	}
}

func TestDeletingAccountPurgesPeerMediaInCascadedConversation(t *testing.T) {
	a := newTestAPI(t)
	ua := a.session("A")
	aid := ua["user"].(map[string]any)["id"].(string)
	tokA := a.token
	a.token = ""
	ub := a.session("A")
	bid := ub["user"].(map[string]any)["id"].(string)
	tokB := a.token
	created := now()
	cid := randomID()
	if _, err := a.s.db.Exec(`INSERT INTO conversations(id,user1_id,user2_id,updated_at) VALUES(?,?,?,?)`, cid, aid, bid, created); err != nil {
		t.Fatal(err)
	}
	w := a.upload("peer.png", pngFixture(t))
	if w.Code != 201 {
		t.Fatal(w.Body.String())
	}
	m := decode[Media](t, w)
	if w = a.req("POST", "/api/v1/conversations/"+cid+"/messages", map[string]any{"mediaIds": []string{m.ID}}); w.Code != 201 {
		t.Fatalf("dm %d %s", w.Code, w.Body.String())
	}
	a.token = tokA
	if w = a.req("DELETE", "/api/v1/me", nil); w.Code != 204 {
		t.Fatalf("delete %d %s", w.Code, w.Body.String())
	}
	var dangling int
	if err := a.s.db.QueryRow(`SELECT count(*) FROM attachments x LEFT JOIN dm_messages m ON x.target_type='dm' AND x.target_id=m.id WHERE x.target_type='dm' AND m.id IS NULL`).Scan(&dangling); err != nil || dangling != 0 {
		t.Fatalf("dangling=%d err=%v", dangling, err)
	}
	var remaining int
	if err := a.s.db.QueryRow(`SELECT count(*) FROM media WHERE id=?`, m.ID).Scan(&remaining); err != nil || remaining != 0 {
		t.Fatalf("peer media remains=%d err=%v", remaining, err)
	}
	if _, err := os.Stat(filepath.Join(a.s.cfg.MediaDir, m.ID)); !os.IsNotExist(err) {
		t.Fatalf("peer file remains: %v", err)
	}
	a.token = tokB
}

func TestConcurrentUploadsCannotExceedPendingQuota(t *testing.T) {
	a := newTestAPI(t)
	u := a.session("A")
	uid := u["user"].(map[string]any)["id"].(string)
	seed := randomID()
	if _, err := a.s.db.Exec(`INSERT INTO media(id,owner_id,kind,mime_type,size,path,created_at) VALUES(?,?,?,?,?,?,?)`, seed, uid, "video", "video/mp4", 99<<20, filepath.Join(a.s.cfg.MediaDir, seed), now()); err != nil {
		t.Fatal(err)
	}
	payload := make([]byte, 1<<20)
	copy(payload, mp4Fixture())
	start := make(chan struct{})
	codes := make(chan int, 2)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); <-start; codes <- a.upload("x.mp4", payload).Code }()
	}
	close(start)
	wg.Wait()
	close(codes)
	var got []int
	for c := range codes {
		got = append(got, c)
	}
	sort.Ints(got)
	if len(got) != 2 || got[0] != 201 || got[1] != 413 {
		t.Fatalf("codes=%v", got)
	}
	var used int64
	if err := a.s.db.QueryRow(`SELECT sum(size) FROM media WHERE owner_id=?`, uid).Scan(&used); err != nil || used > pendingQuota {
		t.Fatalf("used=%d err=%v", used, err)
	}
}

func TestDeleteAndBindAreAtomic(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	for i := 0; i < 12; i++ {
		w := a.upload("x.png", pngFixture(t))
		if w.Code != 201 {
			t.Fatal(w.Body.String())
		}
		id := decode[Media](t, w).ID
		start := make(chan struct{})
		codes := make(chan int, 2)
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); <-start; codes <- a.req("DELETE", "/api/v1/media/"+id, nil).Code }()
		go func() {
			defer wg.Done()
			<-start
			codes <- a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"mediaIds": []string{id}}).Code
		}()
		close(start)
		wg.Wait()
		close(codes)
		var got []int
		for c := range codes {
			got = append(got, c)
		}
		sort.Ints(got)
		if !(got[0] == 201 && got[1] == 409) && !(got[0] == 204 && got[1] == 403) {
			t.Fatalf("iteration %d codes=%v", i, got)
		}
		var media, attached int
		_ = a.s.db.QueryRow(`SELECT count(*) FROM media WHERE id=?`, id).Scan(&media)
		_ = a.s.db.QueryRow(`SELECT count(*) FROM attachments WHERE media_id=?`, id).Scan(&attached)
		if media != attached {
			t.Fatalf("iteration %d media=%d attachment=%d", i, media, attached)
		}
	}
}

func TestOrphanCleanupCannotDeleteConcurrentlyBoundMedia(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	for i := 0; i < 8; i++ {
		w := a.upload("x.png", pngFixture(t))
		if w.Code != 201 {
			t.Fatal(w.Body.String())
		}
		id := decode[Media](t, w).ID
		if _, err := a.s.db.Exec(`UPDATE media SET created_at=? WHERE id=?`, time.Now().UTC().Add(-48*time.Hour).Format(time.RFC3339Nano), id); err != nil {
			t.Fatal(err)
		}
		start := make(chan struct{})
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); <-start; a.s.cleanupOrphans() }()
		go func() {
			defer wg.Done()
			<-start
			_ = a.req("POST", "/api/v1/rooms/treehole/messages", map[string]any{"mediaIds": []string{id}})
		}()
		close(start)
		wg.Wait()
		var media, attached int
		_ = a.s.db.QueryRow(`SELECT count(*) FROM media WHERE id=?`, id).Scan(&media)
		_ = a.s.db.QueryRow(`SELECT count(*) FROM attachments WHERE media_id=?`, id).Scan(&attached)
		if media != attached {
			t.Fatalf("iteration %d media=%d attachment=%d", i, media, attached)
		}
	}
}
