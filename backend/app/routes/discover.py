from fastapi import APIRouter, Query

from app.routes.dependencies import MusicBrainzDep, SourceIndexDep, SourcesDep
from app.schemas import DiscoverResponse, SearchScope
from app.services.discovery import DiscoveryService

router = APIRouter(prefix="/api/discover", tags=["discover"])


@router.get("", response_model=DiscoverResponse)
async def discover(
    musicbrainz: MusicBrainzDep,
    sources: SourcesDep,
    source_index: SourceIndexDep,
    q: str = Query(min_length=1, max_length=500),
    scope: SearchScope = Query(default=SearchScope.all),
) -> DiscoverResponse:
    service = DiscoveryService(musicbrainz, sources, source_index=source_index)
    return await service.discover(q, scope=scope)


@router.get("/playable", response_model=DiscoverResponse)
async def discover_playable(
    musicbrainz: MusicBrainzDep,
    sources: SourcesDep,
    q: str = Query(min_length=1, max_length=500),
) -> DiscoverResponse:
    service = DiscoveryService(musicbrainz, sources)
    return await service.discover_playable(q)
