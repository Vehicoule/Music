from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, Field, HttpUrl


class AdapterName(str, Enum):
    ytmusic = "ytmusic"
    ytdlp = "yt_dlp"
    direct_url = "direct_url"
    internet_radio = "internet_radio"


class SearchMode(str, Enum):
    metadata = "metadata"
    url = "url"
    stream = "stream"


class SearchScope(str, Enum):
    all = "all"
    songs = "songs"
    albums = "albums"
    artists = "artists"
    videos = "videos"


class DiscoverKind(str, Enum):
    song = "song"
    video = "video"
    album = "album"
    artist = "artist"
    metadata = "metadata"


class ArtistMetadata(BaseModel):
    id: str | None = None
    name: str


class AlbumMetadata(BaseModel):
    id: str | None = None
    title: str | None = None
    release_group_id: str | None = None
    artwork_url: str | None = None


class TrackMetadata(BaseModel):
    id: str
    title: str
    artists: list[ArtistMetadata] = Field(default_factory=list)
    album: AlbumMetadata | None = None
    length_ms: int | None = None
    score: int | None = None
    release_count: int | None = None
    listen_count: int | None = None
    listener_count: int | None = None
    popularity_score: float | None = None
    confidence_score: float | None = None
    rank_reason: str | None = None
    artwork_url: str | None = None
    source_provider: str | None = None
    source_id: str | None = None
    source_url: str | None = None
    source_kind: str | None = None
    raw_title: str | None = None
    canonical_title: str | None = None
    canonical_artist: str | None = None
    parse_source: str | None = None
    match_reasons: list[str] = Field(default_factory=list)
    source: str = "musicbrainz"

    @property
    def artist_label(self) -> str:
        return ", ".join(artist.name for artist in self.artists)


class SourceCandidate(BaseModel):
    adapter: AdapterName
    url: str
    title: str
    mime_type: str | None = None
    duration_seconds: float | None = None
    source_provider: str | None = None
    source_id: str | None = None
    source_url: str | None = None
    source_kind: str | None = None
    raw_title: str | None = None
    canonical_title: str | None = None
    canonical_artist: str | None = None
    album_title: str | None = None
    artwork_url: str | None = None
    parse_source: str | None = None
    confidence_score: float | None = None
    rank_reason: str | None = None
    is_live: bool = False
    expires_at: datetime | None = None
    headers: dict[str, str] = Field(default_factory=dict)


class PlaybackItem(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    track: TrackMetadata
    source: SourceCandidate | None = None
    added_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class Playlist(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: str
    description: str = ""
    tracks: list[PlaybackItem] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class Favorite(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    item: PlaybackItem
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AdapterCapability(BaseModel):
    name: AdapterName
    enabled: bool
    healthy: bool
    label: str
    supports_search: bool = False
    supports_direct_url: bool = False
    supports_live_stream: bool = False
    notes: str | None = None


class SearchResponse(BaseModel):
    query: str
    tracks: list[TrackMetadata]


class DiscoverWarning(BaseModel):
    code: str
    message: str


class AlbumSearchResult(BaseModel):
    title: str
    artists: list[ArtistMetadata] = Field(default_factory=list)
    browse_id: str | None = None
    playlist_id: str | None = None
    year: str | None = None
    artwork_url: str | None = None

    @property
    def artist_label(self) -> str:
        return ", ".join(artist.name for artist in self.artists)


class ArtistSearchResult(BaseModel):
    name: str
    browse_id: str | None = None
    channel_id: str | None = None
    artwork_url: str | None = None


class DiscoverItem(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    mode: SearchMode
    kind: DiscoverKind = DiscoverKind.metadata
    track: TrackMetadata | None = None
    album_result: AlbumSearchResult | None = None
    artist_result: ArtistSearchResult | None = None
    source: SourceCandidate | None = None
    label: str | None = None


class DiscoverResponse(BaseModel):
    query: str
    mode: SearchMode
    scope: SearchScope = SearchScope.all
    items: list[DiscoverItem]
    warnings: list[DiscoverWarning] = Field(default_factory=list)


class DetailSection(BaseModel):
    label: str
    items: list[DiscoverItem] = Field(default_factory=list)


class AlbumDetail(BaseModel):
    title: str
    artists: list[ArtistMetadata] = Field(default_factory=list)
    browse_id: str | None = None
    playlist_id: str | None = None
    year: str | None = None
    artwork_url: str | None = None
    tracks: list[DiscoverItem] = Field(default_factory=list)

    @property
    def artist_label(self) -> str:
        return ", ".join(artist.name for artist in self.artists)


class ArtistDetail(BaseModel):
    name: str
    browse_id: str | None = None
    channel_id: str | None = None
    artwork_url: str | None = None
    sections: list[DetailSection] = Field(default_factory=list)


class ResolveRequest(BaseModel):
    track: TrackMetadata
    adapters: list[AdapterName] = Field(default_factory=list)
    source_url: HttpUrl | None = None


class ResolveResponse(BaseModel):
    track: TrackMetadata
    candidates: list[SourceCandidate]
    warnings: list[DiscoverWarning] = Field(default_factory=list)


class ResolverDebugAttempt(BaseModel):
    adapter: AdapterName
    target: str
    candidate_count: int = 0
    first_title: str | None = None
    first_url_host: str | None = None
    first_duration_seconds: float | None = None
    headers_present: bool = False
    warning: str | None = None


class ResolverDebugResponse(BaseModel):
    track: TrackMetadata
    attempts: list[ResolverDebugAttempt] = Field(default_factory=list)


class PlaylistCreate(BaseModel):
    name: str
    description: str = ""
    tracks: list[PlaybackItem] = Field(default_factory=list)


class PlaylistUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    tracks: list[PlaybackItem] | None = None


class FavoriteCreate(BaseModel):
    item: PlaybackItem


class HistoryCreate(BaseModel):
    item: PlaybackItem


JsonDict = dict[str, Any]
