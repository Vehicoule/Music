from __future__ import annotations

import asyncio
import hashlib
from typing import Any

from app.core.config import Settings
from app.core.db import Database
from app.schemas import (
    AdapterCapability,
    AdapterName,
    AlbumDetail,
    AlbumSearchResult,
    AlbumMetadata,
    ArtistDetail,
    ArtistMetadata,
    ArtistSearchResult,
    DetailSection,
    DiscoverItem,
    DiscoverKind,
    ResolveRequest,
    SearchMode,
    SearchScope,
    SourceCandidate,
    TrackMetadata,
)
from app.sources.base import SourceAdapter


class YtMusicAdapter(SourceAdapter):
    def __init__(
        self,
        settings: Settings,
        client: Any | None = None,
        db: Database | None = None,
    ) -> None:
        self.settings = settings
        self._client = client
        self.db = db
        self.last_warning: str | None = None

    async def capability(self) -> AdapterCapability:
        healthy = self._client is not None or _ytmusic_class() is not None
        return AdapterCapability(
            name=AdapterName.ytmusic,
            enabled=self.settings.enable_ytmusic,
            healthy=healthy,
            label="YouTube Music",
            supports_search=True,
            supports_direct_url=False,
            notes="Searches structured YouTube Music song metadata for source references.",
        )

    async def resolve(self, _request: ResolveRequest) -> list[SourceCandidate]:
        return []

    async def search(
        self, query: str, scope: SearchScope = SearchScope.all, limit: int = 12
    ) -> list[DiscoverItem]:
        self.last_warning = None
        if not self.settings.enable_ytmusic:
            return []
        client = self._get_client()
        if client is None:
            self.last_warning = "ytmusicapi is not available in the backend environment."
            return []
        clean_query = query.strip()
        if not clean_query:
            return []

        cached = self._cached_payload(_search_cache_key(clean_query, scope, limit))
        if cached is not None:
            return [DiscoverItem.model_validate(item) for item in cached]

        filters = _filters_for_scope(scope)
        raw_groups = await asyncio.gather(
            *[
                asyncio.to_thread(
                    _client_search,
                    client,
                    clean_query,
                    filter_name,
                    limit,
                )
                for filter_name in filters
            ]
        )
        items: list[DiscoverItem] = []
        for filter_name, raw_items in zip(filters, raw_groups, strict=True):
            items.extend(_raw_items_to_discover_items(raw_items, filter_name))
        deduped = _dedupe_discover_items(items)[:limit]
        self._set_cached_payload(
            _search_cache_key(clean_query, scope, limit),
            [item.model_dump(mode="json") for item in deduped],
        )
        return deduped

    async def album_detail(self, browse_id: str) -> AlbumDetail:
        self.last_warning = None
        client = self._get_client()
        if client is None:
            self.last_warning = "ytmusicapi is not available in the backend environment."
            return AlbumDetail(title="")
        cache_key = _detail_cache_key("album", browse_id)
        cached = self._cached_payload(cache_key)
        if cached is not None:
            return AlbumDetail.model_validate(cached)
        payload = await asyncio.to_thread(client.get_album, browse_id)
        detail = _album_payload_to_detail(payload, browse_id)
        self._set_cached_payload(cache_key, detail.model_dump(mode="json"))
        return detail

    async def artist_detail(self, browse_id: str) -> ArtistDetail:
        self.last_warning = None
        client = self._get_client()
        if client is None:
            self.last_warning = "ytmusicapi is not available in the backend environment."
            return ArtistDetail(name="")
        cache_key = _detail_cache_key("artist", browse_id)
        cached = self._cached_payload(cache_key)
        if cached is not None:
            return ArtistDetail.model_validate(cached)
        payload = await asyncio.to_thread(client.get_artist, browse_id)
        detail = _artist_payload_to_detail(payload, browse_id)
        self._set_cached_payload(cache_key, detail.model_dump(mode="json"))
        return detail

    async def source_search(
        self, request: ResolveRequest, limit: int = 12
    ) -> list[SourceCandidate]:
        self.last_warning = None
        if not self.settings.enable_ytmusic:
            return []
        client = self._get_client()
        if client is None:
            self.last_warning = "ytmusicapi is not available in the backend environment."
            return []

        query = request.track.title.strip()
        if not query:
            return []

        songs = await asyncio.to_thread(_client_search, client, query, "songs", limit)
        videos = await asyncio.to_thread(_client_search, client, query, "videos", limit)
        candidates = [
            *_items_to_candidates(songs, source_kind="song"),
            *_items_to_candidates(videos, source_kind="video"),
        ]
        return _dedupe_candidates(candidates)[:limit]

    def _get_client(self) -> Any | None:
        if self._client is not None:
            return self._client
        client_class = _ytmusic_class()
        if client_class is None:
            return None
        self._client = client_class()
        return self._client

    def _cached_payload(self, cache_key: str) -> Any | None:
        if self.db is None:
            return None
        return self.db.get_cache(cache_key, self.settings.ytmusic_cache_ttl_seconds)

    def _set_cached_payload(self, cache_key: str, payload: Any) -> None:
        if self.db is None:
            return
        self.db.set_cache(cache_key, payload)


