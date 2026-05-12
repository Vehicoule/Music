from __future__ import annotations

import asyncio
import re
import time
from urllib.parse import parse_qs, urlparse

import httpx

from app.schemas import (
    AdapterName,
    ArtistMetadata,
    DiscoverItem,
    DiscoverKind,
    DiscoverResponse,
    DiscoverWarning,
    ResolveRequest,
    SearchMode,
    SearchScope,
    SourceCandidate,
    TrackMetadata,
)
from app.services.musicbrainz import MusicBrainzClient
from app.services.source_index import (
    SourceIndex,
    SourceIndexEntry,
    source_entries_from_candidates,
)
from app.sources.registry import SourceRegistry


DISCOVER_RESULT_LIMIT = 12


def is_url(value: str) -> bool:
    parsed = urlparse(normalize_input_url(value) or value.strip())
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


def normalize_input_url(value: str) -> str | None:
    clean = value.strip()
    if not clean:
        return None
    if clean.startswith("?"):
        video_id = parse_qs(clean[1:]).get("v", [None])[0]
        return _youtube_url(video_id) if video_id else None
    if clean.startswith("v="):
        video_id = parse_qs(clean).get("v", [None])[0]
        return _youtube_url(video_id) if video_id else None
    if clean.startswith(("youtube.com/", "www.youtube.com/", "youtu.be/", "www.youtu.be/")):
        clean = f"https://{clean}"
    parsed = urlparse(clean)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return None
    host = parsed.netloc.lower().removeprefix("www.")
    if host == "youtu.be":
        video_id = parsed.path.strip("/").split("/")[0]
        return _youtube_url(video_id) if video_id else clean
    if host in {"music.youtube.com", "youtube.com"} and parsed.path == "/watch":
        video_id = parse_qs(parsed.query).get("v", [None])[0]
        return _youtube_url(video_id) if video_id else clean
    return clean


