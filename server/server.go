package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

type Config struct {
	DBPath, WebDir, DownloadDir, MediaDir, AllowedOrigin, AdminToken string
	RateLimit                                                        int
}
type Server struct {
	db          *sql.DB
	cfg         Config
	mux         *http.ServeMux
	authLimiter *rateLimiter
	anonLimiter *rateLimiter
	mediaSlots  chan struct{}
	uploadSlots [64]chan struct{}
	stopCleanup chan struct{}
	cleanupWG   sync.WaitGroup
	closeOnce   sync.Once
}
type User struct {
	ID        string `json:"id"`
	Alias     string `json:"alias"`
	Campus    string `json:"campus"`
	Avatar    int    `json:"avatar"`
	AllowDM   bool   `json:"allowDM"`
	CreatedAt string `json:"createdAt"`
}
type Post struct {
	ID, AuthorID, Alias, Campus, Body, Category, CreatedAt string
	Avatar, Likes, Comments                                int
	Liked, Saved                                           bool
	Attachments                                            []Media
}

func (p Post) MarshalJSON() ([]byte, error) {
	m := map[string]any{"id": p.ID, "authorId": p.AuthorID, "alias": p.Alias, "avatar": p.Avatar, "campus": p.Campus, "body": p.Body, "category": p.Category, "createdAt": p.CreatedAt, "likes": p.Likes, "comments": p.Comments, "liked": p.Liked, "saved": p.Saved}
	if len(p.Attachments) > 0 {
		m["attachments"] = p.Attachments
	}
	return json.Marshal(m)
}

type Message struct {
	ID          string  `json:"id"`
	AuthorID    string  `json:"authorId"`
	Alias       string  `json:"alias"`
	Avatar      int     `json:"avatar"`
	Body        string  `json:"body"`
	CreatedAt   string  `json:"createdAt"`
	Attachments []Media `json:"attachments,omitempty"`
}

var roomSeeds = []struct{ id, name, desc, emoji string }{
	{"treehole", "深夜树洞", "把没说出口的心事，留在这里", "🌙"},
	{"daily", "课间茶水间", "聊聊今天发生的小事", "🍵"},
	{"study", "自习搭子", "一起把目标变成日常", "📚"},
	{"music", "耳机分你一半", "分享让你单曲循环的歌", "🎧"},
}

var postCategories = map[string]bool{"校园日常": true, "心事树洞": true, "搭子集合": true, "恋爱碎碎念": true, "学习交流": true}

