# Rust Core Migration

FastAPI is now a **legacy fallback backend** for Streambox. It remains in the
repo so Flutter can keep using stable HTTP contracts while the native Rust core
absorbs features incrementally. Do not delete FastAPI routes, schemas, tests, or
storage code until Flutter no longer depends on the corresponding `CoreClient`
method.

## Current Backend Roles

- **Rust core** is the target runtime for offline/local app logic and native
  integration. Today it provides native health/version diagnostics through FFI.
- **FastAPI** is the compatibility fallback for network metadata, source
  resolution, local profile data, and debug endpoints during migration.
- **Flutter `HybridCoreClient`** should prefer a Rust-backed implementation when
  one exists and fall back to FastAPI for unmigrated features.

## `CoreClient` FastAPI-Only Methods

As of this migration note, every `CoreClient` feature method except
`nativeHealth()` is still serviced by FastAPI through `RustCoreClient`'s
`fallbackApiClient`:

| `CoreClient` method | FastAPI endpoint(s) / responsibility | Migration status |
| --- | --- | --- |
| `discover(query, scope)` | `GET /api/discover` discovery search | FastAPI-only |
| `discoverPlayable(query)` | `GET /api/discover/playable` playable discovery | FastAPI-only |
| `runtimeDebug()` | `GET /api/debug/runtime` backend/runtime diagnostics | FastAPI-only |
| `albumDetail(browseId)` | `GET /api/albums/{browse_id}` album metadata | FastAPI-only |
| `artistDetail(browseId)` | `GET /api/artists/{browse_id}` artist metadata | FastAPI-only |
| `resolve(track, adapters, sourceUrl)` | `POST /api/resolve` source resolution | FastAPI-only |
| `sources()` | `GET /api/sources` adapter capabilities | FastAPI-only |
| `playlists()` | `GET /api/playlists` local playlists | FastAPI-only |
| `createPlaylist(name, tracks)` | `POST /api/playlists` local playlist creation | FastAPI-only |
| `favorites()` | `GET /api/favorites` local favorites | FastAPI-only |
| `favorite(item)` | `POST /api/favorites` local favorite writes | FastAPI-only |
| `addHistory(item)` | `POST /api/history` playback history writes | FastAPI-only |
| `history()` | `GET /api/history` playback history reads | FastAPI-only |
| `nativeHealth()` | Rust FFI health check with non-Rust fallback | Rust-backed |

When a method becomes Rust-backed, update this table in the same change that
switches Flutter routing so the fallback surface remains visible.

## Migration Checklist

Keep this checklist current. A box is only complete when the Rust path is wired
through Flutter, covered by tests, and the FastAPI fallback/removal decision is
recorded.

### Before Restructuring FastAPI

Do **not** move FastAPI into `backend/legacy_fastapi/` until all of these design
areas are stable:

- [ ] Playlists data model, update semantics, and export/import behavior.
- [ ] Favorites schema, identity/de-duplication rules, and deletion behavior.
- [ ] Playback history retention, ordering, privacy, and sync/export decisions.
- [ ] Source index ownership, refresh strategy, and cache invalidation rules.
- [ ] Ranking strategy for discovery results and source candidate ordering.
- [ ] Plugin protocol boundaries for source adapters and metadata providers.

### Feature Migration

- [ ] Define Rust-owned SQLite migrations for playlists, favorites, and history.
- [ ] Port playlist read/create/update behavior and preserve API contract
      fixtures.
- [ ] Port favorites read/write/delete behavior and preserve identity semantics.
- [ ] Port playback history writes and bounded reads.
- [ ] Decide whether discovery/search stays network-backed, becomes plugin
      backed, or remains a FastAPI-only optional service.
- [ ] Port source capability listing and source resolution or define the plugin
      protocol that owns them.
- [ ] Port album/artist detail lookup or document the external metadata provider
      boundary.
- [ ] Replace runtime debug output with Rust/native diagnostics where possible.
- [ ] Update `CoreClient` routing and tests method-by-method as Rust features
      land.

### FastAPI Decommission Gates

FastAPI routes may only be removed after all of the following are true for the
route's feature area:

- [ ] Flutter no longer calls the route in normal, fallback, or debug flows.
- [ ] Contract tests exist for the Rust/native replacement.
- [ ] Local data migration or compatibility handling is documented.
- [ ] Release notes identify any user-visible migration impact.
- [ ] The `CoreClient` FastAPI-only table above no longer lists the method.

Until these gates are met, keep the existing FastAPI app and route tests intact.
