# Streambox API Contracts

This document freezes the current FastAPI contract while the app migrates to a
serverless native Rust core. FastAPI is a legacy fallback backend during this
migration: Flutter may call Rust for migrated features and FastAPI for
unmigrated features, but these response shapes remain the compatibility
baseline. Do not remove a FastAPI route until Flutter no longer depends on the
matching contract.

## Search And Discovery

- `GET /api/discover?q=<query>&scope=all|songs|albums|artists|videos`
- Returns `DiscoverResponse` with typed `DiscoverItem` rows.
- Playable rows use `kind: song` or `kind: video` and include `track`.
- Non-playable rows use `kind: album` with `album_result` or `kind: artist`
  with `artist_result`.

## Playback Resolve

- `POST /api/resolve`
- Request body includes `track`, optional `source_url`, and optional adapters.
- Returns short-lived `SourceCandidate` values and warnings.
- The app must not store downloaded audio or long-lived resolved stream URLs.

## Details

- `GET /api/albums/{browse_id}` returns album metadata and playable child tracks.
- `GET /api/artists/{browse_id}` returns artist metadata plus typed sections.

## Local Profile Data

- `GET /api/playlists`, `POST /api/playlists`, `PUT /api/playlists/{id}`
- `GET /api/favorites`, `POST /api/favorites`, `DELETE /api/favorites/{id}`
- `GET /api/history`, `POST /api/history`

These are the first features planned for migration to Rust-owned SQLite.

See [Rust Core Migration](rust-core-migration.md) for the current FastAPI-only `CoreClient` surface, migration checklist, and decommission gates.