const schema = `
PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,alias TEXT NOT NULL,campus TEXT NOT NULL,avatar INTEGER NOT NULL,allow_dm INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY,author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,body TEXT NOT NULL,category TEXT NOT NULL,created_at TEXT NOT NULL,hidden INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS comments(id TEXT PRIMARY KEY,post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,body TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS likes(user_id TEXT REFERENCES users(id) ON DELETE CASCADE,post_id TEXT REFERENCES posts(id) ON DELETE CASCADE,PRIMARY KEY(user_id,post_id));
CREATE TABLE IF NOT EXISTS saves(user_id TEXT REFERENCES users(id) ON DELETE CASCADE,post_id TEXT REFERENCES posts(id) ON DELETE CASCADE,PRIMARY KEY(user_id,post_id));
CREATE TABLE IF NOT EXISTS room_messages(id TEXT PRIMARY KEY,room_id TEXT NOT NULL,campus TEXT NOT NULL,author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,body TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY,user1_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,user2_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,updated_at TEXT NOT NULL,UNIQUE(user1_id,user2_id));
CREATE TABLE IF NOT EXISTS dm_messages(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,body TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS reads(conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id) ON DELETE CASCADE,last_read_at TEXT NOT NULL,PRIMARY KEY(conversation_id,user_id));
CREATE TRIGGER IF NOT EXISTS cleanup_reads_conversation AFTER DELETE ON conversations BEGIN DELETE FROM reads WHERE conversation_id=OLD.id; END;
CREATE TRIGGER IF NOT EXISTS cleanup_reads_user AFTER DELETE ON users BEGIN DELETE FROM reads WHERE user_id=OLD.id; END;
CREATE TABLE IF NOT EXISTS blocks(blocker_id TEXT REFERENCES users(id) ON DELETE CASCADE,blocked_id TEXT REFERENCES users(id) ON DELETE CASCADE,PRIMARY KEY(blocker_id,blocked_id));
CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,target_type TEXT NOT NULL,target_id TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL,resolved INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS media(id TEXT PRIMARY KEY,owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,mime_type TEXT NOT NULL,size INTEGER NOT NULL,width INTEGER,height INTEGER,path TEXT NOT NULL,created_at TEXT NOT NULL,upload_key TEXT,UNIQUE(owner_id,upload_key));
CREATE TABLE IF NOT EXISTS attachments(media_id TEXT PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,target_type TEXT NOT NULL,target_id TEXT NOT NULL,position INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_attachments_target ON attachments(target_type,target_id,position);
CREATE TABLE IF NOT EXISTS media_tickets(token_hash TEXT PRIMARY KEY,media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS media_gc(path TEXT PRIMARY KEY,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS client_requests(user_id TEXT NOT NULL,scope TEXT NOT NULL,client_id TEXT NOT NULL,content_hash TEXT NOT NULL,target_id TEXT NOT NULL,PRIMARY KEY(user_id,scope,client_id));
CREATE INDEX IF NOT EXISTS idx_posts_campus ON posts(created_at); CREATE INDEX IF NOT EXISTS idx_room_messages ON room_messages(campus,room_id,created_at); CREATE INDEX IF NOT EXISTS idx_dm ON dm_messages(conversation_id,created_at);`