def _ytmusic_class() -> Any | None:
    try:
        from ytmusicapi import YTMusic
    except ImportError:
        return None
    return YTMusic


def _client_search(
    client: Any, query: str, filter_name: str, limit: int
) -> list[dict[str, Any]]:
    return client.search(query, filter=filter_name, limit=limit)


def _search_cache_key(query: str, scope: SearchScope, limit: int) -> str:
    digest = hashlib.sha256(
        f"{scope.value}:{limit}:{query.lower()}".encode("utf-8")
    ).hexdigest()
    return f"ytmusic:search:v1:{digest}"


def _detail_cache_key(kind: str, browse_id: str) -> str:
    digest = hashlib.sha256(browse_id.encode("utf-8")).hexdigest()
    return f"ytmusic:{kind}:v1:{digest}"


def _filters_for_scope(scope: SearchScope) -> list[str]:
    match scope:
        case SearchScope.songs:
            return ["songs"]
        case SearchScope.albums:
            return ["albums"]
        case SearchScope.artists:
            return ["artists"]
        case SearchScope.videos:
            return ["videos"]
        case _:
            return ["songs", "albums", "artists", "videos"]


def _raw_items_to_discover_items(
    items: list[dict[str, Any]], filter_name: str
) -> list[DiscoverItem]:
    parsed: list[DiscoverItem] = []
    for item in items:
        discover_item = _raw_item_to_discover_item(item, filter_name)
        if discover_item is not None:
            parsed.append(discover_item)
    return parsed


def _raw_item_to_discover_item(item: dict[str, Any], filter_name: str) -> DiscoverItem | None:
    if filter_name in {"songs", "videos"}:
        candidate = _item_to_candidate(
            item,
            source_kind="song" if filter_name == "songs" else "video",
        )
        if candidate is None:
            return None
        return _candidate_to_discover_item(candidate)
    if filter_name == "albums":
        return _album_item_to_discover_item(item)
    if filter_name == "artists":
        return _artist_item_to_discover_item(item)
    return None


