package main

import (
	"bytes"
	"context"
	"errors"
	"image/jpeg"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestPosterOutputLimitAlsoBoundsStreamCopies(t *testing.T) {
	var output posterBuffer
	// Match exec's pipe-to-writer copy path, including io.ReaderFrom dispatch.
	source := io.LimitReader(bytes.NewReader(make([]byte, posterMaxBytes+1)), posterMaxBytes+1)
	if _, err := io.Copy(&output, source); err == nil {
		t.Fatal("decoder stream bypassed poster output size limit")
	}
}

func realVideoFixture(t *testing.T) []byte {
	t.Helper()
	tool := os.Getenv("FFMPEG_PATH")
	if tool == "" {
		tool = "ffmpeg"
	}
	if _, err := exec.LookPath(tool); err != nil {
		t.Skip("real video tests require FFmpeg via FFMPEG_PATH or PATH")
	}
	b, err := os.ReadFile(filepath.Join("..", "artifacts", "media-fixtures", "bee.mp4"))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestPosterCorruptVideoFallsBackAndImageHasNoVideoPoster(t *testing.T) {
	realVideoFixture(t) // Require the real decoder for the corrupt-input branch.
	a := newTestAPI(t)
	a.session("A")
	for _, data := range [][]byte{mp4Fixture(), pngFixture(t)} {
		w := a.upload("media.bin", data)
		if w.Code != 201 {
			t.Fatal(w.Code, w.Body.String())
		}
		m := decode[Media](t, w)
		if w = a.req("GET", "/api/v1/media/"+m.ID+"?view=poster", nil); w.Code != 404 {
			t.Fatalf("poster fallback: %d %s", w.Code, w.Body.String())
		}
		if w = a.req("GET", "/api/v1/media/"+m.ID, nil); w.Code != 200 {
			t.Fatalf("original unavailable: %d", w.Code)
		}
	}
}

func TestPosterDemuxerDoesNotFollowUploadedPlaylist(t *testing.T) {
	realVideoFixture(t)
	var fetched atomic.Int32
	trap := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fetched.Add(1); w.WriteHeader(404) }))
	defer trap.Close()
	path := filepath.Join(t.TempDir(), "untrusted")
	if err := os.WriteFile(path, []byte("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\n"+trap.URL+"/segment.ts\n#EXT-X-ENDLIST\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, mime := range []string{"video/mp4", "video/webm"} {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		_, err := renderPoster(ctx, path, mime)
		cancel()
		if !errors.Is(err, errPosterMissing) {
			t.Fatalf("unexpected playlist result: %v", err)
		}
	}
	if fetched.Load() != 0 {
		t.Fatal("decoder followed untrusted URL")
	}
}

