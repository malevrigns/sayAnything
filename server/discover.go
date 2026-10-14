package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Profile and discover limits are shared by the authoritative writes and the
// public GET /api/v1/config hints, so the two can never drift apart.
const (
	maxBioCharacters   = 120
	maxProfileTags     = 5
	discoverDailyLikes = 50
	discoverDeckSize   = 20
	discoverPassTTL    = 30 * 24 * time.Hour
)

// Interest tags are a server-side closed list: clients may only pick from it.
var profileTags = []string{"运动", "音乐", "阅读", "摄影", "美食", "旅行", "电影", "游戏"}

type gradeOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

var profileGrades = []gradeOption{{"freshman", "大一"}, {"sophomore", "大二"}, {"junior", "大三"}, {"senior", "大四"}}

const tagSeparator = "\x1f"

func validProfileTag(tag string) bool {
	for _, t := range profileTags {
		if t == tag {
			return true
		}
	}
	return false
}
func validGrade(grade string) bool {
	for _, g := range profileGrades {
		if g.ID == grade {
			return true
		}
	}
	return false
}

// tagsColumn returns the SQL fragment that selects one user's tags as a
// separator-delimited string; callers decode it with splitTags. Tags live in
// their own table so the closed list and the ordering stay in one place.
func tagsColumn(userIDExpr string) string {
	return `COALESCE((SELECT group_concat(tag,char(31)) FROM (SELECT tag FROM user_tags WHERE user_id=` + userIDExpr + ` ORDER BY position)),'')`
}
func splitTags(v string) []string {
	tags := []string{}
	if v == "" {
		return tags
	}
	return strings.Split(v, tagSeparator)
}
func validateTags(tags []string) string {
	if len(tags) > maxProfileTags {
		return "too many tags"
	}
	seen := map[string]bool{}
	for _, tag := range tags {
		if !validProfileTag(tag) {
			return "unknown tag"
		}
		if seen[tag] {
			return "duplicate tag"
		}
		seen[tag] = true
	}
	return ""
}

// userColumns lists every column needed to build a User for the given table
// alias, so no SELECT can silently fall behind the struct. scanUser is its
// counterpart for both *sql.Row and *sql.Rows.
func userColumns(alias string) string {
	return alias + `.id,` + alias + `.alias,` + alias + `.campus,` + alias + `.avatar,` + alias + `.allow_dm,` + alias + `.created_at,` + alias + `.gender,` + alias + `.bio,` + alias + `.grade,` + tagsColumn(alias+".id")
}

type rowScanner interface{ Scan(dest ...any) error }