def _candidate_to_discover_item(candidate: SourceCandidate) -> DiscoverItem:
    track = TrackMetadata(
        id=f"ytmusic:{candidate.source_id}",
        title=candidate.canonical_title or candidate.title,
        artists=[
            ArtistMetadata(name=name.strip())
            for name in (candidate.canonical_artist or "").split(",")
            if name.strip()
        ],
        album=AlbumMetadata(title=candidate.album_title) if candidate.album_title else None,
        length_ms=int(candidate.duration_seconds * 1000) if candidate.duration_seconds else None,
        artwork_url=candidate.artwork_url,
        source_provider=candidate.source_provider,
        source_id=candidate.source_id,
        source_url=candidate.source_url,
        source_kind=candidate.source_kind,
        raw_title=candidate.raw_title,
        canonical_title=candidate.canonical_title,
        canonical_artist=candidate.canonical_artist,
        parse_source=candidate.parse_source,
        source="ytmusic",
    )
    return DiscoverItem(
        mode=SearchMode.stream,
        kind=DiscoverKind.video if candidate.source_kind == "video" else DiscoverKind.song,
        track=track,
        label="YouTube Music" if candidate.source_kind == "song" else "YouTube video",
    )


def _album_payload_to_detail(payload: dict[str, Any], browse_id: str) -> AlbumDetail:
    artists = _artists_from_item(payload)
    artwork_url = _thumbnail_url(payload.get("thumbnails") or payload.get("thumbnail"))
    album_title = payload.get("title") or payload.get("name") or ""
    tracks: list[DiscoverItem] = []
    for item in payload.get("tracks") or []:
        if not isinstance(item, dict):
            continue
        track_item = dict(item)
        if not track_item.get("artists") and artists:
            track_item["artists"] = [artist.model_dump(mode="json") for artist in artists]
        if not track_item.get("album"):
            track_item["album"] = {"name": album_title, "id": browse_id}
        if not track_item.get("thumbnails") and artwork_url:
            track_item["thumbnails"] = [{"url": artwork_url}]
        candidate = _item_to_candidate(track_item, source_kind="song")
        if candidate is not None:
            tracks.append(_candidate_to_discover_item(candidate))

    return AlbumDetail(
        title=album_title,
        artists=artists,
        browse_id=browse_id,
        playlist_id=payload.get("audioPlaylistId") or payload.get("playlistId"),
        year=str(payload.get("year")) if payload.get("year") is not None else None,
        artwork_url=artwork_url,
        tracks=tracks,
    )


def _artist_payload_to_detail(payload: dict[str, Any], browse_id: str) -> ArtistDetail:
    artwork_url = _thumbnail_url(payload.get("thumbnails") or payload.get("thumbnail"))
    sections: list[DetailSection] = []
    for label, key, filter_name in [
        ("Top songs", "songs", "songs"),
        ("Albums", "albums", "albums"),
        ("Videos", "videos", "videos"),
    ]:
        section_payload = payload.get(key)
        if not isinstance(section_payload, dict):
            continue
        raw_items = section_payload.get("results") or []
        if not isinstance(raw_items, list):
            continue
        items = _raw_items_to_discover_items(raw_items, filter_name)
        if items:
            sections.append(DetailSection(label=label, items=items))

    return ArtistDetail(
        name=payload.get("name") or payload.get("artist") or "",
        browse_id=browse_id,
        channel_id=payload.get("channelId"),
        artwork_url=artwork_url,
        sections=sections,
    )


def _album_item_to_discover_item(item: dict[str, Any]) -> DiscoverItem | None:
    title = item.get("title") or item.get("name")
    browse_id = item.get("browseId")
    if not title or not browse_id:
        return None
    result = AlbumSearchResult(
        title=title,
        artists=_artists_from_item(item),
        browse_id=browse_id,
        playlist_id=item.get("playlistId"),
        year=str(item.get("year")) if item.get("year") is not None else None,
        artwork_url=_thumbnail_url(item.get("thumbnails") or item.get("thumbnail")),
    )
    return DiscoverItem(
        mode=SearchMode.stream,
        kind=DiscoverKind.album,
        album_result=result,
        label="YouTube Music",
    )


