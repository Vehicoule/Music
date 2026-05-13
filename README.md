# Streambox

Streambox is a streaming-first personal music app with a Flutter frontend and a
Rust native core — no HTTP server dependency. All data is local SQLite, all
provider integrations are native Rust.

## Project overview

Two-layer architecture:

- **`frontend/`**: Flutter desktop/mobile app — UI, playback, queue management,
  playlists, favorites, history. Communicates with Rust core through FFI
  (JSON-in/JSON-out protocol).
- **`native/streambox_core/`**: Rust native core — SQLite-backed app state,
  MusicBrainz metadata, ListenBrainz popularity, yt-dlp subprocess integration,
  source index with FTS5. Exposed via C FFI (`cdylib`).

The legacy `backend/` FastAPI service was fully deleted on 2026-05-13. All
features now run through the Rust native core with zero HTTP fallback.

## Architecture

```
Flutter UI (Dart)                  Rust Native Core (Rust)
══════════════════════             ═══════════════════════
main.dart                          lib.rs
  └── RustCoreClient (FFI)           ├── db.rs          (SQLite FTS5)
       └── FfiNativeCore             ├── ffi.rs         (C FFI boundary)
            └── DynamicLibrary       ├── services/
               ↓                         ├── musicbrainz.rs
         streambox_core.dll              ├── listenbrainz.rs
                                         ├── ytdlp.rs
                                         └── discovery.rs
                                    └── ranking.rs (shared scoring)
```

FFI protocol: JSON-in/JSON-out via `{ok, data}` / `{ok, error: {code, message}}`
envelope. All Rust functions are `#[no_mangle] pub extern "C"`.

## All Rust-backed features

| Feature | Rust module | FFI endpoint |
|---------|-------------|-------------|
| Health diagnostics | `lib.rs` | `streambox_health_json` |
| DB health | `db.rs` | `streambox_db_health_json` |
| Playlists CRUD | `db.rs` | `streambox_playlists_*_json` |
| Favorites CRUD | `db.rs` | `streambox_favorites_*_json` |
| Play history | `db.rs` | `streambox_history_*_json` |
| Source index search | `db.rs` | `streambox_source_index_*_json` |
| MusicBrainz search | `musicbrainz.rs` | `streambox_musicbrainz_search_json` |
| yt-dlp search/resolve | `ytdlp.rs` | `streambox_ytdlp_*_json` |
| Unified discovery | `discovery.rs` | `streambox_discover_json` |
| ListenBrainz popularity | `listenbrainz.rs` | (internal, enrichment) |
| Source capabilities | `ffi.rs` | `streambox_sources_json` |
| Runtime debug | `ffi.rs` | `streambox_runtime_debug_json` |

## Required external tools

- Flutter SDK for the frontend.
- Rust toolchain (`rustup`, `cargo`, `rustfmt`) for the native core.
- `yt-dlp` binary on `PATH` for YouTube Music resolution.

## Local development commands

### Rust core

From `native/streambox_core/`:

```bash
cargo fmt
cargo test
cargo build
```

### Frontend

From `frontend/`:

```bash
flutter pub get
flutter run -d windows
flutter build windows
```

Use a different Flutter device/build target as needed: `linux`, `macos`, or an
Android device ID.

## Test suite

```bash
# Run all Rust tests (lib + integration)
cd native/streambox_core
cargo test

# Flutter tests (requires Flutter SDK)
cd frontend
flutter test
```
