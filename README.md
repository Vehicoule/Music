# Streambox

Streambox is a streaming-first music app with three main parts:

- `backend/`: FastAPI service for metadata discovery/search, source resolution, and local library APIs.
- `frontend/`: Flutter client for desktop/mobile UI, playback, queue, playlists, favorites, and history.
- `native/streambox_core/`: Rust native core used for local data and FFI-backed client features.

## Required external tools

Install these before working with the app:

- Flutter SDK for the frontend.
- Rust toolchain (`rustup`, `cargo`, `rustfmt`) for the native core.
- Python 3.12 and `uv` for backend dependency management.
- `yt-dlp`/YouTube Music-related dependencies. The backend `uv sync` installs Python packages such as `yt-dlp` and `ytmusicapi`; run the API through `uv run` so virtualenv scripts are on `PATH`.

## Backend setup

From `backend/`:

```bash
uv sync --extra dev
cp .env.example .env
uv run uvicorn app.main:app --reload
```

The API starts locally at `http://127.0.0.1:8000` by default.

## Frontend setup

From `frontend/`:

```bash
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter build windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use a different Flutter device/build target as needed, for example `linux`, `macos`, or an Android device ID.

## Native core

From `native/streambox_core/`:

```bash
cargo fmt
cargo test
cargo build
```

## Main API and features

- Discover/search music metadata and playable results.
- Resolve tracks to stream sources through configured adapters.
- Manage playlists.
- Add, list, and remove favorites.
- Record and display playback history.
