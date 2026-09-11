# Video posters and nearby people

**Goal:** Real video covers before and after upload; opt-in nearby campus discovery with greetings; only gender as a new profile field. Preserve human anonymous chat and Go business authority.

## Shared contracts

- Videos: Go produces a bounded JPEG beside each original video (`originalPath + .poster.jpg`). `GET/HEAD /api/v1/media/{id}?view=poster` uses the SAME bearer/ticket and parent/campus/block checks as the original. Ticket response may add `posterUrl`; clients can select `view=poster` on the existing ticket URL. New uploads generate covers when FFmpeg is installed; existing videos generate lazily. Unavailable/undecodable cover has a clear fallback, never fake artwork. Delete and failed upload clean both files, with no create-after-delete race. FFmpeg is server-only. Local draft uses the existing muted paused video player, not another native codec bundle.
- `User.gender`: `male | female | undisclosed`, default `undisclosed`; additive migration. `PATCH /me` accepts only these values. Existing users and identities survive.
- `GET /api/v1/nearby` -> `{enabled:bool,revision:int,expiresAt?:string,radiusKm:5,items:[{id,alias,gender,distanceLabel}]}`. When not opted in, return empty items. No coordinates, precise distances, or last-seen telemetry in public results.
- `PUT /api/v1/nearby/location` `{latitude:number,longitude:number,revision:int}`: active user action; Go validates finite/range and the current revision atomically, rounds to 0.01-degree grid before storing, sets server-time 30-minute expiry. Requires receiving private messages enabled. Successful writes increment revision; DELETE and disabling DMs always increment too, preventing late old updates from restoring visibility. Return the same nearby response. Client requests approximate foreground location only; no background tracking.
- `DELETE /api/v1/nearby/location`: immediately remove sharing; no database location history. Account deletion cascades location/greeting rows. Expired entries excluded and periodically removed.
- `POST /api/v1/nearby/{id}/greet` `{}`: both opted-in/unexpired, within 5km grid distance, same campus, both allowDM, no block, not self. Go transaction validates current data, creates/reuses normal conversation; on first creation insert one fixed greeting `你好，方便聊聊吗？`. Repeated requests return same conversation without duplicate message. Max 10 new greetings/day/sender, persist rate decisions. Existing conversation may be opened without another greeting. Return normal conversation DTO. No bypass of user permissions through direct ID requests.
- Backend checks all visibility/distance/rate/profile constraints. Frontend only orchestrates explicit actions and shows state. Only isolated QA identities/coordinates used in automated location and greeting tests.

## Tasks / ownership

- Video backend worker: media.go, posters.go/tests, Dockerfile, FFmpeg setup/start helpers. Do not edit server.go/handlers.go (nearby worker owns those). No new config struct fields necessary: FFmpeg executable via environment/PATH. Root handles deployment and FFmpeg install.
- Nearby backend worker: server.go, handlers.go, nearby.go/tests, gender migration, policy.go optional metadata. Keep media auth readers valid if User shape changes. Coordinate new shared fields with root instead of editing media.go.
- Video client worker: media_viewer.dart, media_draft.dart (preview presentation only), media_video_native/web.dart, api.dart (poster URL method only), focused tests. No dependency additions.
- Root: nearby/profile UI, geolocator dependency + foreground coarse permission, navigation entry, integration, release/version/docs, browser and USB verification, commit/push to existing GitHub repo.

## Validation

Real referenced bee.mp4 frame, poster authorization/deletion/backfill; gender invalid values and old DB migration; nearby disabled/expired/outside/cross-campus/blocks/no-precision leakage; concurrent/repeated greetings and daily quota. Flutter analyze/tests, real API/browser flows, Android builds + connected-phone install preserving app data. No real phone location or real-user greetings are sent by automation.
