package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/disintegration/imaging"
	_ "golang.org/x/image/webp"
)

const (
	maxImageBytes = int64(10 << 20)
	maxVideoBytes = int64(50 << 20)
	pendingQuota  = int64(100 << 20)
)

type Media struct {
	ID       string `json:"id"`
	Kind     string `json:"kind"`
	MIMEType string `json:"mimeType"`
	Name     string `json:"name"`
	Size     int64  `json:"size"`
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}

func mediaName(kind, mime string) string {
	ext := ".bin"
	if mime == "image/jpeg" {
		ext = ".jpg"
	} else if mime == "image/png" {
		ext = ".png"
	} else if mime == "video/mp4" {
		ext = ".mp4"
	} else if mime == "video/webm" {
		ext = ".webm"
	}
	if kind == "image" {
		return "图片" + ext
	}
	return "视频" + ext
}

func (s *Server) scanMedia(id string) (Media, string, string, error) {
	var m Media
	var owner, path string
	err := s.db.QueryRow(`SELECT id,owner_id,kind,mime_type,size,COALESCE(width,0),COALESCE(height,0),path FROM media WHERE id=?`, id).Scan(&m.ID, &owner, &m.Kind, &m.MIMEType, &m.Size, &m.Width, &m.Height, &path)
	m.Name = mediaName(m.Kind, m.MIMEType)
	return m, owner, path, err
}

