package main

import (
	"database/sql"
	"errors"
	"math"
	"net/http"
	"sort"
	"time"
)

const nearbyRadiusKm = 5
const nearbyGreeting = "你好，方便聊聊吗？"

// The only location record is the latest coarse grid cell and its expiry.
// Quota records deliberately contain no location or encounter telemetry.
func migrateNearby(db *sql.DB) error {
	rows, err := db.Query(`PRAGMA table_info(users)`)
	if err != nil {
		return err
	}
	hasGender := false
	hasRevision := false
	for rows.Next() {
		var cid, notNull, pk int
		var name, typ string
		var def any
		if err = rows.Scan(&cid, &name, &typ, &notNull, &def, &pk); err != nil {
			rows.Close()
			return err
		}
		if name == "gender" {
			hasGender = true
		}
		if name == "nearby_revision" {
			hasRevision = true
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if !hasGender {
		if _, err = db.Exec(`ALTER TABLE users ADD COLUMN gender TEXT NOT NULL DEFAULT 'undisclosed' CHECK(gender IN ('male','female','undisclosed'))`); err != nil {
			return err
		}
	}
	if !hasRevision {
		if _, err = db.Exec(`ALTER TABLE users ADD COLUMN nearby_revision INTEGER NOT NULL DEFAULT 0 CHECK(nearby_revision>=0)`); err != nil {
			return err
		}
	}
	_, err = db.Exec(`
CREATE TABLE IF NOT EXISTS nearby_locations(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,latitude REAL NOT NULL,longitude REAL NOT NULL,expires_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS idx_nearby_expiry ON nearby_locations(expires_at);
CREATE TABLE IF NOT EXISTS nearby_greetings(sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,day TEXT NOT NULL,count INTEGER NOT NULL CHECK(count BETWEEN 1 AND 10),PRIMARY KEY(sender_id,day));`)
	return err
}

func validGender(g string) bool { return g == "male" || g == "female" || g == "undisclosed" }

type nearbyItem struct {
	ID            string `json:"id"`
	Alias         string `json:"alias"`
	Gender        string `json:"gender"`
	DistanceLabel string `json:"distanceLabel"`
}
type nearbyResponse struct {
	Enabled   bool         `json:"enabled"`
	ExpiresAt string       `json:"expiresAt,omitempty"`
	RadiusKm  int          `json:"radiusKm"`
	Items     []nearbyItem `json:"items"`
	Revision  int64        `json:"revision"`
}

func (s *Server) cleanupNearby() {
	_, _ = s.db.Exec(`DELETE FROM nearby_locations WHERE expires_at<=?`, time.Now().UnixMilli())
	_, _ = s.db.Exec(`DELETE FROM nearby_greetings WHERE day<?`, time.Now().UTC().Format("2006-01-02"))
}
func (s *Server) nearbyCleanupLoop() {
	defer s.cleanupWG.Done()
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-s.stopCleanup:
			return
		case <-ticker.C:
			s.cleanupNearby()
		}
	}
}

func gridDistanceKm(lat1, lon1, lat2, lon2 float64) float64 {
	const rad = math.Pi / 180
	dlat, dlon := (lat2-lat1)*rad, (lon2-lon1)*rad
	a := math.Pow(math.Sin(dlat/2), 2) + math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Pow(math.Sin(dlon/2), 2)
	return 6371 * 2 * math.Asin(math.Sqrt(math.Min(1, math.Max(0, a))))
}
func coarseDistanceLabel(distance float64) string {
	if distance < 1 {
		return "1 公里内"
	}
	if distance < 3 {
		return "1–3 公里"
	}
	return "3–5 公里"
}