func scanUser(row rowScanner) (User, error) {
	var u User
	var allow int
	var tags string
	if err := row.Scan(&u.ID, &u.Alias, &u.Campus, &u.Avatar, &allow, &u.CreatedAt, &u.Gender, &u.Bio, &u.Grade, &tags); err != nil {
		return User{}, err
	}
	u.AllowDM = allow != 0
	u.Tags = splitTags(tags)
	return u, nil
}
func replaceTags(ctx context.Context, tx *sql.Tx, userID string, tags []string) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM user_tags WHERE user_id=?`, userID); err != nil {
		return err
	}
	for i, tag := range tags {
		if _, err := tx.ExecContext(ctx, `INSERT INTO user_tags(user_id,tag,position) VALUES(?,?,?)`, userID, tag, i); err != nil {
			return err
		}
	}
	return nil
}

// migrateDiscover only adds columns and tables, so an existing database keeps
// every row it had. bio/grade stay in users; tags get their own table because
// they are an ordered, server-enumerated list.
func migrateDiscover(db *sql.DB) error {
	rows, err := db.Query(`PRAGMA table_info(users)`)
	if err != nil {
		return err
	}
	hasBio := false
	hasGrade := false
	for rows.Next() {
		var cid, notNull, pk int
		var name, typ string
		var def any
		if err = rows.Scan(&cid, &name, &typ, &notNull, &def, &pk); err != nil {
			rows.Close()
			return err
		}
		if name == "bio" {
			hasBio = true
		}
		if name == "grade" {
			hasGrade = true
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if !hasBio {
		if _, err = db.Exec(`ALTER TABLE users ADD COLUMN bio TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
	}
	if !hasGrade {
		if _, err = db.Exec(`ALTER TABLE users ADD COLUMN grade TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
	}
	_, err = db.Exec(`
CREATE TABLE IF NOT EXISTS user_tags(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,tag TEXT NOT NULL,position INTEGER NOT NULL,PRIMARY KEY(user_id,tag));
CREATE INDEX IF NOT EXISTS idx_user_tags_order ON user_tags(user_id,position);
CREATE TABLE IF NOT EXISTS swipes(actor_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,target_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,action TEXT NOT NULL CHECK(action IN ('like','pass')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(actor_id,target_id));
CREATE INDEX IF NOT EXISTS idx_swipes_target ON swipes(target_id,action);
CREATE TABLE IF NOT EXISTS matches(id TEXT PRIMARY KEY,user1_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,user2_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,created_at TEXT NOT NULL,UNIQUE(user1_id,user2_id));
CREATE INDEX IF NOT EXISTS idx_matches_user2 ON matches(user2_id,created_at);
CREATE TABLE IF NOT EXISTS discover_likes(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,day TEXT NOT NULL,count INTEGER NOT NULL CHECK(count>=1),PRIMARY KEY(user_id,day));`)
	return err
}

// discoverMe/peer aliases are required by every query below.
const discoverBlockFilter = `NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=me.id AND blocked_id=peer.id) OR (blocker_id=peer.id AND blocked_id=me.id))`

// A pass is not final: once it ages out, the peer may resurface for both the
// deck and the "who liked me" list.
const discoverExpiredPass = `(s.action='pass' AND substr(s.updated_at,1,10)<?)`

func (s *Server) cleanupDiscover() {
	_, _ = s.db.Exec(`DELETE FROM discover_likes WHERE day<?`, dateKey(time.Now()))
	_, _ = s.db.Exec(`DELETE FROM swipes WHERE action='pass' AND substr(updated_at,1,10)<?`, dateKey(time.Now().Add(-discoverPassTTL)))
}
func (s *Server) discoverCleanupLoop() {
	defer s.cleanupWG.Done()
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-s.stopCleanup:
			return
		case <-ticker.C:
			s.cleanupDiscover()
		}
	}
}
func dateKey(t time.Time) string { return t.UTC().Format("2006-01-02") }

type discoverItem struct {
	ID            string   `json:"id"`
	Alias         string   `json:"alias"`
	Avatar        int      `json:"avatar"`
	Gender        string   `json:"gender"`
	Bio           string   `json:"bio"`
	Grade         string   `json:"grade"`
	Tags          []string `json:"tags"`
	Campus        string   `json:"campus"`
	DistanceLabel string   `json:"distanceLabel,omitempty"`
}
type discoverResponse struct {
	Items     []discoverItem `json:"items"`
	LikesMe   int            `json:"likesMe"`
	LikesLeft int            `json:"likesLeft"`
}
type matchItem struct {
	ID             string `json:"id"`
	Alias          string `json:"alias"`
	Avatar         int    `json:"avatar"`
	ConversationID string `json:"conversationId"`
	MatchedAt      string `json:"matchedAt"`
}

// scanDiscoverItems reads candidate rows whose trailing four columns are the
// viewer's and the peer's coarse grid coordinates. Like the nearby page, only
// a coarse distance label within the nearby radius is reported, and only while
// both locations are live right now; the coordinates stop here.
func (s *Server) scanDiscoverItems(ctx context.Context, query string, args ...any) ([]discoverItem, error) {
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []discoverItem{}
	for rows.Next() {
		var item discoverItem
		var tags string
		var lat, lon, plat, plon sql.NullFloat64
		if err = rows.Scan(&item.ID, &item.Alias, &item.Avatar, &item.Gender, &item.Bio, &item.Grade, &tags, &item.Campus, &lat, &lon, &plat, &plon); err != nil {
			return nil, err
		}
		item.Tags = splitTags(tags)
		if lat.Valid && lon.Valid && plat.Valid && plon.Valid {
			if d := gridDistanceKm(lat.Float64, lon.Float64, plat.Float64, plon.Float64); d <= nearbyRadiusKm {
				item.DistanceLabel = coarseDistanceLabel(d)
			}
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

// Candidates are ordered so the people who already liked me come first, then
// the profiles with something to look at, then the rest by alias for a stable
// order that leaks nothing about activity. tagsColumn is a function call, so
// this base cannot be a constant.
var discoverItemsSelect = `SELECT peer.id,peer.alias,peer.avatar,peer.gender,peer.bio,peer.grade,` + tagsColumn("peer.id") + `,peer.campus,own.latitude,own.longitude,loc.latitude,loc.longitude
FROM users me
JOIN users peer ON peer.campus=me.campus AND peer.id<>me.id AND peer.allow_dm=1
LEFT JOIN nearby_locations own ON own.user_id=me.id AND own.expires_at>?
LEFT JOIN nearby_locations loc ON loc.user_id=peer.id AND loc.expires_at>?
WHERE me.id=?
 AND ` + discoverBlockFilter + `
 AND NOT EXISTS(SELECT 1 FROM swipes s WHERE s.actor_id=me.id AND s.target_id=peer.id AND NOT ` + discoverExpiredPass + `)`

func (s *Server) discover(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	u := current(r)
	gender := r.URL.Query().Get("gender")
	if gender != "" && gender != "male" && gender != "female" {
		fail(w, 400, "invalid gender filter")
		return
	}
	clock := time.Now()
	query := discoverItemsSelect
	args := []any{clock.UnixMilli(), clock.UnixMilli(), u.ID, dateKey(clock.Add(-discoverPassTTL))}
	if gender != "" {
		query += ` AND peer.gender=?`
		args = append(args, gender)
	}
	query += ` ORDER BY (EXISTS(SELECT 1 FROM swipes w WHERE w.actor_id=peer.id AND w.target_id=me.id AND w.action='like')) DESC,(peer.bio<>'' OR EXISTS(SELECT 1 FROM user_tags t WHERE t.user_id=peer.id)) DESC,peer.alias,peer.id LIMIT ` + strconv.Itoa(discoverDeckSize)
	items, err := s.scanDiscoverItems(r.Context(), query, args...)
	if err != nil {
		fail(w, 500, "could not load discover")
		return
	}
	var used int
	if err = s.db.QueryRowContext(r.Context(), `SELECT COALESCE((SELECT count FROM discover_likes WHERE user_id=? AND day=?),0)`, u.ID, dateKey(clock)).Scan(&used); err != nil {
		fail(w, 500, "could not load discover")
		return
	}
	var likesMe int
	if err = s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM swipes w JOIN users me ON me.id=? JOIN users peer ON peer.id=w.actor_id
WHERE w.target_id=me.id AND w.action='like' AND peer.campus=me.campus AND peer.allow_dm=1
 AND `+discoverBlockFilter+`
 AND NOT EXISTS(SELECT 1 FROM swipes s WHERE s.actor_id=me.id AND s.target_id=peer.id AND NOT `+discoverExpiredPass+`)`, u.ID, dateKey(clock.Add(-discoverPassTTL))).Scan(&likesMe); err != nil {
		fail(w, 500, "could not load discover")
		return
	}
	out := discoverResponse{Items: items, LikesMe: likesMe, LikesLeft: max(0, discoverDailyLikes-used)}
	writeJSON(w, 200, out)
}

