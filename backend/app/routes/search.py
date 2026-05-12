import httpx
from fastapi import APIRouter, Query

from app.routes.dependencies import MusicBrainzDep
from app.schemas import SearchResponse

router = APIRouter(prefix="/api/search", tags=["search"])


@router.get("", response_model=SearchResponse)
async def search_tracks(
    musicbrainz: MusicBrainzDep,
    q: str = Query(min_length=1, max_length=200),
) -> SearchResponse:
    try:
        tracks = await musicbrainz.search_tracks(q)
    except httpx.HTTPError:
        tracks = []
    return SearchResponse(query=q, tracks=tracks)