func TestPosterPublicationRechecksDeletionAfterDecode(t *testing.T) {
	video := realVideoFixture(t)
	a := newTestAPI(t)
	u := a.session("A")
	id := randomID()
	path := filepath.Join(a.s.cfg.MediaDir, id)
	if err := os.WriteFile(path, video, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := a.s.db.Exec(`INSERT INTO media(id,owner_id,kind,mime_type,size,path,created_at) VALUES(?,?,?,?,?,?,?)`, id, u["user"].(map[string]any)["id"], "video", "video/mp4", len(video), path, now()); err != nil {
		t.Fatal(err)
	}
	// Hold the database connection so that decoding completes before the
	// deletion commits, then let publication attempt its metadata recheck.
	conn, err := a.s.db.Conn(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	done := make(chan error, 1)
	go func() {
		_, err := a.s.ensurePoster(context.Background(), Media{ID: id, Kind: "video", MIMEType: "video/mp4"}, path)
		done <- err
	}()
	deadline := time.Now().Add(5 * time.Second)
	for {
		files, err := filepath.Glob(filepath.Join(a.s.cfg.MediaDir, ".poster-*"))
		if err != nil {
			t.Fatal(err)
		}
		if len(files) != 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("decoder did not create temporary JPEG")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if _, err := conn.ExecContext(context.Background(), `DELETE FROM media WHERE id=?`, id); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	conn.Close()
	if err := <-done; !errors.Is(err, errPosterMissing) {
		t.Fatalf("published deleted media: %v", err)
	}
	files, err := os.ReadDir(a.s.cfg.MediaDir)
	if err != nil || len(files) != 0 {
		t.Fatalf("files after deleted-media publication: %v %v", files, err)
	}
}

func assertPosterJPEG(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	if w.Code != 200 || w.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("poster: %d %v %s", w.Code, w.Header(), w.Body.String())
	}
	if w.Header().Get("Cache-Control") != "private, no-store" {
		t.Fatal("poster must remain private")
	}
	im, err := jpeg.Decode(bytes.NewReader(w.Body.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if im.Bounds().Dx() > 640 || im.Bounds().Dy() > 640 || w.Body.Len() > 1<<20 {
		t.Fatalf("unbounded poster: %v %d", im.Bounds(), w.Body.Len())
	}
}

func TestPosterUnavailableDoesNotBreakOriginalVideo(t *testing.T) {
	t.Setenv("FFMPEG_PATH", filepath.Join(t.TempDir(), "missing-ffmpeg"))
	a := newTestAPI(t)
	a.session("A")
	w := a.upload("clip.mp4", mp4Fixture())
	if w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	m := decode[Media](t, w)
	if w = a.req("GET", "/api/v1/media/"+m.ID+"?view=poster", nil); w.Code != 503 {
		t.Fatalf("missing FFmpeg: %d %s", w.Code, w.Body.String())
	}
	if w = a.req("GET", "/api/v1/media/"+m.ID, nil); w.Code != 200 || !bytes.Equal(w.Body.Bytes(), mp4Fixture()) {
		t.Fatalf("original: %d", w.Code)
	}
}

func TestPosterNewUploadTicketVisibilityAndDeletion(t *testing.T) {
	video := realVideoFixture(t)
	a := newTestAPI(t)
	u := a.session("A")
	uid := u["user"].(map[string]any)["id"].(string)
	ownerToken := a.token
	w := a.upload("bee.mp4", video)
	if w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	m := decode[Media](t, w)
	path := filepath.Join(a.s.cfg.MediaDir, m.ID)
	if _, err := os.Stat(path + ".poster.jpg"); err != nil {
		t.Fatalf("new upload has no poster: %v", err)
	}
	url := "/api/v1/media/" + m.ID + "?view=poster"
	assertPosterJPEG(t, a.req("GET", url, nil))
	if w = a.req("HEAD", url, nil); w.Code != 200 || w.Body.Len() != 0 {
		t.Fatalf("HEAD: %d", w.Code)
	}
	a.token = ""
	if w = a.req("GET", url, nil); w.Code != 401 {
		t.Fatalf("anonymous: %d", w.Code)
	}
	a.session("A")
	peerToken := a.token
	if w = a.req("GET", url, nil); w.Code != 404 {
		t.Fatalf("foreign draft: %d", w.Code)
	}
	a.token = ownerToken
	w = a.req("POST", "/api/v1/posts", map[string]any{"category": firstCategory(), "mediaIds": []string{m.ID}})
	if w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
	postID := decode[Post](t, w).ID
	a.token = peerToken
	w = a.req("POST", "/api/v1/media/"+m.ID+"/ticket", nil)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	ticket := decode[map[string]any](t, w)
	posterURL, ok := ticket["posterUrl"].(string)
	if !ok || !strings.Contains(posterURL, "view=poster") {
		t.Fatalf("missing poster ticket: %v", ticket)
	}
	a.token = ""
	assertPosterJPEG(t, a.req("GET", posterURL, nil))
	a.session("B")
	if w = a.req("GET", url, nil); w.Code != 404 {
		t.Fatalf("cross campus: %d", w.Code)
	}
	a.token = peerToken
	if w = a.req("POST", "/api/v1/blocks", map[string]any{"userId": uid}); w.Code != 201 {
		t.Fatal(w.Code)
	}
	if w = a.req("GET", url, nil); w.Code != 404 {
		t.Fatalf("blocked bearer: %d", w.Code)
	}
	a.token = ""
	if w = a.req("GET", posterURL, nil); w.Code != 404 {
		t.Fatalf("blocked ticket: %d", w.Code)
	}
	a.token = ownerToken
	if w = a.req("DELETE", "/api/v1/posts/"+postID, nil); w.Code != 204 {
		t.Fatal(w.Code)
	}
	for _, p := range []string{path, path + ".poster.jpg"} {
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Fatalf("deleted media file remains: %s %v", p, err)
		}
	}
}

func TestPosterLegacyBackfillAndConcurrentDeletion(t *testing.T) {
	video := realVideoFixture(t)
	for i := 0; i < 6; i++ {
		a := newTestAPI(t)
		u := a.session("A")
		id := randomID()
		path := filepath.Join(a.s.cfg.MediaDir, id)
		if err := os.WriteFile(path, video, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := a.s.db.Exec(`INSERT INTO media(id,owner_id,kind,mime_type,size,path,created_at) VALUES(?,?,?,?,?,?,?)`, id, u["user"].(map[string]any)["id"], "video", "video/mp4", len(video), path, now()); err != nil {
			t.Fatal(err)
		}
		url := "/api/v1/media/" + id + "?view=poster"
		if i == 0 {
			assertPosterJPEG(t, a.req("GET", url, nil))
		}
		var wg sync.WaitGroup
		wg.Add(2)
		go func() { defer wg.Done(); a.req("GET", url, nil) }()
		go func() {
			defer wg.Done()
			if w := a.req("DELETE", "/api/v1/media/"+id, nil); w.Code != 204 {
				t.Errorf("delete: %d", w.Code)
			}
		}()
		wg.Wait()
		files, err := os.ReadDir(a.s.cfg.MediaDir)
		if err != nil || len(files) != 0 {
			t.Fatalf("files after concurrent delete: %v %v", files, err)
		}
	}
}

func TestPosterCleanupIncludesDerivedFile(t *testing.T) {
	for _, mode := range []string{"draft", "account", "orphan"} {
		t.Run(mode, func(t *testing.T) {
			t.Setenv("FFMPEG_PATH", filepath.Join(t.TempDir(), "missing-ffmpeg"))
			a := newTestAPI(t)
			a.session("A")
			m := decode[Media](t, a.upload("clip.mp4", mp4Fixture()))
			path := filepath.Join(a.s.cfg.MediaDir, m.ID)
			if err := os.WriteFile(path+".poster.jpg", jpegFixture(t), 0600); err != nil {
				t.Fatal(err)
			}
			switch mode {
			case "draft":
				if w := a.req("DELETE", "/api/v1/media/"+m.ID, nil); w.Code != 204 {
					t.Fatal(w.Code)
				}
			case "account":
				if w := a.req("DELETE", "/api/v1/me", nil); w.Code != 204 {
					t.Fatal(w.Code)
				}
			case "orphan":
				if _, err := a.s.db.Exec(`UPDATE media SET created_at=? WHERE id=?`, time.Now().UTC().Add(-48*time.Hour).Format(time.RFC3339Nano), m.ID); err != nil {
					t.Fatal(err)
				}
				a.s.cleanupOrphans()
			}
			for _, p := range []string{path, path + ".poster.jpg"} {
				if _, err := os.Stat(p); !os.IsNotExist(err) {
					t.Fatalf("file remains: %s %v", p, err)
				}
			}
		})
	}
}