// discoverLikes is the deck's inbound half: people who liked me and whose
// swipe I have not answered yet, newest first. It shares the candidate
// visibility rules with the deck so a blocked or other-campus liker never shows.
func (s *Server) discoverLikes(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	u := current(r)
	clock := time.Now()
	query := `SELECT peer.id,peer.alias,peer.avatar,peer.gender,peer.bio,peer.grade,` + tagsColumn("peer.id") + `,peer.campus,own.latitude,own.longitude,loc.latitude,loc.longitude
FROM swipes w
JOIN users me ON me.id=?
JOIN users peer ON peer.id=w.actor_id AND peer.campus=me.campus AND peer.allow_dm=1
LEFT JOIN nearby_locations own ON own.user_id=me.id AND own.expires_at>?
LEFT JOIN nearby_locations loc ON loc.user_id=peer.id AND loc.expires_at>?
WHERE w.target_id=me.id AND w.action='like'
 AND ` + discoverBlockFilter + `
 AND NOT EXISTS(SELECT 1 FROM swipes s WHERE s.actor_id=me.id AND s.target_id=peer.id AND NOT ` + discoverExpiredPass + `)
ORDER BY w.updated_at DESC,peer.id`
	items, err := s.scanDiscoverItems(r.Context(), query, u.ID, clock.UnixMilli(), clock.UnixMilli(), dateKey(clock.Add(-discoverPassTTL)))
	if err != nil {
		fail(w, 500, "could not load likes")
		return
	}
	writeJSON(w, 200, items)
}

