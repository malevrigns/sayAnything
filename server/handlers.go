package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	if !s.anonLimiter.allow(clientIP(r)) {
		fail(w, 429, "too many requests")
		return
	}
	var in struct {
		Campus string `json:"campus"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	in.Campus = strings.TrimSpace(in.Campus)
	if !validText(in.Campus, maxCampusCharacters) {
		fail(w, 400, "学校名称需为 1 至 80 个字符")
		return
	}
	id, raw, created := randomID(), randomID()+randomID(), now()
	h := sha256String(raw)
	alias := "同学" + strings.ToUpper(id[:4])
	avatar := int(id[0]) % 8
	_, err := s.db.ExecContext(r.Context(), `INSERT INTO users(id,alias,campus,avatar,allow_dm,created_at) VALUES(?,?,?,?,1,?)`, id, alias, in.Campus, avatar, created)
	if err != nil {
		fail(w, 500, "could not create session")
		return
	}
	_, err = s.db.ExecContext(r.Context(), `INSERT INTO sessions(token_hash,user_id,expires_at) VALUES(?,?,?)`, h, id, timeAdd(30))
	if err != nil {
		fail(w, 500, "could not create session")
		return
	}
	writeJSON(w, 201, map[string]any{"token": raw, "user": User{id, alias, in.Campus, avatar, true, created}})
}
func sha256String(v string) string { h := sha256.Sum256([]byte(v)); return hex.EncodeToString(h[:]) }
func timeAdd(days int) string {
	return time.Now().UTC().Add(time.Duration(days) * 24 * time.Hour).Format(time.RFC3339Nano)
}
func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	switch r.Method {
	case "GET":
		writeJSON(w, 200, u)
	case "PATCH":
		var in struct {
			Alias   *string `json:"alias"`
			AllowDM *bool   `json:"allowDM"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		if in.Alias != nil {
			*in.Alias = strings.TrimSpace(*in.Alias)
			if !validText(*in.Alias, maxAliasCharacters) {
				fail(w, 400, "alias must be 1-40 characters")
				return
			}
			u.Alias = *in.Alias
		}
		if in.AllowDM != nil {
			u.AllowDM = *in.AllowDM
		}
		_, err := s.db.ExecContext(r.Context(), `UPDATE users SET alias=?,allow_dm=? WHERE id=?`, u.Alias, u.AllowDM, u.ID)
		if err != nil {
			fail(w, 500, "could not update profile")
			return
		}
		writeJSON(w, 200, u)
	case "DELETE":
		err := s.deleteAccountWithMedia(r.Context(), u.ID)
		if err != nil {
			fail(w, 500, "could not delete account")
			return
		}
		w.WriteHeader(204)
	}
}

