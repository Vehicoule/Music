from fastapi import APIRouter, HTTPException

from app.routes.dependencies import SourcesDep
from app.schemas import AlbumDetail, ArtistDetail


router = APIRouter(prefix="/api", tags=["details"])


@router.get("/albums/{browse_id}", response_model=AlbumDetail)
async def album_detail(browse_id: str, sources: SourcesDep) -> AlbumDetail:
    detail = await sources.ytmusic_album_detail(browse_id)
    if detail is None or not detail.title:
        raise HTTPException(status_code=404, detail="Album not found")
    return detail


@router.get("/artists/{browse_id}", response_model=ArtistDetail)
async def artist_detail(browse_id: str, sources: SourcesDep) -> ArtistDetail:
    detail = await sources.ytmusic_artist_detail(browse_id)
    if detail is None or not detail.name:
        raise HTTPException(status_code=404, detail="Artist not found")
    return detail