class DiscoveryService:
    def __init__(
        self,
        musicbrainz: MusicBrainzClient,
        sources: SourceRegistry,
        source_index: SourceIndex | None = None,
    ) -> None:
        self.musicbrainz = musicbrainz
        self.sources = sources
        self.source_index = source_index

    async def discover(self, query: str, scope: SearchScope = SearchScope.all) -> DiscoverResponse:
        clean_query = query.strip()
        normalized_url = normalize_input_url(clean_query)
        if normalized_url:
            return await self._discover_url(normalized_url)
        source_response = await self._discover_structured(clean_query, scope)
        if source_response is not None:
            return source_response
        return await self._discover_metadata(clean_query, scope=scope)

    async def debug_search(self, query: str, scope: SearchScope = SearchScope.all) -> dict:
        clean_query = query.strip()
        started = time.perf_counter()
        source_hits = _index_search(self.source_index, clean_query, scope) if self.source_index else []
        index_done = time.perf_counter()
        ytmusic_items, source_warnings = await self._ytmusic_items(clean_query, scope)
        source_done = time.perf_counter()
        metadata_response = (
            await self._discover_metadata(clean_query, suppress_empty_warning=True, scope=scope)
            if not source_hits and not ytmusic_items
            else DiscoverResponse(query=clean_query, mode=SearchMode.metadata, scope=scope, items=[])
        )
        metadata_done = time.perf_counter()
        result_source = "metadata"
        if ytmusic_items:
            result_source = "ytmusic"
        elif source_hits:
            result_source = "index"
        return {
            "query": clean_query,
            "scope": scope.value,
            "result_source": result_source,
            "providers_queried": ["ytmusic"] + (["musicbrainz"] if metadata_response.items else []),
            "phase_timings_ms": {
                "index_lookup": round((index_done - started) * 1000, 2),
                "ytmusic_search": round((source_done - index_done) * 1000, 2),
                "metadata_fallback": round((metadata_done - source_done) * 1000, 2),
            },
            "source_targets": [f"ytmusic:{scope.value}:{clean_query}"],
            "source_index_hits": [entry.__dict__ for entry in source_hits],
            "source_candidates": [
                _debug_item_payload(item) for item in ytmusic_items
            ],
            "ytmusic_items": [_debug_item_payload(item) for item in ytmusic_items],
            "metadata_items": [
                item.track.model_dump(mode="json") for item in metadata_response.items if item.track
            ],
            "filtered_cached_rows": [],
            "source_warnings": [
                {"code": warning.code, "message": warning.message} for warning in source_warnings
            ],
        }

    async def discover_playable(self, query: str) -> DiscoverResponse:
        clean_query = query.strip()
        normalized_url = normalize_input_url(clean_query)
        if normalized_url:
            return await self._discover_url(normalized_url)
        if not clean_query:
            return DiscoverResponse(query=clean_query, mode=SearchMode.stream, items=[])

        track = TrackMetadata(
            id=f"playable-search:{clean_query.lower()}",
            title=clean_query,
            artists=[ArtistMetadata(name="YouTube")],
            source="query",
        )
        request = ResolveRequest(track=track, adapters=[AdapterName.ytdlp])
        candidates, warnings = await self.sources.resolve_with_warnings(request)
        candidates = [
            candidate for candidate in candidates if _is_reasonable_playable_match(clean_query, candidate)
        ]
        if not candidates and not warnings:
            warnings.append(
                DiscoverWarning(
                    code="no_stream_candidates",
                    message="No playable top match was found.",
                )
            )
        return DiscoverResponse(
            query=clean_query,
            mode=SearchMode.stream,
            scope=SearchScope.songs,
            items=[
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=track.model_copy(update={"title": candidate.title or clean_query}),
                    source=candidate,
                    label="Top playable match",
                )
                for candidate in candidates[:1]
            ],
            warnings=warnings,
        )

    async def _discover_url(self, url: str) -> DiscoverResponse:
        track = TrackMetadata(
            id=f"url:{url}",
            title=_title_from_url(url),
            artists=[ArtistMetadata(name="Stream URL")],
            source="url",
        )
        request = ResolveRequest(
            track=track,
            adapters=[AdapterName.direct_url, AdapterName.ytdlp],
            source_url=url,
        )
        candidates, warnings = await self.sources.resolve_with_warnings(request)
        if not candidates:
            warnings.append(
                DiscoverWarning(
                    code="no_stream_candidates",
                    message="No playable stream was found for that URL.",
                )
            )
        return DiscoverResponse(
            query=url,
            mode=SearchMode.url,
            scope=SearchScope.all,
            items=[
                DiscoverItem(
                    mode=SearchMode.url,
                    kind=DiscoverKind.video,
                    track=track.model_copy(update={"title": candidate.title or track.title}),
                    source=candidate,
                    label=candidate.adapter.value,
                )
                for candidate in candidates
            ],
            warnings=warnings,
        )

    async def _discover_structured(
        self, query: str, scope: SearchScope = SearchScope.all
    ) -> DiscoverResponse | None:
        if not query:
            return DiscoverResponse(query=query, mode=SearchMode.stream, scope=scope, items=[])

        index_hits = _index_search(self.source_index, query, scope) if self.source_index else []
        if index_hits and scope in {SearchScope.songs, SearchScope.videos} and index_hits[0].confidence_score >= 90:
            return _source_entries_response(query, index_hits, scope=scope)

        if not hasattr(self.sources, "ytmusic_search"):
            return None

        items, warnings = await self._ytmusic_items(query, scope)
        if items:
            if self.source_index is not None:
                self.source_index.upsert_many(_source_entries_from_discover_items(query, items))
            return DiscoverResponse(
                query=query,
                mode=SearchMode.stream,
                scope=scope,
                items=items[:DISCOVER_RESULT_LIMIT],
                warnings=[],
            )

        metadata = await self._discover_metadata(
            query,
            suppress_empty_warning=True,
            use_playable_hint=False,
            scope=scope,
        )
        if metadata.items:
            return metadata
        return DiscoverResponse(query=query, mode=SearchMode.stream, scope=scope, items=[])

    async def _ytmusic_items(
        self, query: str, scope: SearchScope = SearchScope.all
    ) -> tuple[list[DiscoverItem], list[DiscoverWarning]]:
        search = getattr(self.sources, "ytmusic_search", None)
        if search is None:
            return [], []
        try:
            return await search(query, scope=scope, limit=DISCOVER_RESULT_LIMIT), []
        except TimeoutError:
            return [], [
                DiscoverWarning(
                    code="ytmusic_timeout",
                    message="YouTube Music search timed out.",
                )
            ]
        except Exception as exc:
            detail = str(exc).strip() or f"{type(exc).__name__}: {exc!r}"
            return [], [DiscoverWarning(code="ytmusic_error", message=detail)]

    async def _source_search_entries(
        self, query: str
    ) -> tuple[list[SourceIndexEntry], list[DiscoverWarning]]:
        if not query:
            return [], []
        track = TrackMetadata(
            id=f"source-search:{query.lower()}",
            title=query,
            artists=[],
            source="query",
        )
        request = ResolveRequest(track=track, adapters=[AdapterName.ytmusic, AdapterName.ytdlp])
        source_search = getattr(self.sources, "source_search_with_warnings", None)
        if source_search is not None:
            try:
                candidates, warnings = await source_search(request, limit=DISCOVER_RESULT_LIMIT)
            except TimeoutError:
                return [], [
                    DiscoverWarning(
                        code="source_discovery_timeout",
                        message="Source discovery timed out.",
                    )
                ]
        else:
            try:
                candidates, warnings = await self.sources.resolve_with_warnings(request)
            except TimeoutError:
                return [], [
                    DiscoverWarning(
                        code="source_discovery_timeout",
                        message="Source discovery timed out.",
                    )
                ]
        return source_entries_from_candidates(query, candidates), warnings

    async def _discover_metadata(
        self,
        query: str,
        suppress_empty_warning: bool = False,
        use_playable_hint: bool = True,
        scope: SearchScope = SearchScope.all,
    ) -> DiscoverResponse:
        if not query:
            return DiscoverResponse(query=query, mode=SearchMode.metadata, scope=scope, items=[])

        warnings: list[DiscoverWarning] = []
        try:
            search_query = await self._search_query_with_playable_hint(query) if use_playable_hint else query
            tracks = await self.musicbrainz.search_tracks(search_query)
            if search_query != query:
                warnings.append(
                    DiscoverWarning(
                        code="canonical_hint",
                        message=f"Ranked using playable match hint: {search_query}",
                    )
                )
        except httpx.HTTPError:
            tracks = []
            warnings.append(
                DiscoverWarning(
                    code="metadata_unavailable",
                    message="MusicBrainz is unavailable right now. Try again in a moment.",
                )
            )
        except ValueError:
            tracks = []
            warnings.append(
                DiscoverWarning(
                    code="metadata_invalid_response",
                    message="MusicBrainz returned an unreadable response.",
                )
            )

        if not tracks and not warnings and not suppress_empty_warning:
            warnings.append(
                DiscoverWarning(
                    code="no_metadata_results",
                    message="No matching tracks were found.",
                )
            )

        return DiscoverResponse(
            query=query,
            mode=SearchMode.metadata,
            scope=scope,
            items=[
                DiscoverItem(
                    mode=SearchMode.metadata,
                    kind=DiscoverKind.metadata,
                    track=track,
                    label="MusicBrainz",
                )
                for track in tracks
            ],
            warnings=warnings,
        )

    async def _search_query_with_playable_hint(self, query: str) -> str:
        tokens = _tokens(query)
        if len(tokens) > 4:
            return query
        try:
            response = await asyncio.wait_for(self.discover_playable(query), timeout=5.0)
        except Exception:
            return query
        if not response.items:
            return query
        title = response.items[0].track.title
        hint = _query_hint_from_playable_title(title)
        return hint or query