func (s *Server) posts(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	if r.Method == "POST" {
		var in struct {
			Body     string   `json:"body"`
			Category string   `json:"category"`
			MediaIDs []string `json:"mediaIds"`
			ClientID string   `json:"clientId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		in.Body = strings.TrimSpace(in.Body)
		if !validateCreate(in.Body, maxPostCharacters, in.MediaIDs, in.ClientID) || !validCategory(in.Category) {
			fail(w, 400, "invalid post")
			return
		}
		id, t := randomID(), now()
		hash := mediaHash(in.Body, in.MediaIDs, in.Category)
		tx, e := s.db.BeginTx(r.Context(), nil)
		if e == nil {
			var replay bool
			var rid string
			rid, replay, e = requestReplay(tx, u.ID, "post", in.ClientID, hash)
			if e == nil && replay {
				tx.Rollback()
				p, e := s.getPost(r, rid)
				if e == nil {
					p.Attachments = s.attachments("post", []string{rid})[rid]
					writeJSON(w, 200, p)
					return
				}
				fail(w, 409, "clientId 对应的原内容已不存在")
				return
			}
		}
		if e == nil {
			_, e = tx.ExecContext(r.Context(), `INSERT INTO posts(id,author_id,body,category,created_at) VALUES(?,?,?,?,?)`, id, u.ID, in.Body, in.Category, t)
		}
		if e == nil {
			e = bindMedia(tx, u.ID, "post", id, in.MediaIDs)
		}
		if e == nil {
			e = storeRequest(tx, u.ID, "post", in.ClientID, hash, id)
		}
		if e != nil || tx.Commit() != nil {
			if tx != nil {
				_ = tx.Rollback()
			}
			if errors.Is(e, errTooLarge) {
				fail(w, 413, "附件总大小不能超过 50MiB")
				return
			}
			if errors.Is(e, errMediaBind) {
				fail(w, 403, "只能发送本人尚未绑定的附件")
				return
			}
			if e != nil && e.Error() == "conflict" {
				fail(w, 409, "clientId 已用于不同内容")
				return
			}
			fail(w, 500, "could not create post")
			return
		}
		writeJSON(w, 201, Post{ID: id, AuthorID: u.ID, Alias: u.Alias, Avatar: u.Avatar, Campus: u.Campus, Body: in.Body, Category: in.Category, CreatedAt: t, Attachments: s.attachments("post", []string{id})[id]})
		return
	}
	args := []any{u.ID, u.ID, u.ID, u.Campus, u.ID, u.ID}
	q := `SELECT p.id,p.author_id,a.alias,a.avatar,a.campus,p.body,p.category,p.created_at,(SELECT count(*) FROM likes WHERE post_id=p.id),(SELECT count(*) FROM comments WHERE post_id=p.id),EXISTS(SELECT 1 FROM likes WHERE post_id=p.id AND user_id=?),EXISTS(SELECT 1 FROM saves WHERE post_id=p.id AND user_id=?) FROM posts p JOIN users a ON a.id=p.author_id WHERE a.campus=? AND p.hidden=0 AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=p.author_id) OR (blocker_id=p.author_id AND blocked_id=?))`
	args = []any{u.ID, u.ID, u.Campus, u.ID, u.ID}
	if c := r.URL.Query().Get("category"); c != "" {
		q += " AND p.category=?"
		args = append(args, c)
	}
	if x := r.URL.Query().Get("q"); x != "" {
		q += " AND p.body LIKE ?"
		args = append(args, "%"+x+"%")
	}
	if r.URL.Query().Get("saved") == "1" {
		q += " AND EXISTS(SELECT 1 FROM saves WHERE post_id=p.id AND user_id=?)"
		args = append(args, u.ID)
	}
	if r.URL.Query().Get("mine") == "1" {
		q += " AND p.author_id=?"
		args = append(args, u.ID)
	}
	q += " ORDER BY p.created_at DESC LIMIT 200"
	rows, e := s.db.QueryContext(r.Context(), q, args...)
	if e != nil {
		fail(w, 500, "could not list posts")
		return
	}
	out := []Post{}
	for rows.Next() {
		var p Post
		if rows.Scan(&p.ID, &p.AuthorID, &p.Alias, &p.Avatar, &p.Campus, &p.Body, &p.Category, &p.CreatedAt, &p.Likes, &p.Comments, &p.Liked, &p.Saved) == nil {
			out = append(out, p)
		}
	}
	rows.Close()
	ids := make([]string, len(out))
	for i := range out {
		ids[i] = out[i].ID
	}
	am := s.attachments("post", ids)
	for i := range out {
		out[i].Attachments = am[out[i].ID]
	}
	writeJSON(w, 200, out)
}
func validCategory(v string) bool {
	for _, category := range postCategories {
		if v == category {
			return true
		}
	}
	return false
}
func (s *Server) getPost(r *http.Request, id string) (Post, error) {
	u := current(r)
	var p Post
	err := s.db.QueryRowContext(r.Context(), `SELECT p.id,p.author_id,a.alias,a.avatar,a.campus,p.body,p.category,p.created_at,(SELECT count(*) FROM likes WHERE post_id=p.id),(SELECT count(*) FROM comments WHERE post_id=p.id),EXISTS(SELECT 1 FROM likes WHERE post_id=p.id AND user_id=?),EXISTS(SELECT 1 FROM saves WHERE post_id=p.id AND user_id=?) FROM posts p JOIN users a ON a.id=p.author_id WHERE p.id=? AND a.campus=? AND p.hidden=0 AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=p.author_id) OR (blocker_id=p.author_id AND blocked_id=?))`, u.ID, u.ID, id, u.Campus, u.ID, u.ID).Scan(&p.ID, &p.AuthorID, &p.Alias, &p.Avatar, &p.Campus, &p.Body, &p.Category, &p.CreatedAt, &p.Likes, &p.Comments, &p.Liked, &p.Saved)
	return p, err
}
func (s *Server) postByID(w http.ResponseWriter, r *http.Request) {
	p, e := s.getPost(r, r.PathValue("id"))
	if e != nil {
		fail(w, 404, "post not found")
		return
	}
	if r.Method == "GET" {
		p.Attachments = s.attachments("post", []string{p.ID})[p.ID]
		writeJSON(w, 200, p)
		return
	}
	if p.AuthorID != current(r).ID {
		fail(w, 403, "not allowed")
		return
	}
	if e := s.deletePostWithMedia(r.Context(), p.ID); e != nil {
		fail(w, 500, "could not update post")
		return
	}
	w.WriteHeader(204)
}
func (s *Server) toggleLike(w http.ResponseWriter, r *http.Request) { s.toggle(w, r, "likes") }
func (s *Server) toggleSave(w http.ResponseWriter, r *http.Request) { s.toggle(w, r, "saves") }
func (s *Server) toggle(w http.ResponseWriter, r *http.Request, table string) {
	u := current(r)
	p, e := s.getPost(r, r.PathValue("id"))
	if e != nil {
		fail(w, 404, "post not found")
		return
	}
	res, e := s.db.ExecContext(r.Context(), `DELETE FROM `+table+` WHERE user_id=? AND post_id=?`, u.ID, p.ID)
	if e != nil {
		fail(w, 500, "could not update post")
		return
	}
	n, e := res.RowsAffected()
	if e != nil {
		fail(w, 500, "could not update post")
		return
	}
	active := n == 0
	if active {
		_, e = s.db.ExecContext(r.Context(), `INSERT INTO `+table+`(user_id,post_id) VALUES(?,?)`, u.ID, p.ID)
	}
	if e != nil {
		fail(w, 500, "could not update post")
		return
	}
	writeJSON(w, 200, map[string]bool{"active": active})
}
func (s *Server) comments(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	p, e := s.getPost(r, r.PathValue("id"))
	if e != nil {
		fail(w, 404, "post not found")
		return
	}
	if r.Method == "POST" {
		var in struct {
			Body     string   `json:"body"`
			MediaIDs []string `json:"mediaIds"`
			ClientID string   `json:"clientId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		in.Body = strings.TrimSpace(in.Body)
		if !validateCreate(in.Body, maxMessageCharacters, in.MediaIDs, in.ClientID) {
			fail(w, 400, "invalid comment")
			return
		}
		m := Message{ID: randomID(), AuthorID: u.ID, Alias: u.Alias, Avatar: u.Avatar, Body: in.Body, CreatedAt: now()}
		hash := mediaHash(in.Body, in.MediaIDs, p.ID)
		tx, e := s.db.BeginTx(r.Context(), nil)
		if e == nil {
			var replay bool
			var rid string
			rid, replay, e = requestReplay(tx, u.ID, "comment:"+p.ID, in.ClientID, hash)
			if e == nil && replay {
				tx.Rollback()
				m.ID = rid
				if e = s.db.QueryRowContext(r.Context(), `SELECT c.author_id,a.alias,a.avatar,c.body,c.created_at FROM comments c JOIN users a ON a.id=c.author_id WHERE c.id=?`, rid).Scan(&m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt); e == nil {
					m.Attachments = s.attachments("comment", []string{rid})[rid]
					writeJSON(w, 200, m)
					return
				}
				fail(w, 409, "clientId 对应的原内容已不存在")
				return
			}
		}
		if e == nil {
			_, e = tx.ExecContext(r.Context(), `INSERT INTO comments(id,post_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, m.ID, p.ID, u.ID, m.Body, m.CreatedAt)
		}
		if e == nil {
			e = bindMedia(tx, u.ID, "comment", m.ID, in.MediaIDs)
		}
		if e == nil {
			e = storeRequest(tx, u.ID, "comment:"+p.ID, in.ClientID, hash, m.ID)
		}
		if e != nil || tx.Commit() != nil {
			if tx != nil {
				_ = tx.Rollback()
			}
			if errors.Is(e, errTooLarge) {
				fail(w, 413, "附件总大小不能超过 50MiB")
				return
			}
			if errors.Is(e, errMediaBind) {
				fail(w, 403, "只能发送本人尚未绑定的附件")
				return
			}
			if e != nil && e.Error() == "conflict" {
				fail(w, 409, "clientId 已用于不同内容")
				return
			}
			fail(w, 500, "could not create comment")
			return
		}
		m.Attachments = s.attachments("comment", []string{m.ID})[m.ID]
		writeJSON(w, 201, m)
		return
	}
	rows, e := s.db.QueryContext(r.Context(), `SELECT c.id,c.author_id,a.alias,a.avatar,c.body,c.created_at FROM comments c JOIN users a ON a.id=c.author_id WHERE c.post_id=? AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=c.author_id) OR (blocker_id=c.author_id AND blocked_id=?)) ORDER BY c.created_at`, p.ID, u.ID, u.ID)
	if e != nil {
		fail(w, 500, "could not list comments")
		return
	}
	out := []Message{}
	for rows.Next() {
		var m Message
		if rows.Scan(&m.ID, &m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt) == nil {
			out = append(out, m)
		}
	}
	rows.Close()
	ids := make([]string, len(out))
	for i := range out {
		ids[i] = out[i].ID
	}
	am := s.attachments("comment", ids)
	for i := range out {
		out[i].Attachments = am[out[i].ID]
	}
	writeJSON(w, 200, out)
}

func roomValid(id string) bool {
	for _, v := range roomSeeds {
		if v.id == id {
			return true
		}
	}
	return false
}
func (s *Server) rooms(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	out := []map[string]any{}
	for _, v := range roomSeeds {
		var n int
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM room_messages WHERE campus=? AND room_id=?`, u.Campus, v.id).Scan(&n)
		out = append(out, map[string]any{"id": v.id, "name": v.name, "description": v.desc, "emoji": v.emoji, "messages": n})
	}
	writeJSON(w, 200, out)
}
func (s *Server) roomMessages(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	rid := r.PathValue("id")
	if !roomValid(rid) {
		fail(w, 404, "room not found")
		return
	}
	if r.Method == "POST" {
		var in struct {
			Body     string   `json:"body"`
			MediaIDs []string `json:"mediaIds"`
			ClientID string   `json:"clientId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		in.Body = strings.TrimSpace(in.Body)
		if !validateCreate(in.Body, maxMessageCharacters, in.MediaIDs, in.ClientID) {
			fail(w, 400, "invalid message")
			return
		}
		m := Message{ID: randomID(), AuthorID: u.ID, Alias: u.Alias, Avatar: u.Avatar, Body: in.Body, CreatedAt: now()}
		hash := mediaHash(in.Body, in.MediaIDs, rid)
		tx, e := s.db.BeginTx(r.Context(), nil)
		if e == nil {
			var replay bool
			var mid string
			mid, replay, e = requestReplay(tx, u.ID, "room:"+rid, in.ClientID, hash)
			if e == nil && replay {
				tx.Rollback()
				m.ID = mid
				if e = s.db.QueryRowContext(r.Context(), `SELECT m.author_id,a.alias,a.avatar,m.body,m.created_at FROM room_messages m JOIN users a ON a.id=m.author_id WHERE m.id=?`, mid).Scan(&m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt); e == nil {
					m.Attachments = s.attachments("room", []string{mid})[mid]
					writeJSON(w, 200, m)
					return
				}
				fail(w, 409, "clientId 对应的原内容已不存在")
				return
			}
		}
		if e == nil {
			_, e = tx.ExecContext(r.Context(), `INSERT INTO room_messages(id,room_id,campus,author_id,body,created_at) VALUES(?,?,?,?,?,?)`, m.ID, rid, u.Campus, u.ID, m.Body, m.CreatedAt)
		}
		if e == nil {
			e = bindMedia(tx, u.ID, "room", m.ID, in.MediaIDs)
		}
		if e == nil {
			e = storeRequest(tx, u.ID, "room:"+rid, in.ClientID, hash, m.ID)
		}
		if e != nil || tx.Commit() != nil {
			if tx != nil {
				_ = tx.Rollback()
			}
			if errors.Is(e, errTooLarge) {
				fail(w, 413, "附件总大小不能超过 50MiB")
				return
			}
			if errors.Is(e, errMediaBind) {
				fail(w, 403, "只能发送本人尚未绑定的附件")
				return
			}
			if e != nil && e.Error() == "conflict" {
				fail(w, 409, "clientId 已用于不同内容")
				return
			}
			fail(w, 500, "could not send message")
			return
		}
		m.Attachments = s.attachments("room", []string{m.ID})[m.ID]
		writeJSON(w, 201, m)
		return
	}
	q := `SELECT id,author_id,alias,avatar,body,created_at FROM (SELECT m.id,m.author_id,a.alias,a.avatar,m.body,m.created_at FROM room_messages m JOIN users a ON a.id=m.author_id WHERE m.room_id=? AND m.campus=? AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=m.author_id) OR (blocker_id=m.author_id AND blocked_id=?))`
	args := []any{rid, u.Campus, u.ID, u.ID}
	if after := r.URL.Query().Get("after"); after != "" {
		q += " AND m.created_at>?"
		args = append(args, after)
	}
	q += " ORDER BY m.created_at DESC LIMIT 200) ORDER BY created_at"
	rows, e := s.db.QueryContext(r.Context(), q, args...)
	if e != nil {
		fail(w, 500, "could not list messages")
		return
	}
	out := []Message{}
	for rows.Next() {
		var m Message
		if rows.Scan(&m.ID, &m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt) == nil {
			out = append(out, m)
		}
	}
	rows.Close()
	ids := make([]string, len(out))
	for i := range out {
		ids[i] = out[i].ID
	}
	am := s.attachments("room", ids)
	for i := range out {
		out[i].Attachments = am[out[i].ID]
	}
	writeJSON(w, 200, out)
}

func ordered(a, b string) (string, string) {
	if a < b {
		return a, b
	}
	return b, a
}
func (s *Server) conversations(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	if r.Method == "POST" {
		var in struct {
			PostID string `json:"postId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		var other, campus string
		var allow int
		e := s.db.QueryRowContext(r.Context(), `SELECT p.author_id,a.campus,a.allow_dm FROM posts p JOIN users a ON a.id=p.author_id WHERE p.id=? AND p.hidden=0`, in.PostID).Scan(&other, &campus, &allow)
		if e != nil {
			fail(w, 404, "post not found")
			return
		}
		if other == u.ID {
			fail(w, 400, "cannot message yourself")
			return
		}
		if campus != u.Campus || allow == 0 {
			fail(w, 403, "direct messages unavailable")
			return
		}
		if blocked(s.db, u.ID, other) {
			fail(w, 403, "direct messages unavailable")
			return
		}
		a, b := ordered(u.ID, other)
		id := randomID()
		_, e = s.db.ExecContext(r.Context(), `INSERT INTO conversations(id,user1_id,user2_id,updated_at) VALUES(?,?,?,?) ON CONFLICT(user1_id,user2_id) DO NOTHING`, id, a, b, now())
		if e != nil {
			fail(w, 500, "could not create conversation")
			return
		}
		s.db.QueryRowContext(r.Context(), `SELECT id FROM conversations WHERE user1_id=? AND user2_id=?`, a, b).Scan(&id)
		c, e := s.conversation(r, u, id)
		if e != nil {
			fail(w, 500, "could not load conversation")
			return
		}
		writeJSON(w, 201, c)
		return
	}
	search := r.URL.Query().Get("q")
	query := `SELECT id,'' FROM conversations WHERE (user1_id=? OR user2_id=?) ORDER BY updated_at DESC`
	args := []any{u.ID, u.ID}
	if search != "" {
		// instr treats %, _ and all other query characters literally. Search all
		// history, returning only a bounded excerpt of the newest matching body.
		query = `SELECT id,snippet FROM (
			SELECT c.id,c.updated_at,COALESCE(
				(SELECT substr(m.body,max(instr(sayanything_lower(m.body),?)-40,1),160) FROM dm_messages m
				 WHERE m.conversation_id=c.id AND instr(sayanything_lower(m.body),?)>0 ORDER BY m.created_at DESC LIMIT 1),
				CASE WHEN instr(sayanything_lower(peer.alias),?)>0 THEN peer.alias END) AS snippet
			FROM conversations c JOIN users peer ON peer.id=CASE WHEN c.user1_id=? THEN c.user2_id ELSE c.user1_id END
			WHERE (c.user1_id=? OR c.user2_id=?) AND NOT EXISTS(
				SELECT 1 FROM blocks WHERE (blocker_id=? AND blocked_id=peer.id) OR (blocker_id=peer.id AND blocked_id=?))
		) WHERE snippet IS NOT NULL ORDER BY updated_at DESC LIMIT 200`
		folded := strings.ToLower(search)
		args = []any{folded, folded, folded, u.ID, u.ID, u.ID, u.ID, u.ID}
	}
	rows, e := s.db.QueryContext(r.Context(), query, args...)
	if e != nil {
		fail(w, 500, "could not list conversations")
		return
	}
	ids := []string{}
	snippets := map[string]string{}
	for rows.Next() {
		var id, snippet string
		if e = rows.Scan(&id, &snippet); e != nil {
			rows.Close()
			fail(w, 500, "could not list conversations")
			return
		}
		ids = append(ids, id)
		snippets[id] = snippet
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		fail(w, 500, "could not list conversations")
		return
	}
	out := []map[string]any{}
	for _, id := range ids {
		if c, e := s.conversation(r, u, id); e == nil {
			if search != "" {
				c["matchSnippet"] = snippets[id]
			}
			out = append(out, c)
		}
	}
	writeJSON(w, 200, out)
}
func (s *Server) conversation(r *http.Request, u User, id string) (map[string]any, error) {
	var a, b, updated string
	e := s.db.QueryRowContext(r.Context(), `SELECT user1_id,user2_id,updated_at FROM conversations WHERE id=? AND (user1_id=? OR user2_id=?)`, id, u.ID, u.ID).Scan(&a, &b, &updated)
	if e != nil {
		return nil, e
	}
	other := a
	if other == u.ID {
		other = b
	}
	if blocked(s.db, u.ID, other) {
		return nil, sql.ErrNoRows
	}
	var alias string
	var avatar int
	if e = s.db.QueryRowContext(r.Context(), `SELECT alias,avatar FROM users WHERE id=?`, other).Scan(&alias, &avatar); e != nil {
		return nil, e
	}
	var last, lastID string
	s.db.QueryRowContext(r.Context(), `SELECT id,body FROM dm_messages WHERE conversation_id=? ORDER BY created_at DESC LIMIT 1`, id).Scan(&lastID, &last)
	if last == "" && lastID != "" {
		if a := s.attachments("dm", []string{lastID})[lastID]; len(a) > 0 {
			if a[0].Kind == "image" {
				last = "[图片]"
			} else {
				last = "[视频]"
			}
		}
	}
	var unread int
	s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM dm_messages m WHERE m.conversation_id=? AND m.author_id<>? AND m.created_at>COALESCE((SELECT last_read_at FROM reads WHERE conversation_id=? AND user_id=?),'')`, id, u.ID, id, u.ID).Scan(&unread)
	return map[string]any{"id": id, "alias": alias, "avatar": avatar, "lastMessage": last, "updatedAt": updated, "unread": unread}, nil
}
func blocked(db *sql.DB, a, b string) bool {
	var n int
	db.QueryRow(`SELECT count(*) FROM blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)`, a, b, b, a).Scan(&n)
	return n > 0
}
func (s *Server) dmMessages(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	id := r.PathValue("id")
	var a, b string
	if e := s.db.QueryRowContext(r.Context(), `SELECT user1_id,user2_id FROM conversations WHERE id=? AND (user1_id=? OR user2_id=?)`, id, u.ID, u.ID).Scan(&a, &b); e != nil {
		fail(w, 404, "conversation not found")
		return
	}
	other := a
	if other == u.ID {
		other = b
	}
	if blocked(s.db, u.ID, other) {
		fail(w, 403, "direct messages unavailable")
		return
	}
	if r.Method == "POST" {
		var allow int
		s.db.QueryRowContext(r.Context(), `SELECT allow_dm FROM users WHERE id=?`, other).Scan(&allow)
		if allow == 0 {
			fail(w, 403, "direct messages unavailable")
			return
		}
		var in struct {
			Body     string   `json:"body"`
			MediaIDs []string `json:"mediaIds"`
			ClientID string   `json:"clientId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		in.Body = strings.TrimSpace(in.Body)
		if !validateCreate(in.Body, maxMessageCharacters, in.MediaIDs, in.ClientID) {
			fail(w, 400, "invalid message")
			return
		}
		m := Message{ID: randomID(), AuthorID: u.ID, Alias: u.Alias, Avatar: u.Avatar, Body: in.Body, CreatedAt: now()}
		hash := mediaHash(in.Body, in.MediaIDs, id)
		tx, e := s.db.BeginTx(r.Context(), nil)
		if e == nil {
			var replay bool
			var mid string
			mid, replay, e = requestReplay(tx, u.ID, "dm:"+id, in.ClientID, hash)
			if e == nil && replay {
				tx.Rollback()
				m.ID = mid
				if e = s.db.QueryRowContext(r.Context(), `SELECT m.author_id,a.alias,a.avatar,m.body,m.created_at FROM dm_messages m JOIN users a ON a.id=m.author_id WHERE m.id=?`, mid).Scan(&m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt); e == nil {
					m.Attachments = s.attachments("dm", []string{mid})[mid]
					writeJSON(w, 200, m)
					return
				}
				fail(w, 409, "clientId 对应的原内容已不存在")
				return
			}
		}
		if e == nil {
			_, e = tx.ExecContext(r.Context(), `INSERT INTO dm_messages(id,conversation_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, m.ID, id, u.ID, m.Body, m.CreatedAt)
		}
		if e == nil {
			e = bindMedia(tx, u.ID, "dm", m.ID, in.MediaIDs)
		}
		if e == nil {
			_, e = tx.ExecContext(r.Context(), `UPDATE conversations SET updated_at=? WHERE id=?`, m.CreatedAt, id)
		}
		if e == nil {
			e = storeRequest(tx, u.ID, "dm:"+id, in.ClientID, hash, m.ID)
		}
		if e != nil {
			if tx != nil {
				tx.Rollback()
			}
			if e != nil && e.Error() == "conflict" {
				fail(w, 409, "clientId 已用于不同内容")
				return
			}
			if errors.Is(e, errTooLarge) {
				fail(w, 413, "附件总大小不能超过 50MiB")
				return
			}
			if errors.Is(e, errMediaBind) {
				fail(w, 403, "只能发送本人尚未绑定的附件")
				return
			}
			fail(w, 500, "could not send message")
			return
		}
		if e = tx.Commit(); e != nil {
			fail(w, 500, "could not send message")
			return
		}
		m.Attachments = s.attachments("dm", []string{m.ID})[m.ID]
		writeJSON(w, 201, m)
		return
	}
	q := `SELECT id,author_id,alias,avatar,body,created_at FROM (SELECT m.id,m.author_id,a.alias,a.avatar,m.body,m.created_at FROM dm_messages m JOIN users a ON a.id=m.author_id WHERE m.conversation_id=?`
	args := []any{id}
	if after := r.URL.Query().Get("after"); after != "" {
		q += " AND m.created_at>?"
		args = append(args, after)
	}
	q += " ORDER BY m.created_at DESC LIMIT 500) ORDER BY created_at"
	rows, e := s.db.QueryContext(r.Context(), q, args...)
	if e != nil {
		fail(w, 500, "could not list messages")
		return
	}
	out := []Message{}
	for rows.Next() {
		var m Message
		if rows.Scan(&m.ID, &m.AuthorID, &m.Alias, &m.Avatar, &m.Body, &m.CreatedAt) == nil {
			out = append(out, m)
		}
	}
	rows.Close()
	ids := make([]string, len(out))
	for i := range out {
		ids[i] = out[i].ID
	}
	am := s.attachments("dm", ids)
	for i := range out {
		out[i].Attachments = am[out[i].ID]
	}
	if len(out) > 0 {
		lastRead := out[len(out)-1].CreatedAt
		if _, e = s.db.ExecContext(r.Context(), `INSERT INTO reads(conversation_id,user_id,last_read_at) VALUES(?,?,?) ON CONFLICT(conversation_id,user_id) DO UPDATE SET last_read_at=MAX(reads.last_read_at,excluded.last_read_at)`, id, u.ID, lastRead); e != nil {
			fail(w, 500, "could not update read state")
			return
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) blocks(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	if r.Method == "POST" {
		var in struct {
			UserID string `json:"userId"`
		}
		if !decodeBody(w, r, &in) {
			return
		}
		if in.UserID == "" || in.UserID == u.ID {
			fail(w, 400, "invalid user")
			return
		}
		var campus string
		if s.db.QueryRowContext(r.Context(), `SELECT campus FROM users WHERE id=?`, in.UserID).Scan(&campus) != nil {
			fail(w, 404, "user not found")
			return
		}
		if campus != u.Campus {
			fail(w, 403, "not allowed")
			return
		}
		_, e := s.db.ExecContext(r.Context(), `INSERT OR IGNORE INTO blocks(blocker_id,blocked_id) VALUES(?,?)`, u.ID, in.UserID)
		if e != nil {
			fail(w, 500, "could not block user")
			return
		}
		writeJSON(w, 201, map[string]bool{"ok": true})
		return
	}
	if r.Method == "DELETE" {
		if _, e := s.db.ExecContext(r.Context(), `DELETE FROM blocks WHERE blocker_id=? AND blocked_id=?`, u.ID, r.PathValue("id")); e != nil {
			fail(w, 500, "could not update block")
			return
		}
		w.WriteHeader(204)
		return
	}
	rows, e := s.db.QueryContext(r.Context(), `SELECT x.id,x.alias,x.campus,x.avatar,x.allow_dm,x.created_at FROM blocks b JOIN users x ON x.id=b.blocked_id WHERE b.blocker_id=?`, u.ID)
	if e != nil {
		fail(w, 500, "could not list blocks")
		return
	}
	defer rows.Close()
	out := []User{}
	for rows.Next() {
		var x User
		var allow int
		if rows.Scan(&x.ID, &x.Alias, &x.Campus, &x.Avatar, &allow, &x.CreatedAt) == nil {
			x.AllowDM = allow != 0
			out = append(out, x)
		}
	}
	writeJSON(w, 200, out)
}
func (s *Server) reports(w http.ResponseWriter, r *http.Request) {
	u := current(r)
	var in struct {
		TargetType string `json:"targetType"`
		TargetID   string `json:"targetId"`
		Reason     string `json:"reason"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.TargetType != "post" && in.TargetType != "message" && in.TargetType != "user" || !validText(in.TargetID, 100) || !validText(in.Reason, 500) {
		fail(w, 400, "invalid report")
		return
	}
	if !s.reportTargetVisible(r, u, in.TargetType, in.TargetID) {
		fail(w, 404, "target not found")
		return
	}
	_, e := s.db.ExecContext(r.Context(), `INSERT INTO reports(id,reporter_id,target_type,target_id,reason,created_at) VALUES(?,?,?,?,?,?)`, randomID(), u.ID, in.TargetType, in.TargetID, strings.TrimSpace(in.Reason), now())
	if e != nil {
		fail(w, 500, "could not create report")
		return
	}
	writeJSON(w, 201, map[string]bool{"ok": true})
}

func (s *Server) reportTargetVisible(r *http.Request, u User, typ, id string) bool {
	var n int
	switch typ {
	case "post":
		_, e := s.getPost(r, id)
		return e == nil
	case "user":
		s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM users WHERE id=? AND campus=?`, id, u.Campus).Scan(&n)
	case "message":
		s.db.QueryRowContext(r.Context(), `SELECT (SELECT count(*) FROM room_messages WHERE id=? AND campus=?)+(SELECT count(*) FROM dm_messages m JOIN conversations c ON c.id=m.conversation_id WHERE m.id=? AND (c.user1_id=? OR c.user2_id=?))`, id, u.Campus, id, u.ID, u.ID).Scan(&n)
	}
	return n > 0
}
func (s *Server) adminReports(w http.ResponseWriter, r *http.Request) {
	if s.cfg.AdminToken == "" || r.Header.Get("Authorization") != "Bearer "+s.cfg.AdminToken {
		fail(w, 401, "admin authentication required")
		return
	}
	if r.Method == "GET" {
		rows, e := s.db.QueryContext(r.Context(), `SELECT id,reporter_id,target_type,target_id,reason,created_at,resolved FROM reports ORDER BY created_at DESC LIMIT 500`)
		if e != nil {
			fail(w, 500, "could not list reports")
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id, rid, typ, tid, reason, at string
			var resolved bool
			rows.Scan(&id, &rid, &typ, &tid, &reason, &at, &resolved)
			out = append(out, map[string]any{"id": id, "reporterId": rid, "targetType": typ, "targetId": tid, "reason": reason, "createdAt": at, "resolved": resolved})
		}
		writeJSON(w, 200, out)
		return
	}
	var in struct {
		Resolved bool `json:"resolved"`
		HidePost bool `json:"hidePost"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	tx, e := s.db.BeginTx(r.Context(), nil)
	if e != nil {
		fail(w, 500, "could not update report")
		return
	}
	var typ, tid string
	if e = tx.QueryRowContext(r.Context(), `SELECT target_type,target_id FROM reports WHERE id=?`, r.PathValue("id")).Scan(&typ, &tid); e == nil {
		_, e = tx.ExecContext(r.Context(), `UPDATE reports SET resolved=? WHERE id=?`, in.Resolved, r.PathValue("id"))
	}
	if e == nil && in.HidePost && typ == "post" {
		_, e = tx.ExecContext(r.Context(), `UPDATE posts SET hidden=1 WHERE id=?`, tid)
	}
	if e != nil {
		tx.Rollback()
		fail(w, 404, "report not found")
		return
	}
	if e = tx.Commit(); e != nil {
		fail(w, 500, "could not update report")
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

var downloadFiles = map[string]string{
	"android":      "sayanything-android.apk",
	"androidArm64": "sayanything-android-arm64.apk",
	"androidArmv7": "sayanything-android-armv7.apk",
	"androidX64":   "sayanything-android-x64.apk",
	"windows":      "sayanything-windows.zip",
}

func (s *Server) downloads(w http.ResponseWriter, r *http.Request) {
	exists := func(n string) bool {
		st, e := os.Stat(filepath.Join(s.cfg.DownloadDir, n))
		return e == nil && !st.IsDir()
	}
	available := map[string]bool{}
	for key, file := range downloadFiles {
		available[key] = exists(file)
	}
	writeJSON(w, 200, available)
}
func (s *Server) downloadFile(w http.ResponseWriter, r *http.Request) {
	n := r.PathValue("file")
	allowed := false
	for _, file := range downloadFiles {
		if n == file {
			allowed = true
			break
		}
	}
	if !allowed {
		fail(w, 404, "download not found")
		return
	}
	p := filepath.Join(s.cfg.DownloadDir, n)
	if _, e := os.Stat(p); e != nil {
		fail(w, 404, "download not found")
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="`+n+`"`)
	http.ServeFile(w, r, p)
}