func NewServer(c Config) (*Server, error) {
	if c.DBPath == "" {
		c.DBPath = "sayanything.db"
	}
	if c.WebDir == "" {
		c.WebDir = "web"
	}
	if c.DownloadDir == "" {
		c.DownloadDir = "../dist"
	}
	if c.MediaDir == "" {
		c.MediaDir = filepath.Join(filepath.Dir(c.DBPath), "media")
	}
	if err := os.MkdirAll(c.MediaDir, 0700); err != nil {
		return nil, err
	}
	if c.RateLimit <= 0 {
		c.RateLimit = 120
	}
	db, err := sql.Open("sqlite", c.DBPath)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err = db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	s := &Server{db: db, cfg: c, mux: http.NewServeMux(), authLimiter: newRateLimiter(c.RateLimit), anonLimiter: newRateLimiter(c.RateLimit), mediaSlots: make(chan struct{}, 2), stopCleanup: make(chan struct{})}
	for i := range s.uploadSlots {
		s.uploadSlots[i] = make(chan struct{}, 1)
	}
	s.cleanupOrphans()
	s.cleanupWG.Add(1)
	go s.cleanupLoop()
	s.routes()
	return s, nil
}
func (s *Server) Close() error {
	var err error
	s.closeOnce.Do(func() { close(s.stopCleanup); s.cleanupWG.Wait(); err = s.db.Close() })
	return err
}
func (s *Server) Handler() http.Handler { return s.security(s.mux) }
func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, map[string]any{"ok": true}) })
	s.mux.HandleFunc("POST /api/v1/session", s.session)
	s.mux.Handle("GET /api/v1/me", s.auth(http.HandlerFunc(s.me)))
	s.mux.Handle("PATCH /api/v1/me", s.auth(http.HandlerFunc(s.me)))
	s.mux.Handle("DELETE /api/v1/me", s.auth(http.HandlerFunc(s.me)))
	s.mux.Handle("GET /api/v1/posts", s.auth(http.HandlerFunc(s.posts)))
	s.mux.Handle("POST /api/v1/posts", s.auth(http.HandlerFunc(s.posts)))
	s.mux.Handle("GET /api/v1/posts/{id}", s.auth(http.HandlerFunc(s.postByID)))
	s.mux.Handle("DELETE /api/v1/posts/{id}", s.auth(http.HandlerFunc(s.postByID)))
	s.mux.Handle("POST /api/v1/posts/{id}/like", s.auth(http.HandlerFunc(s.toggleLike)))
	s.mux.Handle("POST /api/v1/posts/{id}/save", s.auth(http.HandlerFunc(s.toggleSave)))
	s.mux.Handle("GET /api/v1/posts/{id}/comments", s.auth(http.HandlerFunc(s.comments)))
	s.mux.Handle("POST /api/v1/posts/{id}/comments", s.auth(http.HandlerFunc(s.comments)))
	s.mux.Handle("GET /api/v1/rooms", s.auth(http.HandlerFunc(s.rooms)))
	s.mux.Handle("GET /api/v1/rooms/{id}/messages", s.auth(http.HandlerFunc(s.roomMessages)))
	s.mux.Handle("POST /api/v1/rooms/{id}/messages", s.auth(http.HandlerFunc(s.roomMessages)))
	s.mux.Handle("POST /api/v1/conversations", s.auth(http.HandlerFunc(s.conversations)))
	s.mux.Handle("GET /api/v1/conversations", s.auth(http.HandlerFunc(s.conversations)))
	s.mux.Handle("GET /api/v1/conversations/{id}/messages", s.auth(http.HandlerFunc(s.dmMessages)))
	s.mux.Handle("POST /api/v1/conversations/{id}/messages", s.auth(http.HandlerFunc(s.dmMessages)))
	s.mux.Handle("POST /api/v1/reports", s.auth(http.HandlerFunc(s.reports)))
	s.mux.Handle("POST /api/v1/blocks", s.auth(http.HandlerFunc(s.blocks)))
	s.mux.Handle("POST /api/v1/media", s.auth(http.HandlerFunc(s.mediaUpload)))
	s.mux.Handle("POST /api/v1/media/{id}/ticket", s.auth(http.HandlerFunc(s.mediaTicket)))
	s.mux.Handle("DELETE /api/v1/media/{id}", s.auth(http.HandlerFunc(s.mediaDelete)))
	s.mux.HandleFunc("GET /api/v1/media/{id}", s.mediaRead)
	s.mux.HandleFunc("HEAD /api/v1/media/{id}", s.mediaRead)
	s.mux.Handle("GET /api/v1/blocks", s.auth(http.HandlerFunc(s.blocks)))
	s.mux.Handle("DELETE /api/v1/blocks/{id}", s.auth(http.HandlerFunc(s.blocks)))
	s.mux.HandleFunc("GET /api/v1/admin/reports", s.adminReports)
	s.mux.HandleFunc("PATCH /api/v1/admin/reports/{id}", s.adminReports)
	s.mux.HandleFunc("GET /api/downloads", s.downloads)
	s.mux.HandleFunc("GET /downloads/{file}", s.downloadFile)
	if st, err := os.Stat(s.cfg.WebDir); err == nil && st.IsDir() {
		s.mux.Handle("/", http.FileServer(http.Dir(s.cfg.WebDir)))
	}
}

type ctxKey int