func (s *Server) nearby(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	s.cleanupNearby()
	u := current(r)
	out := nearbyResponse{RadiusKm: nearbyRadiusKm, Items: []nearbyItem{}}
	// One statement gives a consistent view of own consent and every peer.
	clock := time.Now().UnixMilli()
	rows, err := s.db.QueryContext(r.Context(), `SELECT me.nearby_revision,own.latitude,own.longitude,own.expires_at,peer.id,peer.alias,peer.gender,loc.latitude,loc.longitude
FROM users me LEFT JOIN nearby_locations own ON own.user_id=me.id AND own.expires_at>? AND me.allow_dm=1
LEFT JOIN users peer ON own.user_id IS NOT NULL AND peer.id<>me.id AND peer.campus=me.campus AND peer.allow_dm=1
 AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=me.id AND blocked_id=peer.id) OR (blocker_id=peer.id AND blocked_id=me.id))
LEFT JOIN nearby_locations loc ON loc.user_id=peer.id AND loc.expires_at>?
WHERE me.id=?`, clock, clock, u.ID)
	if err != nil {
		fail(w, 500, "暂时无法加载附近的人")
		return
	}
	defer rows.Close()
	for rows.Next() {
		var lat, lon sql.NullFloat64
		var expires sql.NullInt64
		var id, alias, gender sql.NullString
		var plat, plon sql.NullFloat64
		if err = rows.Scan(&out.Revision, &lat, &lon, &expires, &id, &alias, &gender, &plat, &plon); err != nil {
			fail(w, 500, "暂时无法加载附近的人")
			return
		}
		if !expires.Valid {
			continue
		}
		out.Enabled = true
		out.ExpiresAt = time.UnixMilli(expires.Int64).UTC().Format(time.RFC3339)
		if !plat.Valid || !plon.Valid {
			continue
		}
		d := gridDistanceKm(lat.Float64, lon.Float64, plat.Float64, plon.Float64)
		if d <= nearbyRadiusKm {
			out.Items = append(out.Items, nearbyItem{ID: id.String, Alias: alias.String, Gender: gender.String, DistanceLabel: coarseDistanceLabel(d)})
		}
	}
	if rows.Err() != nil {
		fail(w, 500, "暂时无法加载附近的人")
		return
	}
	// Stable alias order avoids exposing more precise distance through ranking.
	sort.Slice(out.Items, func(i, j int) bool {
		if out.Items[i].Alias == out.Items[j].Alias {
			return out.Items[i].ID < out.Items[j].ID
		}
		return out.Items[i].Alias < out.Items[j].Alias
	})
	writeJSON(w, 200, out)
}

