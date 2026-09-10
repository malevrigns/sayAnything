package main

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestPostDeleteFailurePreservesAttachments(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	m := decode[Media](t, a.upload("x.png", pngFixture(t)))
	w := a.req("POST", "/api/v1/posts", map[string]any{"category": firstCategory(), "mediaIds": []string{m.ID}})
	if w.Code != 201 {
		t.Fatal(w.Body.String())
	}
	id := decode[Post](t, w).ID
	if _, err := a.s.db.Exec(`CREATE TRIGGER reject_post_delete BEFORE DELETE ON posts BEGIN SELECT RAISE(ABORT, 'test deletion failure'); END`); err != nil {
		t.Fatal(err)
	}
	if w = a.req("DELETE", "/api/v1/posts/"+id, nil); w.Code != 500 {
		t.Fatalf("status=%d", w.Code)
	}
	if w = a.req("GET", "/api/v1/media/"+m.ID, nil); w.Code != 200 {
		t.Fatalf("failed deletion lost attachment: status=%d", w.Code)
	}
}

func TestAccountDeleteFailurePreservesMedia(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	m := decode[Media](t, a.upload("x.png", pngFixture(t)))
	if _, err := a.s.db.Exec(`CREATE TRIGGER reject_user_delete BEFORE DELETE ON users BEGIN SELECT RAISE(ABORT, 'test deletion failure'); END`); err != nil {
		t.Fatal(err)
	}
	if w := a.req("DELETE", "/api/v1/me", nil); w.Code != 500 {
		t.Fatalf("status=%d", w.Code)
	}
	if w := a.req("GET", "/api/v1/media/"+m.ID, nil); w.Code != 200 {
		t.Fatalf("failed deletion lost media: status=%d", w.Code)
	}
}

func assertNoLostMediaFiles(t *testing.T, a *testAPI) {
	t.Helper()
	files, err := os.ReadDir(a.s.cfg.MediaDir)
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		var n int
		if err := a.s.db.QueryRow(`SELECT count(*) FROM media WHERE path=?`, filepath.Join(a.s.cfg.MediaDir, f.Name())).Scan(&n); err != nil || n != 1 {
			t.Fatalf("file without metadata: %s count=%d err=%v", f.Name(), n, err)
		}
	}
	var dangling int
	err = a.s.db.QueryRow(`SELECT count(*) FROM attachments a WHERE a.target_type='comment' AND NOT EXISTS(SELECT 1 FROM comments c WHERE c.id=a.target_id)`).Scan(&dangling)
	if err != nil || dangling != 0 {
		t.Fatalf("dangling comment attachments=%d err=%v", dangling, err)
	}
}

func TestAccountDeleteConcurrentUploadLeavesNoFiles(t *testing.T) {
	for i := 0; i < 12; i++ {
		a := newTestAPI(t)
		a.session("A")
		payload := pngFixture(t)
		start := make(chan struct{})
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); <-start; a.upload("x.png", payload) }()
		go func() { defer wg.Done(); <-start; a.req("DELETE", "/api/v1/me", nil) }()
		close(start)
		wg.Wait()
		assertNoLostMediaFiles(t, a)
	}
}

func TestPostDeleteConcurrentCommentLeavesNoDanglingMedia(t *testing.T) {
	a := newTestAPI(t)
	a.session("A")
	for i := 0; i < 20; i++ {
		w := a.req("POST", "/api/v1/posts", map[string]any{"category": firstCategory(), "body": "post"})
		if w.Code != 201 {
			t.Fatal(w.Body.String())
		}
		id := decode[Post](t, w).ID
		m := decode[Media](t, a.upload("x.png", pngFixture(t)))
		start := make(chan struct{})
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			a.req("POST", "/api/v1/posts/"+id+"/comments", map[string]any{"mediaIds": []string{m.ID}})
		}()
		go func() { defer wg.Done(); <-start; a.req("DELETE", "/api/v1/posts/"+id, nil) }()
		close(start)
		wg.Wait()
		assertNoLostMediaFiles(t, a)
	}
}
