# Streambox API Contracts

This document freezes the API contract shapes originally defined by the FastAPI
backend. FastAPI has been fully removed (2026-05-13); the Rust native core now
serves all data through FFI using the same wire-compatible JSON shapes. These
contracts remain the authoritative baseline for both the Rust FFI output and the
`docs/api-contract-fixtures/` test fixtures.

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

## Shared Local Profile Shapes

Flutter decodes local profile endpoints into these shared model shapes:

### `PlaybackItem`

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `id` | Yes | string | Flutter falls back to an empty string when decoding a missing value, but compatible backends must emit an id. |
| `track` | Yes | `TrackMetadata` object | Required by Flutter decoding and by FastAPI/Pydantic validation. |
| `source` | No | `SourceCandidate` object or `null` | Present when the playback item has a resolved playable source. |
| `added_at` | No | timestamp string or `null` | Flutter accepts a missing or unparsable value as `null`; compatible backends should emit a valid timestamp when known. |

### `TrackMetadata`

Required fields are `id`, `title`, and `artists`. Optional fields are `album`,
`length_ms`, `score`, `release_count`, `listen_count`, `listener_count`,
`popularity_score`, `confidence_score`, `rank_reason`, `artwork_url`,
`source_provider`, `source_id`, `source_url`, `source_kind`, `raw_title`,
`canonical_title`, `canonical_artist`, `parse_source`, `match_reasons`, and
`source`. `artists` is an array of `{ "id": string | null, "name": string }`.
`album`, when present, is an object with optional `id`, `title`,
`release_group_id`, and `artwork_url`. Flutter defaults `source` to
`musicbrainz` and `match_reasons` to an empty array when absent, but Rust and
FastAPI should both emit these fields for parity with the fixtures.

### `SourceCandidate`

Required fields are `adapter`, `url`, and `title`. Optional fields are
`mime_type`, `duration_seconds`, `source_provider`, `source_id`, `source_url`,
`source_kind`, `raw_title`, `canonical_title`, `canonical_artist`,
`album_title`, `artwork_url`, `parse_source`, `confidence_score`,
`rank_reason`, `is_live`, and `headers`. Flutter defaults `is_live` to `false`
and `headers` to `{}` when absent; compatible backends should emit those defaults
explicitly.

## Local Profile Data

These endpoints are the first features planned for migration to Rust-owned
SQLite.

### Playlists

Fixtures:

- `docs/api-contract-fixtures/playlists/list.json`
- `docs/api-contract-fixtures/playlists/create.json`

#### `GET /api/playlists`

- Request shape: no JSON body.
- Response shape: HTTP `200` with an array of playlist objects sorted by most
  recently updated first.
- Playlist response fields:
  - Required: `id`, `name`, `description`, `tracks`, `created_at`, `updated_at`.
  - `tracks` is an array of `PlaybackItem` objects.
  - Flutter currently consumes `id`, `name`, `description`, and `tracks`; it
    ignores playlist timestamps, but Rust must still emit them to match FastAPI.

#### `POST /api/playlists`

- Request shape: JSON object with required `name`, optional `description`, and
  optional `tracks`.
- Request defaults: FastAPI defaults missing `description` to `""` and missing
  `tracks` to `[]`; Rust must do the same.
- Response shape: HTTP `201` with the created playlist object, including
  generated `id`, `created_at`, and `updated_at`.

#### `PUT /api/playlists/{playlist_id}`

- Request shape: JSON object with optional `name`, `description`, and `tracks`.
  Omitted fields keep their existing values.
- Response shape: HTTP `200` with the updated playlist object.
- Error shape: missing playlist ids return HTTP `404` with
  `{ "detail": "Playlist not found" }`.

### Favorites

Fixtures:

- `docs/api-contract-fixtures/favorites/list.json`
- `docs/api-contract-fixtures/favorites/add.json`

#### `GET /api/favorites`

- Request shape: no JSON body.
- Response shape: HTTP `200` with an array of favorite objects sorted by most
  recently created first.
- Favorite response fields:
  - Required: `id`, `item`, `created_at`.
  - `item` is a `PlaybackItem` object.
  - Flutter currently consumes `id` and `item`; it ignores `created_at`, but
    Rust must still emit it to match FastAPI.

#### `POST /api/favorites`

- Request shape: JSON object with required `item`, where `item` is a
  `PlaybackItem` object.
- Response shape: HTTP `201` with the created favorite object, including a
  generated favorite `id` and `created_at` timestamp.

#### `DELETE /api/favorites/{favorite_id}`

- Request shape: no JSON body.
- Response shape: HTTP `204` with an empty body. Deleting an unknown favorite id
  is currently idempotent and still returns `204`.

### History

Fixtures:

- `docs/api-contract-fixtures/history/list.json`
- `docs/api-contract-fixtures/history/add.json`

The current FastAPI history routes are implemented in `backend/app/routes/favorites.py`.
If Rust splits them into a separate module, the HTTP contract must remain the
same.

#### `GET /api/history`

- Request shape: no JSON body.
- Response shape: HTTP `200` with an array of `PlaybackItem` objects sorted by
  most recently played first, limited to 100 items.
- The persisted `played_at` ordering column is not part of the response body;
  clients use each item's `added_at` when they need an item-level timestamp.

#### `POST /api/history`

- Request shape: JSON object with required `item`, where `item` is a
  `PlaybackItem` object.
- Response shape: HTTP `201` with the same `PlaybackItem` shape that was added.

## Error Shape

FastAPI errors use the standard `detail` envelope and Rust must mirror it for
compatible status codes:

- Not found: `{ "detail": "Playlist not found" }`.
- Validation errors: `{ "detail": [ ... ] }`, where each entry identifies the
  invalid request location, message, and error type. The exact text may vary by
  validator version, but the top-level `detail` array shape must remain stable.
- Other client or server errors: `{ "detail": "<human-readable message>" }`.

Flutter wraps non-2xx responses as `ApiException('HTTP <status>: <body>')`, so
backend compatibility depends on preserving the HTTP status code and JSON body
shape rather than a Flutter-specific error model.

## Timestamp Format

All persisted timestamps are UTC instants serialized as ISO 8601/RFC 3339 JSON
strings, for example `2026-05-12T12:00:00Z`. Clients and servers must also
accept the equivalent explicit-offset form, for example
`2026-05-12T12:00:00+00:00`, because FastAPI/Pydantic and Dart `DateTime` both
support offset timestamps. Rust should emit UTC timestamps consistently and must
not emit Unix epoch numbers in JSON responses.

## Wire Compatibility

The Rust FFI protocol must be wire-compatible with the original FastAPI contracts
for every endpoint listed above. All fixtures in
`docs/api-contract-fixtures/` pass against the Rust core via
`tests/json_contract.rs`.

See [Rust Core Migration](rust-core-migration.md) for the full `CoreClient`
surface and migration status.
