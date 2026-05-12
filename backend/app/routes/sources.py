from fastapi import APIRouter

from app.routes.dependencies import SourcesDep
from app.schemas import (
    AdapterCapability,
    ResolveRequest,
    ResolveResponse,
    ResolverDebugResponse,
)

router = APIRouter(prefix="/api", tags=["sources"])


@router.get("/sources", response_model=list[AdapterCapability])
async def list_sources(sources: SourcesDep) -> list[AdapterCapability]:
    return await sources.capabilities()


@router.post("/resolve", response_model=ResolveResponse)
async def resolve_track(request: ResolveRequest, sources: SourcesDep) -> ResolveResponse:
    candidates, warnings = await sources.resolve_with_warnings(request)
    return ResolveResponse(track=request.track, candidates=candidates, warnings=warnings)


@router.post("/resolve/debug", response_model=ResolverDebugResponse)
async def resolve_track_debug(
    request: ResolveRequest,
    sources: SourcesDep,
) -> ResolverDebugResponse:
    attempts = await sources.resolve_debug(request)
    return ResolverDebugResponse(track=request.track, attempts=attempts)