func (s *Server) nearbyLocation(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	u := current(r)
	if r.Method == "DELETE" {
		tx, err := s.db.BeginTx(r.Context(), nil)
		if err == nil {
			defer tx.Rollback()
			err = invalidateNearby(r, tx, u.ID)
			if err == nil {
				err = tx.Commit()
			}
		}
		if err != nil {
			fail(w, 500, "暂时无法关闭附近的人")
			return
		}
		w.WriteHeader(204)
		return
	}
	var in struct {
		Latitude  *float64 `json:"latitude"`
		Longitude *float64 `json:"longitude"`
		Revision  *int64   `json:"revision"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.Revision == nil || *in.Revision < 0 {
		fail(w, 400, "请先刷新附近的人状态")
		return
	}
	if in.Latitude == nil || in.Longitude == nil || math.IsNaN(*in.Latitude) || math.IsInf(*in.Latitude, 0) || math.IsNaN(*in.Longitude) || math.IsInf(*in.Longitude, 0) || *in.Latitude < -90 || *in.Latitude > 90 || *in.Longitude < -180 || *in.Longitude > 180 {
		fail(w, 400, "位置信息无效")
		return
	}
	lat, lon := math.Round(*in.Latitude*100)/100, math.Round(*in.Longitude*100)/100
	// Consent and revision are checked together, before any location write. A
	// revoke advances the persistent revision even when there is no location.
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "暂时无法更新位置")
		return
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(r.Context(), `UPDATE users SET nearby_revision=nearby_revision+1 WHERE id=? AND allow_dm=1 AND nearby_revision=?`, u.ID, *in.Revision)
	if err != nil {
		fail(w, 500, "暂时无法更新位置")
		return
	}
	n, err := result.RowsAffected()
	if err != nil {
		fail(w, 500, "暂时无法更新位置")
		return
	}
	if n == 0 {
		var allow bool
		if err = tx.QueryRowContext(r.Context(), `SELECT allow_dm FROM users WHERE id=?`, u.ID).Scan(&allow); err != nil {
			fail(w, 500, "暂时无法更新位置")
			return
		}
		if !allow {
			fail(w, 403, "请先开启接收私信")
		} else {
			fail(w, 409, "位置分享状态已变更，请刷新后重试")
		}
		return
	}
	_, err = tx.ExecContext(r.Context(), `INSERT INTO nearby_locations(user_id,latitude,longitude,expires_at) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET latitude=excluded.latitude,longitude=excluded.longitude,expires_at=excluded.expires_at`, u.ID, lat, lon, time.Now().Add(30*time.Minute).UnixMilli())
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		fail(w, 500, "暂时无法更新位置")
		return
	}
	s.nearby(w, r)
}

func invalidateNearby(r *http.Request, tx *sql.Tx, userID string) error {
	if _, err := tx.ExecContext(r.Context(), `UPDATE users SET nearby_revision=nearby_revision+1 WHERE id=?`, userID); err != nil {
		return err
	}
	_, err := tx.ExecContext(r.Context(), `DELETE FROM nearby_locations WHERE user_id=?`, userID)
	return err
}

func (s *Server) nearbyGreet(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	var in struct{}
	if !decodeBody(w, r, &in) {
		return
	}
	u := current(r)
	other := r.PathValue("id")
	if other == u.ID {
		fail(w, 400, "cannot message yourself")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "could not create conversation")
		return
	}
	defer tx.Rollback()
	clock := time.Now().UTC()
	var lat, lon, plat, plon float64
	err = tx.QueryRowContext(r.Context(), `SELECT own.latitude,own.longitude,loc.latitude,loc.longitude FROM users me JOIN users peer ON peer.id=? AND peer.campus=me.campus JOIN nearby_locations own ON own.user_id=me.id JOIN nearby_locations loc ON loc.user_id=peer.id WHERE me.id=? AND me.allow_dm=1 AND peer.allow_dm=1 AND own.expires_at>? AND loc.expires_at>? AND NOT EXISTS(SELECT 1 FROM blocks WHERE (blocker_id=me.id AND blocked_id=peer.id) OR (blocker_id=peer.id AND blocked_id=me.id))`, other, u.ID, clock.UnixMilli(), clock.UnixMilli()).Scan(&lat, &lon, &plat, &plon)
	if errors.Is(err, sql.ErrNoRows) {
		fail(w, 403, "对方暂时不在附近或无法接收招呼")
		return
	}
	if err != nil {
		fail(w, 500, "could not create conversation")
		return
	}
	if gridDistanceKm(lat, lon, plat, plon) > nearbyRadiusKm {
		fail(w, 403, "对方暂时不在附近或无法接收招呼")
		return
	}
	a, b := ordered(u.ID, other)
	var id string
	err = tx.QueryRowContext(r.Context(), `SELECT id FROM conversations WHERE user1_id=? AND user2_id=?`, a, b).Scan(&id)
	status := 200
	if errors.Is(err, sql.ErrNoRows) {
		var quota sql.Result
		quota, err = tx.ExecContext(r.Context(), `INSERT INTO nearby_greetings(sender_id,day,count) VALUES(?,?,1) ON CONFLICT(sender_id,day) DO UPDATE SET count=count+1 WHERE count<10`, u.ID, clock.Format("2006-01-02"))
		if err == nil {
			var n int64
			n, err = quota.RowsAffected()
			if err == nil && n == 0 {
				fail(w, 429, "今天已向 10 位新朋友打过招呼，请明天再试")
				return
			}
		}
		id = randomID()
		at := clock.Format(time.RFC3339Nano)
		if err == nil {
			_, err = tx.ExecContext(r.Context(), `INSERT INTO conversations(id,user1_id,user2_id,updated_at) VALUES(?,?,?,?)`, id, a, b, at)
		}
		if err == nil {
			_, err = tx.ExecContext(r.Context(), `INSERT INTO dm_messages(id,conversation_id,author_id,body,created_at) VALUES(?,?,?,?,?)`, randomID(), id, u.ID, nearbyGreeting, at)
		}
		status = 201
	}
	if err != nil {
		fail(w, 500, "could not create conversation")
		return
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "could not create conversation")
		return
	}
	conversation, err := s.conversation(r, u, id)
	if err != nil {
		fail(w, 403, "direct messages unavailable")
		return
	}
	writeJSON(w, status, conversation)
}
