# Streambox

Streaming-first personal music player with a Flutter client and a Python FastAPI backend.

V1 uses MusicBrainz for metadata search, Cover Art Archive for artwork, and adapter-based stream resolution through `yt-dlp`, direct audio URLs, and internet radio URLs. It does not download, cache, or rehost audio.

## Repository Layout

- `backend/` - FastAPI API, SQLite persistence, metadata cache, source adapters, and pytest tests.
- `frontend/` - Flutter app source using `media_kit` for Android, macOS, Linux, and Windows audio playback.

## Prerequisites

Install these before running the app:

- `uv`
- Flutter SDK with Android and desktop support enabled
- Visual Studio Build Tools with the Desktop development with C++ workload for Windows desktop builds
- Optional: `ffmpeg`, depending on source formats handled by `yt-dlp`

This workspace now uses `uv` for the backend. `uv` installed Python 3.12.13 and `yt-dlp` inside `backend/.venv`. Flutter is installed locally at `.toolchains/flutter`, and Visual Studio Build Tools 2022 is installed for Windows desktop builds.

## Backend Setup

```powershell
cd backend
uv sync --extra dev
Copy-Item .env.example .env
uv run uvicorn app.main:app --reload
```

The API runs at `http://127.0.0.1:8000` by default.

Set `MUSICBRAINZ_USER_AGENT` in `backend/.env` to a real app/contact string before making regular MusicBrainz requests.

## Frontend Setup

Generate the platform project files after Flutter is installed:

```powershell
cd frontend
..\.toolchains\flutter\bin\flutter.bat pub get
..\.toolchains\flutter\bin\flutter.bat run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use another device target in place of `windows` for Android, macOS, or Linux.

Android builds require an Android SDK. `flutter doctor -v` will report this as missing until Android Studio or the Android command-line SDK is installed and configured.

## API

- `GET /health`
- `GET /api/search?q=...`
- `POST /api/resolve`
- `GET /api/sources`
- `GET /api/playlists`
- `POST /api/playlists`
- `PUT /api/playlists/{id}`
- `GET /api/favorites`
- `POST /api/favorites`
- `DELETE /api/favorites/{id}`
- `GET /api/history`
- `POST /api/history`

## Testing

```powershell
cd backend
uv run pytest
```

```powershell
cd frontend
..\.toolchains\flutter\bin\flutter.bat test
```

## Source Policy

`yt-dlp` is used only as a stream resolver for content and sources you are allowed to access. The backend does not bypass DRM, download tracks, persist audio files, or expose a proxy for rehosting third-party audio.
