# Streambox Backend

Legacy FastAPI fallback service for metadata search, stream source resolution,
and local profile data while Streambox migrates to the native Rust core.

## Legacy Status

FastAPI remains the fallback backend for Flutter `CoreClient` methods that have
not moved to Rust yet. Keep its routes and tests in place until Flutter no
longer depends on them. Do not move this app into `backend/legacy_fastapi/`
until playlists, favorites, history, source index, ranking, and plugin protocol
decisions are stable. Track that work in `../docs/rust-core-migration.md`.

## Main Components

- `app/services/musicbrainz.py` searches MusicBrainz and caches parsed track metadata.
- `app/sources/` contains source adapters for `yt-dlp`, direct stream URLs, and internet radio.
- `app/routes/` exposes search, resolve, sources, playlists, favorites, and history APIs.
- `app/core/db.py` owns the SQLite schema and metadata cache helpers.

## Run

```powershell
uv sync --extra dev
Copy-Item .env.example .env
uv run uvicorn app.main:app --reload
```

`uv` manages Python 3.12 through `.python-version` and installs `yt-dlp` into the backend virtualenv.

## Adapter Notes

- `yt_dlp`: calls the configured `yt-dlp` binary with `--no-download` and returns the resolved playable URL when available. Run the API with `uv run` so the virtualenv script path is available.
- `direct_url`: accepts HTTP/HTTPS stream URLs.
- `internet_radio`: starts with a small built-in station list and can be expanded into persisted station management.
