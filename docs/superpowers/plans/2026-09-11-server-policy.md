# Server policy and smaller Android delivery

> **For agentic workers:** Use subagent-driven-development for independent Go and packaging tasks; root owns client integration and final verification.

**Goal:** Centralize business decisions in Go and reduce Android download size without dropping existing compatibility.

**Architecture:** Go already owns identity, authorization, persistence, media processing and idempotency. Add a canonical public policy document and authenticated database conversation search. Flutter retains presentation, device access, draft state and early input hints from that document. Publish architecture-specific APKs alongside the existing universal package.

**Tech Stack:** Existing Go/SQLite and Flutter/Dart; unchanged campus anonymous human chat.

## Contract and constraints

`GET /api/v1/config` returns `{categories: string[], limits:{postCharacters:1000,messageCharacters:2000,campusCharacters:80,aliasCharacters:40}, media:{maxAttachments:4,maxImageBytes:10485760,maxVideoBytes:52428800,maxTotalBytes:52428800,imageExtensions:["jpg","jpeg","png","webp"],videoExtensions:["mp4","webm"]}}`. This document comes from the same Go definitions as write validation. The authenticated client fetches it on connect/restore, before publishing the identity to the UI; no business-policy fallback is embedded in Flutter.

`GET /api/v1/conversations?q=...` performs literal substring search of peer alias and all conversation text, scoped to the current authenticated participant and existing block checks. Return existing DTO plus `matchSnippet` for search results, without marking messages read. Empty query preserves the existing list contract. Clients debounce and ignore outdated query responses.

Media aggregate 50 MiB is enforced in Go using stored media sizes and the binding transaction. Frontend checks are only early hints, never authorization.

## Tasks

- [x] Go: write failing policy/search/isolation/aggregate-limit tests; implement policy module, search query and authoritative write checks; run tests/vet.
- [x] Flutter: consume policy for categories, text and media limits; remove local record filtering in favor of server search with debounce/race/error states; update meaningful widget tests.
- [x] Packaging: inspect actual APK contents and Gradle inputs, enable release icon tree shaking and split ABI outputs; keep universal package. Do not remove Chinese character coverage or media support for a size claim.
- [x] Verify: Flutter analyze/tests, Go tests/vet, builds, browser regressions, APK signatures/ABI inspection and measured before/after sizes.
- [x] Document API/responsibility boundary and download variants; commit and push to the already authorized GitHub repository.
