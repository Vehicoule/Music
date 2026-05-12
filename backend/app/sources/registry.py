from __future__ import annotations

from app.core.config import Settings
from app.core.db import Database
from app.schemas import (
    AdapterCapability,
    AdapterName,
    DiscoverWarning,
    ResolveRequest,
    ResolverDebugAttempt,
    SearchScope,
    SourceCandidate,
)
from app.sources.base import SourceAdapter
from app.sources.direct_url import DirectUrlAdapter
from app.sources.internet_radio import InternetRadioAdapter
from app.sources.ytdlp import YtDlpAdapter
from app.sources.ytmusic import YtMusicAdapter


SOURCE_SEARCH_BREADTH_TARGET = 8


class SourceRegistry:
    def __init__(self, settings: Settings, db: Database | None = None) -> None:
        adapters: dict[AdapterName, SourceAdapter] = {}
        if settings.enable_ytmusic:
            adapters[AdapterName.ytmusic] = YtMusicAdapter(settings, db=db)
        if settings.enable_ytdlp:
            adapters[AdapterName.ytdlp] = YtDlpAdapter(settings, db)
        if settings.enable_direct_url:
            adapters[AdapterName.direct_url] = DirectUrlAdapter()
        if settings.enable_internet_radio:
            adapters[AdapterName.internet_radio] = InternetRadioAdapter()
        self.adapters = adapters

    async def capabilities(self) -> list[AdapterCapability]:
        return [await adapter.capability() for adapter in self.adapters.values()]

    async def resolve(self, request: ResolveRequest) -> list[SourceCandidate]:
        candidates, _warnings = await self.resolve_with_warnings(request)
        return candidates

    async def resolve_with_warnings(
        self, request: ResolveRequest
    ) -> tuple[list[SourceCandidate], list[DiscoverWarning]]:
        requested = request.adapters or list(self.adapters.keys())
        candidates: list[SourceCandidate] = []
        warnings: list[DiscoverWarning] = []
        for name in requested:
            adapter = self.adapters.get(name)
            if not adapter:
                continue
            try:
                candidates.extend(await adapter.resolve(request))
                warning = getattr(adapter, "last_warning", None)
                if warning:
                    warnings.append(
                        DiscoverWarning(code=f"{name.value}_warning", message=str(warning))
                    )
            except Exception as exc:
                detail = str(exc).strip() or f"{type(exc).__name__}: {exc!r}"
                warnings.append(
                    DiscoverWarning(code=f"{name.value}_error", message=detail)
                )
                continue
        return candidates, warnings

    async def source_search_with_warnings(
        self, request: ResolveRequest, limit: int = 12
    ) -> tuple[list[SourceCandidate], list[DiscoverWarning]]:
        requested = request.adapters or [AdapterName.ytmusic, AdapterName.ytdlp]
        candidates: list[SourceCandidate] = []
        warnings: list[DiscoverWarning] = []
        seen: set[str] = set()
        breadth_target = min(limit, SOURCE_SEARCH_BREADTH_TARGET)
        for name in requested:
            adapter = self.adapters.get(name)
            if not adapter:
                continue
            source_search = getattr(adapter, "source_search", None)
            if source_search is None:
                continue
            try:
                for candidate in await source_search(request, limit=limit):
                    key = candidate.source_id or candidate.source_url or candidate.url
                    if key in seen:
                        continue
                    seen.add(key)
                    candidates.append(candidate)
                warning = getattr(adapter, "last_warning", None)
                if warning:
                    warnings.append(
                        DiscoverWarning(code=f"{name.value}_warning", message=str(warning))
                    )
                if (
                    candidates
                    and name == AdapterName.ytmusic
                    and len(candidates) >= breadth_target
                ):
                    break
            except Exception as exc:
                detail = str(exc).strip() or f"{type(exc).__name__}: {exc!r}"
                warnings.append(DiscoverWarning(code=f"{name.value}_error", message=detail))
        return candidates[:limit], warnings

    async def ytmusic_search(
        self, query: str, scope: SearchScope = SearchScope.all, limit: int = 12
    ):
        adapter = self.adapters.get(AdapterName.ytmusic)
        if adapter is None:
            return []
        search = getattr(adapter, "search", None)
        if search is None:
            return []
        return await search(query, scope=scope, limit=limit)

    async def ytmusic_album_detail(self, browse_id: str):
        adapter = self.adapters.get(AdapterName.ytmusic)
        if adapter is None:
            return None
        album_detail = getattr(adapter, "album_detail", None)
        if album_detail is None:
            return None
        return await album_detail(browse_id)

    async def ytmusic_artist_detail(self, browse_id: str):
        adapter = self.adapters.get(AdapterName.ytmusic)
        if adapter is None:
            return None
        artist_detail = getattr(adapter, "artist_detail", None)
        if artist_detail is None:
            return None
        return await artist_detail(browse_id)

    def source_search_targets(self, request: ResolveRequest, limit: int = 12) -> list[str]:
        requested = request.adapters or [AdapterName.ytmusic, AdapterName.ytdlp]
        targets: list[str] = []
        if AdapterName.ytmusic in requested and AdapterName.ytmusic in self.adapters:
            targets.extend(
                [
                    f"ytmusic:songs:{request.track.title}",
                    f"ytmusic:videos:{request.track.title}",
                ]
            )
        adapter = self.adapters.get(AdapterName.ytdlp)
        if adapter and AdapterName.ytdlp in requested:
            search_targets = getattr(adapter, "_source_search_targets", None)
            if search_targets is not None:
                targets.extend(search_targets(request, limit=limit))
        return targets

    async def resolve_debug(self, request: ResolveRequest) -> list[ResolverDebugAttempt]:
        requested = request.adapters or [AdapterName.ytdlp]
        attempts: list[ResolverDebugAttempt] = []
        for name in requested:
            adapter = self.adapters.get(name)
            if not adapter:
                continue
            debug_resolve = getattr(adapter, "resolve_debug", None)
            if debug_resolve is None:
                continue
            try:
                attempts.extend(await debug_resolve(request))
            except Exception as exc:
                detail = str(exc).strip() or f"{type(exc).__name__}: {exc!r}"
                attempts.append(
                    ResolverDebugAttempt(adapter=name, target="", warning=detail)
                )
        return attempts
