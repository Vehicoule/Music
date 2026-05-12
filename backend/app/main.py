from contextlib import asynccontextmanager
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil

from fastapi import FastAPI
from fastapi import Query
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.db import Database
from app.routes import details, discover, favorites, playlists, search, sources
from app.services.listenbrainz import ListenBrainzClient
from app.services.musicbrainz import MusicBrainzClient
from app.services.discovery import DiscoveryService
from app.services.source_index import SourceIndex
from app.sources.registry import SourceRegistry
from app.schemas import SearchScope


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    db = Database(settings.database_path)
    db.init()
    app.state.settings = settings
    app.state.db = db
    app.state.listenbrainz = ListenBrainzClient(settings, db)
    app.state.musicbrainz = MusicBrainzClient(settings, db, app.state.listenbrainz)
    app.state.sources = SourceRegistry(settings, db)
    app.state.source_index = SourceIndex(db)
    yield


API_VERSION = "0.3.0"
STARTED_AT = datetime.now(timezone.utc)


app = FastAPI(title="Streambox API", version=API_VERSION, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:*", "http://127.0.0.1:*"],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(search.router)
app.include_router(discover.router)
app.include_router(details.router)
app.include_router(sources.router)
app.include_router(playlists.router)
app.include_router(favorites.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/debug/runtime")
async def runtime_debug() -> dict[str, str | bool]:
    settings = get_settings()
    backend_dir = Path(__file__).resolve().parents[1]
    venv_scripts = backend_dir / ".venv" / "Scripts"
    expected_ytdlp_path = venv_scripts / "yt-dlp.exe"
    path_parts = [os.path.normcase(os.path.normpath(part)) for part in os.environ.get("PATH", "").split(os.pathsep)]
    expected_scripts_path = os.path.normcase(os.path.normpath(str(venv_scripts)))
    ytdlp_launch_mode = "python_module" if settings.ytdlp_python else "binary"
    ytdlp_path = settings.ytdlp_python if settings.ytdlp_python else shutil.which(settings.ytdlp_binary)
    return {
        "api_version": API_VERSION,
        "started_at": STARTED_AT.isoformat(),
        "database_path": str(settings.database_path),
        "ytdlp_binary": settings.ytdlp_binary,
        "ytdlp_python": settings.ytdlp_python or "",
        "ytdlp_launch_mode": ytdlp_launch_mode,
        "expected_ytdlp_path": str(expected_ytdlp_path),
        "venv_scripts_on_path": expected_scripts_path in path_parts,
        "ytdlp_path": ytdlp_path or "",
        "ytdlp_available": bool(ytdlp_path),
    }


@app.get("/api/debug/search")
async def search_debug(
    q: str = Query(min_length=1, max_length=500),
    scope: SearchScope = Query(default=SearchScope.all),
) -> dict:
    service = DiscoveryService(
        app.state.musicbrainz,
        app.state.sources,
        source_index=app.state.source_index,
    )
    return await service.debug_search(q, scope=scope)
