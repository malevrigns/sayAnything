package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"image/jpeg"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

var errPosterUnavailable = errors.New("video poster service unavailable")
var errPosterMissing = errors.New("video poster unavailable")

const posterMaxBytes = 1 << 20

// Bound processes across all servers, and serialize each video's generation.
// Fixed stripes avoid retaining an ever-growing map of media IDs.
var posterProcesses = make(chan struct{}, 2)
var posterLocks = func() [64]chan struct{} {
	var locks [64]chan struct{}
	for i := range locks {
		locks[i] = make(chan struct{}, 1)
	}
	return locks
}()

// Do not embed bytes.Buffer: its promoted ReadFrom would let io.Copy bypass
// Write's output limit when exec copies from the child's stdout pipe.
type posterBuffer struct{ data bytes.Buffer }

func (b *posterBuffer) Write(p []byte) (int, error) {
	if b.data.Len()+len(p) > posterMaxBytes {
		return 0, errPosterMissing
	}
	return b.data.Write(p)
}

func renderPoster(ctx context.Context, path, mime string) ([]byte, error) {
	tool := os.Getenv("FFMPEG_PATH")
	if tool == "" {
		tool = "ffmpeg"
	}
	executable, err := exec.LookPath(tool)
	if err != nil {
		return nil, errPosterUnavailable
	}
	input, err := filepath.Abs(path)
	if err != nil {
		return nil, errPosterMissing
	}
	args := []string{"-hide_banner", "-loglevel", "error", "-nostdin", "-max_alloc", "67108864", "-threads", "1", "-filter_threads", "1", "-filter_complex_threads", "1", "-max_pixels", "25000000", "-probesize", "5242880", "-analyzeduration", "3000000", "-protocol_whitelist", "file"}
	switch mime {
	case "video/mp4":
		// Force the demuxer and disable MOV's external data references; an
		// uploaded playlist or reference movie cannot open URLs/local tracks.
		args = append(args, "-f", "mov", "-enable_drefs", "0", "-use_absolute_path", "0")
	case "video/webm":
		args = append(args, "-f", "matroska")
	default:
		return nil, errPosterMissing
	}
	args = append(args, "-i", input, "-map", "0:v:0", "-frames:v", "1", "-an", "-sn", "-dn", "-vf", "scale=w='min(640,iw)':h='min(640,ih)':force_original_aspect_ratio=decrease", "-c:v", "mjpeg", "-threads", "1", "-q:v", "4", "-f", "image2pipe", "pipe:1")
	cmd := exec.CommandContext(ctx, executable, args...)
	cmd.WaitDelay = time.Second
	var output posterBuffer
	cmd.Stdout = &output
	cmd.Stderr = io.Discard
	if err = cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return nil, errPosterUnavailable
		}
		return nil, errPosterMissing
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(output.data.Bytes()))
	if err != nil || cfg.Width < 1 || cfg.Height < 1 || cfg.Width > 640 || cfg.Height > 640 {
		return nil, errPosterMissing
	}
	return output.data.Bytes(), nil
}

func (s *Server) ensurePoster(parent context.Context, m Media, original string) (string, error) {
	if m.Kind != "video" {
		return "", errPosterMissing
	}
	poster := original + ".poster.jpg"
	if st, err := os.Stat(poster); err == nil && st.Mode().IsRegular() && st.Size() > 0 && st.Size() <= posterMaxBytes {
		return poster, nil
	}
	ctx, cancel := context.WithTimeout(parent, 12*time.Second)
	defer cancel()
	hash := sha256.Sum256([]byte(original))
	lock := posterLocks[int(hash[0])%len(posterLocks)]
	select {
	case lock <- struct{}{}:
		defer func() { <-lock }()
	case <-ctx.Done():
		return "", errPosterUnavailable
	}
	if st, err := os.Stat(poster); err == nil && st.Mode().IsRegular() && st.Size() > 0 && st.Size() <= posterMaxBytes {
		return poster, nil
	}
	select {
	case posterProcesses <- struct{}{}:
		defer func() { <-posterProcesses }()
	case <-ctx.Done():
		return "", errPosterUnavailable
	}
	data, err := renderPoster(ctx, original, m.MIMEType)
	if err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(filepath.Dir(original), ".poster-*")
	if err != nil {
		return "", errPosterUnavailable
	}
	tempPath := tmp.Name()
	defer func() { s.removeOrQueue(tempPath) }()
	_, err = tmp.Write(data)
	closeErr := tmp.Close()
	if err != nil || closeErr != nil {
		return "", errPosterUnavailable
	}
	// The shared DB connection serializes publication with every deletion.
	// Never hold a transaction while FFmpeg runs. A deleted original must not
	// gain a new poster, and a deletion commits before removing either file.
	conn, err := s.db.Conn(ctx)
	if err != nil {
		return "", errPosterUnavailable
	}
	defer conn.Close()
	// Cancellation must not auto-rollback between the row check and rename,
	// otherwise a concurrent delete could commit before publication. Only
	// this short local-file publication phase outlives request cancellation.
	tx, err := conn.BeginTx(context.Background(), nil)
	if err != nil {
		return "", errPosterUnavailable
	}
	defer tx.Rollback()
	var currentPath string
	if err = tx.QueryRowContext(ctx, `SELECT path FROM media WHERE id=? AND kind='video'`, m.ID).Scan(&currentPath); err != nil || currentPath != original {
		return "", errPosterMissing
	}
	if err = os.Rename(tempPath, poster); err != nil {
		return "", errPosterUnavailable
	}
	if err = tx.Commit(); err != nil {
		_ = tx.Rollback()
		_ = conn.Close()
		s.removeOrQueue(poster)
		return "", errPosterUnavailable
	}
	return poster, nil
}

func (s *Server) removeMediaFiles(path string) {
	s.removeOrQueue(path)
	s.removeOrQueue(path + ".poster.jpg")
}