func (s *Server) mediaUpload(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	ownerHash := sha256.Sum256([]byte(u.ID))
	ownerSlot := s.uploadSlots[int(ownerHash[0])%len(s.uploadSlots)]
	select {
	case ownerSlot <- struct{}{}:
		defer func() { <-ownerSlot }()
	case <-r.Context().Done():
		fail(w, 408, "上传已取消")
		return
	}
	select {
	case s.mediaSlots <- struct{}{}:
		defer func() { <-s.mediaSlots }()
	case <-r.Context().Done():
		fail(w, 408, "上传已取消")
		return
	}
	key := strings.TrimSpace(r.Header.Get("X-Upload-Id"))
	if len(key) > 80 {
		fail(w, 400, "上传标识无效")
		return
	}
	if key != "" {
		var id string
		if s.db.QueryRowContext(r.Context(), `SELECT id FROM media WHERE owner_id=? AND upload_key=?`, u.ID, key).Scan(&id) == nil {
			m, _, _, _ := s.scanMedia(id)
			writeJSON(w, 200, m)
			return
		}
	}
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		fail(w, 413, "上传文件过大")
		return
	}
	defer r.MultipartForm.RemoveAll()
	if r.MultipartForm == nil || len(r.MultipartForm.File) != 1 || len(r.MultipartForm.File["file"]) != 1 {
		fail(w, 400, "只能上传一个文件")
		return
	}
	f, _, err := r.FormFile("file")
	if err != nil {
		fail(w, 400, "请选择一个文件")
		return
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxVideoBytes+1))
	if err != nil {
		fail(w, 400, "无法读取文件")
		return
	}
	kind, mime, out, width, height, err := s.validateMedia(r, data)
	if err != nil {
		if errors.Is(err, errTooLarge) {
			fail(w, 413, "上传文件过大")
		} else {
			fail(w, 415, "不支持或损坏的媒体文件")
		}
		return
	}
	id := randomID()
	path := filepath.Join(s.cfg.MediaDir, id)
	if err = os.WriteFile(path, out, 0600); err != nil {
		fail(w, 500, "无法保存媒体文件")
		return
	}
	m := Media{ID: id, Kind: kind, MIMEType: mime, Name: mediaName(kind, mime), Size: int64(len(out)), Width: width, Height: height}
	tx, err := s.db.BeginTx(r.Context(), nil)
	var used int64
	if err == nil {
		err = tx.QueryRowContext(r.Context(), `SELECT COALESCE(sum(m.size),0) FROM media m LEFT JOIN attachments a ON a.media_id=m.id WHERE m.owner_id=? AND a.media_id IS NULL`, u.ID).Scan(&used)
	}
	if err == nil && used+m.Size > pendingQuota {
		_ = tx.Rollback()
		s.removeOrQueue(path)
		fail(w, 413, "待发送附件已超过 100MiB")
		return
	}
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO media(id,owner_id,kind,mime_type,size,width,height,path,created_at,upload_key) VALUES(?,?,?,?,?,?,?,?,?,?)`, id, u.ID, kind, mime, m.Size, width, height, path, now(), nullable(key))
	}
	if err == nil {
		err = tx.Commit()
	} else if tx != nil {
		_ = tx.Rollback()
	}
	if err != nil {
		s.removeOrQueue(path)
		if key != "" {
			var old string
			if s.db.QueryRowContext(r.Context(), `SELECT id FROM media WHERE owner_id=? AND upload_key=?`, u.ID, key).Scan(&old) == nil {
				om, _, _, _ := s.scanMedia(old)
				writeJSON(w, 200, om)
				return
			}
		}
		fail(w, 500, "无法保存媒体信息")
		return
	}
	writeJSON(w, 201, m)
}

var errTooLarge = errors.New("too large")

func (s *Server) validateMedia(_ *http.Request, data []byte) (string, string, []byte, int, int, error) {
	ct := http.DetectContentType(data)
	if ct == "image/jpeg" || ct == "image/png" || ct == "image/webp" {
		if int64(len(data)) > maxImageBytes {
			return "", "", nil, 0, 0, errTooLarge
		}
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > 25_000_000 {
			return "", "", nil, 0, 0, errors.New("bad image")
		}
		im, err := imaging.Decode(bytes.NewReader(data), imaging.AutoOrientation(true))
		if err != nil {
			return "", "", nil, 0, 0, err
		}
		var b bytes.Buffer
		if ct == "image/jpeg" {
			err = jpeg.Encode(&b, im, &jpeg.Options{Quality: 90})
		} else {
			ct = "image/png"
			err = png.Encode(&b, im)
		}
		if err != nil {
			return "", "", nil, 0, 0, err
		}
		bounds := im.Bounds()
		return "image", ct, b.Bytes(), bounds.Dx(), bounds.Dy(), nil
	}
	if isMP4(data) {
		if int64(len(data)) > maxVideoBytes {
			return "", "", nil, 0, 0, errTooLarge
		}
		return "video", "video/mp4", data, 0, 0, nil
	}
	if isWebM(data) {
		if int64(len(data)) > maxVideoBytes {
			return "", "", nil, 0, 0, errTooLarge
		}
		return "video", "video/webm", data, 0, 0, nil
	}
	return "", "", nil, 0, 0, errors.New("unsupported")
}
func isMP4(b []byte) bool {
	return len(b) >= 16 && string(b[4:8]) == "ftyp" && bytes.Contains(b[8:min(len(b), 64)], []byte("isom")) || len(b) >= 16 && string(b[4:8]) == "ftyp"
}
func isWebM(b []byte) bool { return len(b) >= 4 && bytes.Equal(b[:4], []byte{0x1a, 0x45, 0xdf, 0xa3}) }
func nullable(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func (s *Server) mediaTicket(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	id := r.PathValue("id")
	if !s.mediaVisible(r, u, id) {
		fail(w, 404, "媒体不存在")
		return
	}
	raw := randomID() + randomID()
	exp := time.Now().UTC().Add(15 * time.Minute)
	_, err := s.db.ExecContext(r.Context(), `INSERT INTO media_tickets(token_hash,media_id,user_id,expires_at) VALUES(?,?,?,?)`, sha256String(raw), id, u.ID, exp.Format(time.RFC3339Nano))
	if err != nil {
		fail(w, 500, "无法创建媒体凭证")
		return
	}
	writeJSON(w, 200, map[string]any{"url": "/api/v1/media/" + id + "?ticket=" + raw, "expiresAt": exp.Format(time.RFC3339Nano)})
}

func (s *Server) requestUser(r *http.Request) (User, error) {
	v := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if v == "" {
		return User{}, sql.ErrNoRows
	}
	var u User
	var allow int
	err := s.db.QueryRowContext(r.Context(), `SELECT u.id,u.alias,u.campus,u.avatar,u.allow_dm,u.created_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?`, sha256String(v), now()).Scan(&u.ID, &u.Alias, &u.Campus, &u.Avatar, &allow, &u.CreatedAt)
	u.AllowDM = allow != 0
	return u, err
}
func (s *Server) mediaRead(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	u, err := s.requestUser(r)
	if err != nil {
		raw := r.URL.Query().Get("ticket")
		if raw == "" {
			fail(w, 401, "请先登录")
			return
		}
		var allow int
		err = s.db.QueryRowContext(r.Context(), `SELECT u.id,u.alias,u.campus,u.avatar,u.allow_dm,u.created_at FROM media_tickets t JOIN users u ON u.id=t.user_id WHERE t.token_hash=? AND t.media_id=? AND t.expires_at>?`, sha256String(raw), id, now()).Scan(&u.ID, &u.Alias, &u.Campus, &u.Avatar, &allow, &u.CreatedAt)
		u.AllowDM = allow != 0
	}
	if err != nil || !s.mediaVisible(r, u, id) {
		fail(w, 404, "媒体不存在")
		return
	}
	m, _, path, err := s.scanMedia(id)
	if err != nil {
		fail(w, 404, "媒体不存在")
		return
	}
	f, err := os.Open(path)
	if err != nil {
		fail(w, 404, "媒体不存在")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		fail(w, 404, "媒体不存在")
		return
	}
	w.Header().Set("Content-Type", m.MIMEType)
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`inline; filename="%s"`, m.Name))
	http.ServeContent(w, r, m.Name, st.ModTime(), f)
}

func (s *Server) mediaVisible(r *http.Request, u User, id string) bool {
	var owner, typ, target string
	err := s.db.QueryRowContext(r.Context(), `SELECT m.owner_id,COALESCE(a.target_type,''),COALESCE(a.target_id,'') FROM media m LEFT JOIN attachments a ON a.media_id=m.id WHERE m.id=?`, id).Scan(&owner, &typ, &target)
	if err != nil {
		return false
	}
	if typ == "" {
		return owner == u.ID
	}
	var n int
	switch typ {
	case "post":
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM posts p JOIN users x ON x.id=p.author_id WHERE p.id=? AND p.hidden=0 AND x.campus=? AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=x.id) OR (blocker_id=x.id AND blocked_id=?))`, target, u.Campus, u.ID, u.ID).Scan(&n)
	case "comment":
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM comments c JOIN posts p ON p.id=c.post_id JOIN users pa ON pa.id=p.author_id JOIN users ca ON ca.id=c.author_id WHERE c.id=? AND p.hidden=0 AND pa.campus=? AND NOT EXISTS(SELECT 1 FROM blocks WHERE ((blocker_id=? AND blocked_id=pa.id) OR (blocker_id=pa.id AND blocked_id=?)) OR ((blocker_id=? AND blocked_id=ca.id) OR (blocker_id=ca.id AND blocked_id=?)))`, target, u.Campus, u.ID, u.ID, u.ID, u.ID).Scan(&n)
	case "room":
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM room_messages m WHERE m.id=? AND m.campus=? AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=m.author_id) OR (blocker_id=m.author_id AND blocked_id=?))`, target, u.Campus, u.ID, u.ID).Scan(&n)
	case "dm":
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM dm_messages m JOIN conversations c ON c.id=m.conversation_id WHERE m.id=? AND (c.user1_id=? OR c.user2_id=?) AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=m.author_id) OR (blocker_id=m.author_id AND blocked_id=?))`, target, u.ID, u.ID, u.ID, u.ID).Scan(&n)
	}
	return n > 0
}
func (s *Server) mediaDelete(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	id := r.PathValue("id")
	var path string
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err == nil {
		err = tx.QueryRowContext(r.Context(), `DELETE FROM media WHERE id=? AND owner_id=? AND NOT EXISTS(SELECT 1 FROM attachments WHERE media_id=media.id) RETURNING path`, id, u.ID).Scan(&path)
	}
	if err != nil {
		if tx != nil {
			_ = tx.Rollback()
		}
		fail(w, 409, "只能删除本人尚未发送的附件")
		return
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "无法删除媒体信息")
		return
	}
	s.removeOrQueue(path)
	w.WriteHeader(204)
}

func (s *Server) attachments(targetType string, ids []string) map[string][]Media {
	out := map[string][]Media{}
	if len(ids) == 0 {
		return out
	}
	placeholders := strings.TrimRight(strings.Repeat("?,", len(ids)), ",")
	args := []any{targetType}
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := s.db.Query(`SELECT a.target_id,m.id,m.kind,m.mime_type,m.size,COALESCE(m.width,0),COALESCE(m.height,0),a.position FROM attachments a JOIN media m ON m.id=a.media_id WHERE a.target_type=? AND a.target_id IN (`+placeholders+`) ORDER BY a.position`, args...)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var target string
		var m Media
		var pos int
		if rows.Scan(&target, &m.ID, &m.Kind, &m.MIMEType, &m.Size, &m.Width, &m.Height, &pos) == nil {
			m.Name = mediaName(m.Kind, m.MIMEType)
			out[target] = append(out[target], m)
		}
	}
	return out
}
func mediaHash(body string, media []string, extra string) string {
	v := append([]string{}, media...)
	sort.Strings(v)
	h := sha256.Sum256([]byte(body + "\x00" + extra + "\x00" + strings.Join(v, "\x00")))
	return hex.EncodeToString(h[:])
}
func validateCreate(body string, max int, media []string, client string) bool {
	return (body != "" && runeLen(body) <= max || body == "" && len(media) > 0) && len(media) <= 4 && len(client) <= 80
}

var errMediaBind = errors.New("media cannot be bound")

func bindMedia(tx *sql.Tx, user, targetType, target string, ids []string) error {
	seen := map[string]bool{}
	var total int64
	for i, id := range ids {
		if seen[id] {
			return errMediaBind
		}
		seen[id] = true
		var size int64
		if err := tx.QueryRow(`SELECT m.size FROM media m LEFT JOIN attachments a ON a.media_id=m.id WHERE m.id=? AND m.owner_id=? AND a.media_id IS NULL`, id, user).Scan(&size); err != nil {
			return errMediaBind
		}
		total += size
		if total > maxVideoBytes {
			return errTooLarge
		}
		res, err := tx.Exec(`INSERT INTO attachments(media_id,target_type,target_id,position) SELECT id,?,?,? FROM media WHERE id=? AND owner_id=? AND NOT EXISTS(SELECT 1 FROM attachments WHERE media_id=?)`, targetType, target, i, id, user, id)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			return errMediaBind
		}
	}
	return nil
}
func requestReplay(tx *sql.Tx, user, scope, client, hash string) (string, bool, error) {
	if client == "" {
		return "", false, nil
	}
	var oldHash, id string
	err := tx.QueryRow(`SELECT content_hash,target_id FROM client_requests WHERE user_id=? AND scope=? AND client_id=?`, user, scope, client).Scan(&oldHash, &id)
	if err == nil {
		if oldHash != hash {
			return "", false, errors.New("conflict")
		}
		return id, true, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", false, err
	}
	return "", false, nil
}
func storeRequest(tx *sql.Tx, user, scope, client, hash, target string) error {
	if client == "" {
		return nil
	}
	_, err := tx.Exec(`INSERT INTO client_requests(user_id,scope,client_id,content_hash,target_id) VALUES(?,?,?,?,?)`, user, scope, client, hash, target)
	return err
}

// deleteContentWithMedia keeps the attachment snapshot and all cascading deletes
// under the same transaction, so concurrent sends cannot escape cleanup.
func (s *Server) deleteContentWithMedia(ctx context.Context, query string, args []any, deleteQuery, target string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(ctx, query, args...)
	if err != nil {
		return err
	}
	var ids, paths []string
	for rows.Next() {
		var id, path string
		if err = rows.Scan(&id, &path); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
		paths = append(paths, path)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, id := range ids {
		if _, err = tx.ExecContext(ctx, `DELETE FROM media WHERE id=?`, id); err != nil {
			return err
		}
	}
	if _, err = tx.ExecContext(ctx, deleteQuery, target); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	for _, path := range paths {
		s.removeOrQueue(path)
	}
	return nil
}

func (s *Server) deletePostWithMedia(ctx context.Context, post string) error {
	return s.deleteContentWithMedia(ctx, `SELECT m.id,m.path FROM media m JOIN attachments a ON a.media_id=m.id WHERE (a.target_type='post' AND a.target_id=?) OR (a.target_type='comment' AND a.target_id IN (SELECT id FROM comments WHERE post_id=?))`, []any{post, post}, `DELETE FROM posts WHERE id=?`, post)
}

func (s *Server) deleteAccountWithMedia(ctx context.Context, user string) error {
	return s.deleteContentWithMedia(ctx, `SELECT DISTINCT m.id,m.path FROM media m LEFT JOIN attachments a ON a.media_id=m.id WHERE m.owner_id=? OR (a.target_type='post' AND a.target_id IN (SELECT id FROM posts WHERE author_id=?)) OR (a.target_type='comment' AND a.target_id IN (SELECT c.id FROM comments c LEFT JOIN posts p ON p.id=c.post_id WHERE c.author_id=? OR p.author_id=?)) OR (a.target_type='room' AND a.target_id IN (SELECT id FROM room_messages WHERE author_id=?)) OR (a.target_type='dm' AND a.target_id IN (SELECT dm.id FROM dm_messages dm JOIN conversations c ON c.id=dm.conversation_id WHERE c.user1_id=? OR c.user2_id=?))`, []any{user, user, user, user, user, user, user}, `DELETE FROM users WHERE id=?`, user)
}

func (s *Server) cleanupOrphans() {
	s.retryGC()
	cut := time.Now().UTC().Add(-24 * time.Hour).Format(time.RFC3339Nano)
	rows, err := s.db.Query(`SELECT m.id,m.path FROM media m LEFT JOIN attachments a ON a.media_id=m.id WHERE a.media_id IS NULL AND m.created_at<?`, cut)
	if err != nil {
		return
	}
	type f struct{ id, path string }
	var fs []f
	for rows.Next() {
		var x f
		if rows.Scan(&x.id, &x.path) == nil {
			fs = append(fs, x)
		}
	}
	rows.Close()
	for _, x := range fs {
		var path string
		tx, err := s.db.Begin()
		if err == nil {
			err = tx.QueryRow(`DELETE FROM media WHERE id=? AND created_at<? AND NOT EXISTS(SELECT 1 FROM attachments WHERE media_id=media.id) RETURNING path`, x.id, cut).Scan(&path)
		}
		if err == nil {
			err = tx.Commit()
		} else if tx != nil {
			_ = tx.Rollback()
		}
		if err == nil {
			s.removeOrQueue(path)
		}
	}
	_, _ = s.db.Exec(`DELETE FROM media_tickets WHERE expires_at<?`, now())
}

func (s *Server) removeOrQueue(path string) {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		_, _ = s.db.Exec(`INSERT OR IGNORE INTO media_gc(path,created_at) VALUES(?,?)`, path, now())
	} else {
		_, _ = s.db.Exec(`DELETE FROM media_gc WHERE path=?`, path)
	}
}
func (s *Server) retryGC() {
	rows, err := s.db.Query(`SELECT path FROM media_gc`)
	if err != nil {
		return
	}
	var paths []string
	for rows.Next() {
		var p string
		if rows.Scan(&p) == nil {
			paths = append(paths, p)
		}
	}
	rows.Close()
	for _, p := range paths {
		s.removeOrQueue(p)
	}
}

func (s *Server) cleanupLoop() {
	defer s.cleanupWG.Done()
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			s.cleanupOrphans()
		case <-s.stopCleanup:
			return
		}
	}
}
