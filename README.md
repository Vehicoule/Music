# Streambox

Streambox is a streaming-first personal music app. It combines a Flutter client,
a native Rust local core, and a FastAPI provider service so local-library actions
can stay fast and offline-friendly while network/provider features remain behind
a stable HTTP fallback during the Rust migration.

## Project overview

The repository is organized around three cooperating runtimes:

- `frontend/`: Flutter desktop/mobile app for the user interface, playback,
  queue management, playlists, favorites, history, and hybrid Rust/FastAPI client
  routing.
- `native/streambox_core/`: Rust native core for local data, SQLite-backed app
  state, and FFI-backed features consumed by Flutter.
- `backend/`: FastAPI service for network/provider integrations, metadata
  discovery, source resolution, and compatibility fallback APIs while features
  move into Rust.

See [`docs/rust-core-migration.md`](docs/rust-core-migration.md) for the current
migration plan, ownership boundaries, and FastAPI decommission gates.

## Current architecture

- **Flutter frontend**: owns the app UI and playback experience. Its
  `HybridCoreClient` prefers Rust-backed behavior when available and falls back
  to FastAPI for unmigrated network/provider operations.
- **Rust local core**: owns native health/version diagnostics and local-library
  data paths that have been migrated to SQLite-backed Rust APIs exposed through
  FFI.
- **FastAPI provider/network fallback**: remains the HTTP compatibility layer for
  discovery, provider metadata, source resolution, and other routes that are not
  yet Rust-backed.

## Current Rust-backed features

- Native health diagnostics.
- Playlists.
- Favorites.
- Playback history.

These local-library features can still use FastAPI fallback behavior where the
Flutter client keeps compatibility paths enabled during migration.

## Current FastAPI-backed features

- Discovery and playable discovery.
- Source resolution and source capability listing.
- MusicBrainz/ListenBrainz metadata integration.
- Album and artist detail lookup.

## Required external tools

Install these before working with the app:

- Flutter SDK for the frontend.
- Rust toolchain (`rustup`, `cargo`, `rustfmt`) for the native core.
- Python 3.12 and `uv` for backend dependency management.
- `yt-dlp`/YouTube Music-related dependencies. The backend `uv sync` installs
  Python packages such as `yt-dlp` and `ytmusicapi`; run the API through
  `uv run` so virtualenv scripts are on `PATH`.

## Local development commands

### Backend

From `backend/`:

```bash
uv sync --extra dev
cp .env.example .env
uv run uvicorn app.main:app --reload
```

The API starts locally at `http://127.0.0.1:8000` by default.

### Frontend

From `frontend/`:

```bash
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter build windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use a different Flutter device/build target as needed, for example `linux`,
`macos`, or an Android device ID.

### Rust core

From `native/streambox_core/`:

```bash
cargo fmt
cargo test
cargo build
```