def _title_from_url(url: str) -> str:
    parsed = urlparse(url)
    host = parsed.netloc.removeprefix("www.")
    if "youtube" in host or "youtu.be" in host:
        return "YouTube stream"
    return host or "Direct stream"


def _youtube_url(video_id: str | None) -> str | None:
    if not video_id:
        return None
    return f"https://www.youtube.com/watch?v={video_id}"


def _is_reasonable_playable_match(query: str, candidate: SourceCandidate) -> bool:
    query_tokens = _tokens(query)
    if not query_tokens:
        return False
    title_tokens = _tokens(candidate.title)
    overlap = len(query_tokens & title_tokens)
    return overlap / len(query_tokens) >= 0.6


def _tokens(value: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", value.lower()) if len(token) > 1}


def _query_hint_from_playable_title(title: str) -> str | None:
    cleaned = re.sub(r"\([^)]*\)", "", title)
    cleaned = re.sub(r"\[[^]]*]", "", cleaned)
    cleaned = re.sub(r"\bofficial\b|\baudio\b|\bvideo\b|\bmusic\b", "", cleaned, flags=re.I)
    parts = [part.strip(" -") for part in cleaned.split("-", maxsplit=1)]
    if len(parts) == 2 and all(parts):
        artist, track = parts
        return f"{track} {artist}".strip()
    return cleaned.strip() or None


def _source_entries_response(
    query: str, entries: list[SourceIndexEntry], scope: SearchScope = SearchScope.all
) -> DiscoverResponse:
    return DiscoverResponse(
        query=query,
        mode=SearchMode.stream,
        scope=scope,
        items=[
            DiscoverItem(
                mode=SearchMode.stream,
                kind=DiscoverKind.video if entry.source_kind == "video" else DiscoverKind.song,
                track=entry.to_track(),
                label=_source_label(entry),
            )
            for entry in entries[:DISCOVER_RESULT_LIMIT]
        ],
        warnings=[],
    )


def _source_label(entry: SourceIndexEntry) -> str:
    if entry.source_provider == "ytmusic":
        return "YouTube Music" if entry.source_kind == "song" else "YouTube video"
    if entry.source_provider == "youtube":
        return "YouTube video"
    return entry.source_provider


def _index_search(
    source_index: SourceIndex, query: str, scope: SearchScope
) -> list[SourceIndexEntry]:
    try:
        return source_index.search(query, scope=scope)
    except TypeError:
        return source_index.search(query)


def _source_entries_from_discover_items(
    query: str, items: list[DiscoverItem]
) -> list[SourceIndexEntry]:
    candidates: list[SourceCandidate] = []
    for item in items:
        track = item.track
        if track is None or track.source_provider != "ytmusic" or not track.source_id or not track.source_url:
            continue
        if track.source_kind not in {"song", "video"}:
            continue
        candidates.append(
            SourceCandidate(
                adapter=AdapterName.ytmusic,
                url=track.source_url,
                title=track.title,
                duration_seconds=(track.length_ms / 1000) if track.length_ms else None,
                source_provider=track.source_provider,
                source_id=track.source_id,
                source_url=track.source_url,
                source_kind=track.source_kind,
                raw_title=track.raw_title,
                canonical_title=track.canonical_title or track.title,
                canonical_artist=track.canonical_artist or track.artist_label,
                album_title=track.album.title if track.album else None,
                artwork_url=track.artwork_url,
                parse_source=track.parse_source or "structured",
            )
        )
    return source_entries_from_candidates(query, candidates)


def _debug_item_payload(item: DiscoverItem) -> dict:
    payload = {
        "kind": item.kind.value,
        "label": item.label,
    }
    if item.track is not None:
        payload.update(
            {
                "title": item.track.title,
                "artist": item.track.artist_label,
                "source_provider": item.track.source_provider,
                "source_kind": item.track.source_kind,
                "source_id": item.track.source_id,
                "raw_title": item.track.raw_title,
                "canonical_title": item.track.canonical_title,
                "canonical_artist": item.track.canonical_artist,
                "artwork_url": item.track.artwork_url,
                "rank_reason": item.track.rank_reason,
                "confidence_score": item.track.confidence_score,
            }
        )
    if item.album_result is not None:
        payload.update(item.album_result.model_dump(mode="json"))
    if item.artist_result is not None:
        payload.update(item.artist_result.model_dump(mode="json"))
    return payload