const userKey ctxKey = 1

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		if v == "" {
			if !s.anonLimiter.allow(clientIP(r)) {
				fail(w, 429, "too many requests")
				return
			}
			fail(w, 401, "请先登录")
			return
		}
		h := sha256.Sum256([]byte(v))
		var u User
		var allow int
		err := s.db.QueryRowContext(r.Context(), `SELECT u.id,u.alias,u.campus,u.avatar,u.allow_dm,u.created_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?`, hex.EncodeToString(h[:]), now()).Scan(&u.ID, &u.Alias, &u.Campus, &u.Avatar, &allow, &u.CreatedAt)
		if err != nil {
			if !s.anonLimiter.allow(clientIP(r)) {
				fail(w, 429, "too many requests")
				return
			}
			fail(w, 401, "登录已失效，请重新登录")
			return
		}
		u.AllowDM = allow != 0
		if !s.authLimiter.allow("user:" + u.ID) {
			fail(w, 429, "too many requests")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey, u)))
	})
}
func current(r *http.Request) User { return r.Context().Value(userKey).(User) }
func (s *Server) security(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		o := r.Header.Get("Origin")
		if o != "" && o == s.cfg.AllowedOrigin {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Upload-Id")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		}
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		limit := int64(1 << 20)
		if r.Method == "POST" && r.URL.Path == "/api/v1/media" {
			limit = 50<<20 + 1<<20
		}
		r.Body = http.MaxBytesReader(w, r.Body, limit)
		next.ServeHTTP(w, r)
	})
}
func decodeBody(w http.ResponseWriter, r *http.Request, v any) bool {
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		if strings.Contains(err.Error(), "request body too large") {
			fail(w, 413, "请求内容过大")
		} else {
			fail(w, 400, "请求格式不正确")
		}
		return false
	}
	if err := d.Decode(&struct{}{}); err != io.EOF {
		fail(w, 400, "请求格式不正确")
		return false
	}
	return true
}
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, status int, msg string) {
	translations := map[string]string{
		"too many requests":        "请求太频繁，请稍后再试",
		"could not create session": "暂时无法创建登录，请稍后再试", "alias must be 1-40 characters": "昵称需为 1 至 40 个字符",
		"could not update profile": "暂时无法更新资料", "could not delete account": "暂时无法注销账号", "invalid post": "帖子内容或分类不正确",
		"could not create post": "暂时无法发布帖子", "could not list posts": "暂时无法加载帖子", "post not found": "帖子不存在",
		"not allowed": "没有权限执行此操作", "could not update post": "暂时无法更新帖子", "invalid comment": "评论内容不正确",
		"could not create comment": "暂时无法发表评论", "could not list comments": "暂时无法加载评论", "room not found": "话题房间不存在",
		"invalid message": "消息内容不正确", "could not send message": "消息发送失败，请稍后再试", "could not list messages": "暂时无法加载消息",
		"cannot message yourself": "不能给自己发私信", "direct messages unavailable": "暂时无法向对方发送私信", "could not create conversation": "暂时无法创建会话",
		"could not load conversation": "暂时无法加载会话", "could not list conversations": "暂时无法加载会话", "conversation not found": "会话不存在",
		"invalid user": "用户信息不正确", "user not found": "用户不存在", "could not block user": "暂时无法屏蔽该用户", "could not list blocks": "暂时无法加载屏蔽列表",
		"invalid report": "举报信息不正确", "target not found": "举报对象不存在", "could not create report": "举报提交失败，请稍后再试",
		"admin authentication required": "需要管理员身份", "could not list reports": "暂时无法加载举报", "could not update report": "暂时无法处理举报",
		"report not found": "举报不存在", "download not found": "下载文件尚未发布",
		"could not update read state": "暂时无法更新已读状态", "could not update block": "暂时无法更新屏蔽状态",
	}
	if translated, ok := translations[msg]; ok {
		msg = translated
	}
	writeJSON(w, status, map[string]string{"error": msg})
}
func now() string                      { return time.Now().UTC().Format(time.RFC3339Nano) }
func randomID() string                 { b := make([]byte, 18); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func runeLen(s string) int             { return len([]rune(s)) }
func validText(v string, max int) bool { return strings.TrimSpace(v) != "" && runeLen(v) <= max }
func clientIP(r *http.Request) string {
	v := r.RemoteAddr
	if i := strings.LastIndex(v, ":"); i >= 0 {
		return v[:i]
	}
	return v
}

type rateLimiter struct {
	mu      sync.Mutex
	limit   int
	entries map[string]*rateEntry
}
type rateEntry struct {
	minute int64
	n      int
}

func newRateLimiter(n int) *rateLimiter {
	return &rateLimiter{limit: n, entries: map[string]*rateEntry{}}
}
func (l *rateLimiter) allow(k string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	m := time.Now().Unix() / 60
	e := l.entries[k]
	if e == nil || e.minute != m {
		l.entries[k] = &rateEntry{minute: m, n: 1}
		return true
	}
	e.n++
	return e.n <= l.limit
}
