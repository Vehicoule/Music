# Rust Core Migration

FastAPI backend was removed on 2026-05-13. All features are now Rust-native.

**Post-migration cleanup completed 2026-05-13:**
- API version bumped from 0.1.0 to 0.3.0
- Stale FastAPI messages removed from Flutter diagnostics
- yt-dlp subprocess timeout enforced
- Shared ranking module extracted (`src/ranking.rs`)
- ListenBrainz wired into discovery scoring
- README updated to reflect all-Rust architecture

## Current Backend Roles

- **Rust core** is the sole runtime for all app logic. It provides health/version
  diagnostics, local library operations (playlists, favorites, history), network
  metadata (discovery, source resolution via yt-dlp and MusicBrainz), and runtime
  diagnostics through FFI.
- **FastAPI** has been removed. No HTTP backend exists.
- **Flutter `HybridCoreClient`** routes all calls through `RustCoreClient` for
  network metadata and uses Rust FFI for local library operations. If
  `rustCoreClient` is null, methods throw `StateError` indicating FastAPI is gone.

## `CoreClient` Migration Status

All methods are now Rust-backed:

| `CoreClient` method | Implementation | Status |
| --- | --- | --- |
| `nativeHealth()` | Rust FFI health check | Rust-backed |
| `nativeDbHealth()` | Rust FFI DB health check | Rust-backed |
| `playlists()` | Rust FFI (`streambox_playlists_list_json`) | Rust-backed |
| `createPlaylist(name, tracks)` | Rust FFI (`streambox_playlists_create_json`) | Rust-backed |
| `updatePlaylist(id, name, description, tracks)` | Rust FFI (`streambox_playlists_update_json`) | Rust-backed |
| `deletePlaylist(id)` | Rust FFI (`streambox_playlists_delete_json`) | Rust-backed |
| `favorites()` | Rust FFI (`streambox_favorites_list_json`) | Rust-backed |
| `favorite(item)` | Rust FFI (`streambox_favorites_add_json`) | Rust-backed |
| `unfavorite(favoriteId)` | Rust FFI (`streambox_favorites_remove_json`) | Rust-backed |
| `addHistory(item)` | Rust FFI (`streambox_history_add_json`) | Rust-backed |
| `history()` | Rust FFI (`streambox_history_list_json`) | Rust-backed |
| `discover(query, scope)` | Rust discovery orchestrator (`streambox_discover_json`) | Rust-backed |
| `discoverPlayable(query)` | Rust yt-dlp search (`streambox_ytdlp_search_json`) | Rust-backed |
| `resolve(track, adapters, sourceUrl)` | Rust yt-dlp resolve (`streambox_ytdlp_resolve_json`) | Rust-backed |
| `sources()` | Rust sources listing (`streambox_sources_json`) | Rust-backed |
| `albumDetail(browseId)` | Rust yt-dlp resolve (`streambox_ytdlp_resolve_json`) | Rust-backed |
| `artistDetail(browseId)` | Rust yt-dlp resolve (`streambox_ytdlp_resolve_json`) | Rust-backed |
| `runtimeDebug()` | Rust runtime debug (`streambox_runtime_debug_json`) | Rust-backed |

## Source Resolution

Source resolution is now entirely Rust-native. The Rust core uses yt-dlp for
source resolution and MusicBrainz for metadata enrichment:

- `resolve()` uses `streambox_ytdlp_resolve_json` directly.
- `sources()` uses `streambox_sources_json` which reports yt-dlp and MusicBrainz
  adapter capabilities.
- yt-dlp integration is an external process boundary managed by the Rust core.
- Provider integrations remain external/network/process boundaries; the Rust core
  owns the invocation and result parsing contracts.

## Migration Checklist

All items complete. FastAPI is fully removed.

### Feature Migration

- [x] Define Rust-owned SQLite migrations for playlists, favorites, and history.
- [x] Playlists: Rust read/create/update/delete behavior is implemented and wired
      through Flutter. FastAPI fallback removed.
- [x] Favorites: Rust read/write/delete behavior is implemented and wired through
      Flutter. FastAPI fallback removed.
- [x] History: Rust writes and bounded reads are implemented and wired through
      Flutter. FastAPI fallback removed.
- [x] Discovery/search is Rust-native via `streambox_discover_json` (source index
      -> yt-dlp -> MusicBrainz pipeline).
- [x] Source capability listing and source resolution via Rust yt-dlp FFI.
- [x] Album/artist detail lookup via Rust yt-dlp resolve FFI.
- [x] Runtime debug via Rust `streambox_runtime_debug_json`.
- [x] FastAPI backend directory deleted.
- [x] CI pipeline no longer references Python/pytest/backend.
- [x] `CoreClient` routing uses Rust FFI only; no ApiClient fallback.