func (s *Server) discoverSwipe(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	u := current(r)
	other := r.PathValue("id")
	var in struct {
		Action string `json:"action"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.Action != "like" && in.Action != "pass" {
		fail(w, 400, "invalid swipe action")
		return
	}
	if other == u.ID {
		fail(w, 400, "cannot like yourself")
		return
	}
	clock := time.Now()
	at := clock.Format(time.RFC3339Nano)
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "could not save swipe")
		return
	}
	defer tx.Rollback()
	// Visibility is re-checked inside the transaction, against current
	// consent, campus and blocks rather than the caller's cached identity.
	var myDM int
	err = tx.QueryRowContext(r.Context(), `SELECT me.allow_dm FROM users me JOIN users peer ON peer.id=? WHERE me.id=? AND peer.campus=me.campus AND peer.allow_dm=1 AND `+discoverBlockFilter, other, u.ID).Scan(&myDM)
	if errors.Is(err, sql.ErrNoRows) {
		fail(w, 403, "profile unavailable")
		return
	}
	if err != nil {
		fail(w, 500, "could not save swipe")
		return
	}
	// A like can end in a conversation, so the liker must accept private
	// messages too, the same rule the nearby greeting applies. A pass has no
	// such side effect and stays allowed.
	if in.Action == "like" && myDM == 0 {
		fail(w, 403, "请先开启接收私信")
		return
	}
	var previous string
	var expired bool
	err = tx.QueryRowContext(r.Context(), `SELECT action,substr(updated_at,1,10)<? FROM swipes WHERE actor_id=? AND target_id=?`, dateKey(clock.Add(-discoverPassTTL)), u.ID, other).Scan(&previous, &expired)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		fail(w, 500, "could not save swipe")
		return
	}
	// Repeating the same action replays the previous outcome: no write, and a
	// like never charges a second daily credit. An aged-out pass is the one
	// exception, since the peer has resurfaced and the new pass must stick.
	replay := err == nil && previous == in.Action && !(in.Action == "pass" && expired)
	if !replay {
		if in.Action == "like" {
			quota, qerr := tx.ExecContext(r.Context(), `INSERT INTO discover_likes(user_id,day,count) VALUES(?,?,1) ON CONFLICT(user_id,day) DO UPDATE SET count=count+1 WHERE count<?`, u.ID, dateKey(clock), discoverDailyLikes)
			if qerr != nil {
				fail(w, 500, "could not save swipe")
				return
			}
			n, qerr := quota.RowsAffected()
			if qerr != nil {
				fail(w, 500, "could not save swipe")
				return
			}
			if n == 0 {
				fail(w, 429, "daily like limit reached")
				return
			}
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO swipes(actor_id,target_id,action,created_at,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(actor_id,target_id) DO UPDATE SET action=excluded.action,updated_at=excluded.updated_at`, u.ID, other, in.Action, at, at); err != nil {
			fail(w, 500, "could not save swipe")
			return
		}
	}
	matched := false
	conversationID := ""
	if in.Action == "like" {
		var liked int
		if err = tx.QueryRowContext(r.Context(), `SELECT COALESCE((SELECT 1 FROM swipes WHERE actor_id=? AND target_id=? AND action='like'),0)`, other, u.ID).Scan(&liked); err != nil {
			fail(w, 500, "could not save swipe")
			return
		}
		if liked != 0 {
			a, b := ordered(u.ID, other)
			// The ordered pair plus ON CONFLICT keeps a mutual like from ever
			// creating a second match or a second conversation.
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO matches(id,user1_id,user2_id,created_at) VALUES(?,?,?,?) ON CONFLICT(user1_id,user2_id) DO NOTHING`, randomID(), a, b, at); err != nil {
				fail(w, 500, "could not save swipe")
				return
			}
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO conversations(id,user1_id,user2_id,updated_at) VALUES(?,?,?,?) ON CONFLICT(user1_id,user2_id) DO NOTHING`, randomID(), a, b, at); err != nil {
				fail(w, 500, "could not save swipe")
				return
			}
			if err = tx.QueryRowContext(r.Context(), `SELECT id FROM conversations WHERE user1_id=? AND user2_id=?`, a, b).Scan(&conversationID); err != nil {
				fail(w, 500, "could not save swipe")
				return
			}
			matched = true
		}
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "could not save swipe")
		return
	}
	if !matched {
		writeJSON(w, 200, map[string]any{"matched": false})
		return
	}
	conversation, err := s.conversation(r, u, conversationID)
	if err != nil {
		fail(w, 403, "direct messages unavailable")
		return
	}
	writeJSON(w, 200, map[string]any{"matched": true, "conversation": conversation})
}

func (s *Server) discoverMatches(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	u := current(r)
	rows, err := s.db.QueryContext(r.Context(), `SELECT peer.id,peer.alias,peer.avatar,m.created_at,COALESCE((SELECT c.id FROM conversations c WHERE c.user1_id=m.user1_id AND c.user2_id=m.user2_id),'')
FROM matches m
JOIN users me ON me.id=?
JOIN users peer ON peer.id=CASE WHEN m.user1_id=? THEN m.user2_id ELSE m.user1_id END
WHERE (m.user1_id=? OR m.user2_id=?) AND `+discoverBlockFilter+`
ORDER BY m.created_at DESC,peer.id`, u.ID, u.ID, u.ID, u.ID)
	if err != nil {
		fail(w, 500, "could not load matches")
		return
	}
	defer rows.Close()
	out := []matchItem{}
	for rows.Next() {
		var m matchItem
		if err = rows.Scan(&m.ID, &m.Alias, &m.Avatar, &m.MatchedAt, &m.ConversationID); err != nil {
			fail(w, 500, "could not load matches")
			return
		}
		out = append(out, m)
	}
	if rows.Err() != nil {
		fail(w, 500, "could not load matches")
		return
	}
	writeJSON(w, 200, out)
}