def _artist_item_to_discover_item(item: dict[str, Any]) -> DiscoverItem | None:
    name = item.get("artist") or item.get("title") or item.get("name")
    browse_id = item.get("browseId")
    if not name or not browse_id:
        return None
    result = ArtistSearchResult(
        name=name,
        browse_id=browse_id,
        channel_id=item.get("channelId"),
        artwork_url=_thumbnail_url(item.get("thumbnails") or item.get("thumbnail")),
    )
    return DiscoverItem(
        mode=SearchMode.stream,
        kind=DiscoverKind.artist,
        artist_result=result,
        label="YouTube Music",
    )


def _artists_from_item(item: dict[str, Any]) -> list[ArtistMetadata]:
    artists = item.get("artists")
    if not isinstance(artists, list):
        return []
    return [
        ArtistMetadata(id=artist.get("id"), name=artist.get("name", "").strip())
        for artist in artists
        if isinstance(artist, dict) and artist.get("name", "").strip()
    ]


def _dedupe_discover_items(items: list[DiscoverItem]) -> list[DiscoverItem]:
    deduped: list[DiscoverItem] = []
    seen: set[str] = set()
    for item in items:
        if item.track is not None:
            key = f"{item.kind}:{item.track.source_id or item.track.id}"
        elif item.album_result is not None:
            key = f"album:{item.album_result.browse_id or item.album_result.title}"
        elif item.artist_result is not None:
            key = f"artist:{item.artist_result.browse_id or item.artist_result.name}"
        else:
            key = item.id
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def _items_to_candidates(items: list[dict[str, Any]], source_kind: str) -> list[SourceCandidate]:
    candidates: list[SourceCandidate] = []
    for item in items:
        candidate = _item_to_candidate(item, source_kind=source_kind)
        if candidate is not None:
            candidates.append(candidate)
    return candidates


def _dedupe_candidates(candidates: list[SourceCandidate]) -> list[SourceCandidate]:
    deduped: list[SourceCandidate] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = candidate.source_id or candidate.source_url or candidate.url
        if key in seen:
            continue
        seen.add(key)
        deduped.append(candidate)
    return deduped


def _item_to_candidate(item: dict[str, Any], source_kind: str) -> SourceCandidate | None:
    video_id = item.get("videoId")
    title = item.get("title")
    if not video_id or not title:
        return None

    source_url = f"https://music.youtube.com/watch?v={video_id}"
    artists = [
        artist.get("name", "").strip()
        for artist in item.get("artists", [])
        if isinstance(artist, dict) and artist.get("name", "").strip()
    ]
    album = item.get("album") if isinstance(item.get("album"), dict) else None
    album_title = album.get("name") if album else None
    duration = _duration_seconds(item)
    artwork_url = _thumbnail_url(item.get("thumbnails") or item.get("thumbnail"))
    canonical_artist = ", ".join(artists)

    return SourceCandidate(
        adapter=AdapterName.ytmusic,
        url=source_url,
        title=title,
        duration_seconds=duration,
        source_provider="ytmusic",
        source_id=video_id,
        source_url=source_url,
        source_kind=source_kind,
        raw_title=item.get("title"),
        canonical_title=title,
        canonical_artist=canonical_artist,
        album_title=album_title,
        artwork_url=artwork_url,
        parse_source="structured",
    )


def _duration_seconds(item: dict[str, Any]) -> float | None:
    value = item.get("duration_seconds")
    if value is not None:
        return float(value)
    text = item.get("duration")
    if not isinstance(text, str) or not text:
        return None
    parts = [part for part in text.split(":") if part.isdigit()]
    if not parts:
        return None
    seconds = 0
    for part in parts:
        seconds = seconds * 60 + int(part)
    return float(seconds)


def _thumbnail_url(value: Any) -> str | None:
    if isinstance(value, str):
        return value
    if not isinstance(value, list) or not value:
        return None
    thumbnails = [item for item in value if isinstance(item, dict) and item.get("url")]
    if not thumbnails:
        return None
    best = max(
        thumbnails,
        key=lambda item: (item.get("width") or 0) * (item.get("height") or 0),
    )
    return best["url"]
