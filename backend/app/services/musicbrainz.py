from __future__ import annotations

import asyncio
import re
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote

import httpx

from app.core.config import Settings
from app.core.db import Database
from app.schemas import AlbumMetadata, ArtistMetadata, TrackMetadata
from app.services.listenbrainz import ListenBrainzClient

_CUE_WORDS = {
    "acoustic",
    "cover",
    "covers",
    "dance",
    "instrumental",
    "karaoke",
    "live",
    "orchestra",
    "piano",
    "remix",
    "symphony",
    "tribute",
}
_SOFT_WORDS = {"a", "an", "and", "feat", "featuring", "in", "of", "the", "to"}


@dataclass(frozen=True)
class QueryVariant:
    query: str
    dismax: bool = False


class MusicBrainzClient:
    def __init__(
        self,
        settings: Settings,
        db: Database,
        listenbrainz: ListenBrainzClient | None = None,
    ) -> None:
        self.settings = settings
        self.db = db
        self.listenbrainz = listenbrainz
        self._lock = asyncio.Lock()
        self._last_request_at = 0.0

    async def search_tracks(self, query: str, limit: int = 15) -> list[TrackMetadata]:
        clean_query = query.strip()
        if not clean_query:
            return []

        cache_key = f"musicbrainz:v7:recording:{clean_query.lower()}:{limit}"
        cached = self.db.get_cache(cache_key, self.settings.metadata_cache_ttl_seconds)
        if cached is not None:
            return [TrackMetadata.model_validate(item) for item in cached]

        fetch_limit = max(limit * 4, 50)
        recordings: list[dict[str, Any]] = []
        for query_variant in _query_variants(clean_query):
            params = {
                "query": query_variant.query,
                "fmt": "json",
                "limit": str(fetch_limit),
                "inc": "artist-credits+releases+release-groups",
            }
            if query_variant.dismax:
                params["dismax"] = "true"
            payload = await self._get_json("/recording", params=params)
            recordings.extend(payload.get("recordings", []))

        tracks = [self._recording_to_track(item) for item in _dedupe_recordings(recordings)]
        tracks = [track for track in tracks if track.title and track.artists]
        tracks = await self._attach_popularity(tracks)
        tracks = self._rank_tracks(clean_query, tracks)

        serialized = [track.model_dump(mode="json") for track in tracks[:limit]]
        self.db.set_cache(cache_key, serialized)
        return tracks[:limit]

    async def _attach_popularity(self, tracks: list[TrackMetadata]) -> list[TrackMetadata]:
        if not self.listenbrainz:
            return tracks
        try:
            popularity = await self.listenbrainz.recording_popularity([track.id for track in tracks])
        except httpx.HTTPError:
            return tracks
        except ValueError:
            return tracks

        updated: list[TrackMetadata] = []
        for track in tracks:
            stats = popularity.get(track.id)
            if not stats:
                updated.append(track)
                continue
            reasons = [*track.match_reasons]
            if stats.score > 0:
                reasons.append("popular")
            updated.append(
                track.model_copy(
                    update={
                        "listen_count": stats.listen_count,
                        "listener_count": stats.listener_count,
                        "popularity_score": stats.score,
                        "match_reasons": reasons,
                    }
                )
            )
        return updated

    async def _attach_artwork(self, tracks: list[TrackMetadata]) -> list[TrackMetadata]:
        lookup_limit = max(0, self.settings.metadata_artwork_lookup_limit)
        for track in tracks[:lookup_limit]:
            album = track.album
            if not album:
                continue
            mbid = album.release_group_id or album.id
            if not mbid:
                continue
            try:
                art_url = await self._cover_art_url(mbid, release_group=bool(album.release_group_id))
            except (httpx.HTTPError, ValueError):
                art_url = None
            if art_url:
                track.album = album.model_copy(update={"artwork_url": art_url})
        return tracks

    async def _cover_art_url(self, mbid: str, release_group: bool) -> str | None:
        kind = "release-group" if release_group else "release"
        cache_key = f"cover-art:{kind}:{mbid}"
        cached = self.db.get_cache(cache_key, self.settings.metadata_cache_ttl_seconds)
        if cached is not None:
            return cached.get("artwork_url")

        url = f"{self.settings.cover_art_base_url}/{kind}/{mbid}"
        try:
            async with httpx.AsyncClient(timeout=5.0, follow_redirects=True) as client:
                response = await client.get(url, headers={"Accept": "application/json"})
        except httpx.HTTPError:
            self.db.set_cache(cache_key, {"artwork_url": None})
            return None

        if response.status_code != 200:
            self.db.set_cache(cache_key, {"artwork_url": None})
            return None

        try:
            payload = response.json()
        except ValueError:
            self.db.set_cache(cache_key, {"artwork_url": None})
            return None
        image = next((item for item in payload.get("images", []) if item.get("front")), None)
        image = image or next(iter(payload.get("images", [])), None)
        artwork_url = None
        if image:
            thumbnails = image.get("thumbnails") or {}
            artwork_url = thumbnails.get("500") or thumbnails.get("large") or image.get("image")
        self.db.set_cache(cache_key, {"artwork_url": artwork_url})
        return artwork_url

    async def _get_json(self, path: str, params: dict[str, str]) -> dict[str, Any]:
        await self._throttle()
        headers = {
            "Accept": "application/json",
            "User-Agent": self.settings.musicbrainz_user_agent,
        }
        url = f"{self.settings.musicbrainz_base_url}{path}"
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, params=params, headers=headers)
            response.raise_for_status()
            return response.json()

    async def _throttle(self) -> None:
        async with self._lock:
            elapsed = time.monotonic() - self._last_request_at
            wait_for = self.settings.musicbrainz_min_interval_seconds - elapsed
            if wait_for > 0:
                await asyncio.sleep(wait_for)
            self._last_request_at = time.monotonic()

    def _recording_to_track(self, recording: dict[str, Any]) -> TrackMetadata:
        artists = [
            ArtistMetadata(
                id=credit.get("artist", {}).get("id"),
                name=credit.get("artist", {}).get("name", ""),
            )
            for credit in recording.get("artist-credit", [])
            if credit.get("artist", {}).get("name")
        ]
        releases = recording.get("releases") or []
        release = _best_release(releases)
        release_group = release.get("release-group") or {}
        album = None
        if release or release_group:
            album = AlbumMetadata(
                id=release.get("id"),
                title=release.get("title"),
                release_group_id=release_group.get("id"),
            )
        return TrackMetadata(
            id=recording.get("id") or quote(recording.get("title", "")),
            title=recording.get("title", ""),
            artists=artists,
            album=album,
            length_ms=recording.get("length"),
            score=recording.get("score"),
            release_count=len(releases),
        )

    def _rank_tracks(self, query: str, tracks: list[TrackMetadata]) -> list[TrackMetadata]:
        query_tokens = _tokens(query)
        query_core_tokens = _core_tokens(query)
        query_cues = query_tokens & _CUE_WORDS

        def rank(track: TrackMetadata) -> tuple[float, str]:
            title_tokens = _tokens(track.title)
            title_core_tokens = _core_tokens(track.title)
            artist_tokens = _tokens(track.artist_label)
            token_overlap = len(query_tokens & (title_tokens | artist_tokens))
            title_overlap = len(query_tokens & title_tokens)
            artist_overlap = len(query_tokens & artist_tokens)
            score = float(track.score or 0)
            album_title = track.album.title if track.album else ""
            combined_tokens = title_tokens | artist_tokens | _tokens(album_title or "")
            cue_overlap = combined_tokens & _CUE_WORDS
            reasons = [*track.match_reasons]
            title_match_ratio = (
                len(query_core_tokens & title_core_tokens) / len(query_core_tokens)
                if query_core_tokens
                else 0.0
            )
            strong_match = title_match_ratio >= 0.75 or bool(artist_overlap)
            popularity_boost = min(float(track.popularity_score or 0) / 1000, 35)
            score += popularity_boost if strong_match else min(popularity_boost, 4)

            if query_tokens and query_tokens <= title_tokens:
                score += 80
                reasons.append("title")
            if query_tokens and query_tokens <= (title_tokens | artist_tokens):
                score += 25
            if query_core_tokens and query_core_tokens == title_core_tokens:
                score += 70
                reasons.append("exact-title")
            elif query_core_tokens & title_core_tokens:
                reasons.append("fuzzy")
            score += token_overlap * 8
            score += title_overlap * 10
            if artist_overlap:
                score += artist_overlap * 85
                reasons.append("artist")
            if query_core_tokens and title_match_ratio < 0.5:
                score -= 80

            stripped_title_tokens = _core_tokens(_strip_parenthetical(track.title))
            if stripped_title_tokens == (query_core_tokens - artist_tokens):
                score += 24

            if track.length_ms is not None:
                duration_seconds = track.length_ms / 1000
                if duration_seconds < 45:
                    score -= 35
                elif 120 <= duration_seconds <= 420:
                    score += 18
                elif 90 <= duration_seconds <= 540:
                    score += 8

            if track.album and track.album.title:
                score += 5
                if _normalize_text(track.album.title) == _normalize_text(track.title):
                    score += 16

            if track.release_count:
                score += min(track.release_count, 12) * 4

            if cue_overlap - query_cues:
                score -= 45 + (len(cue_overlap - query_cues) * 10)
                reasons.append("cover-like")

            track.match_reasons = _dedupe_strings(reasons)

            return (-score, track.title.lower())

        return sorted(tracks, key=rank)


def _tokens(value: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", value.lower()) if len(token) > 1}


def _core_tokens(value: str) -> set[str]:
    return _tokens(value) - _SOFT_WORDS


def _normalize_text(value: str) -> str:
    return " ".join(sorted(_core_tokens(_strip_parenthetical(value))))


def _strip_parenthetical(value: str) -> str:
    return re.sub(r"\([^)]*\)", "", value).strip()


def _query_variants(query: str) -> list[QueryVariant]:
    variants = [QueryVariant(query, dismax=True)]
    words = query.split()
    if len(words) >= 3 and words[-1].lower() not in _SOFT_WORDS:
        title = " ".join(words[:-1])
        artist = words[-1]
        variants.append(QueryVariant(f'recording:"{title}" AND artist:"{artist}"'))
    fuzzy_terms = [token for token in _core_tokens(query) if len(token) > 3]
    if fuzzy_terms:
        variants.append(QueryVariant(" AND ".join(f"recording:{token}~" for token in fuzzy_terms)))
    return variants


def _dedupe_recordings(recordings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    deduped: list[dict[str, Any]] = []
    for recording in recordings:
        recording_id = recording.get("id")
        if not recording_id or recording_id in seen:
            continue
        seen.add(recording_id)
        deduped.append(recording)
    return deduped


def _dedupe_strings(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def _best_release(releases: list[dict[str, Any]]) -> dict[str, Any]:
    if not releases:
        return {}

    def rank(release: dict[str, Any]) -> tuple[int, str]:
        release_group = release.get("release-group") or {}
        title = release.get("title") or ""
        text = f"{title} {release_group.get('title', '')}"
        score = 0
        if release.get("status") == "Official":
            score += 8
        if release_group.get("primary-type") in {"Album", "Single", "EP"}:
            score += 6
        if not (_tokens(text) & _CUE_WORDS):
            score += 4
        date = release.get("date") or "9999"
        return (-score, date)

    return sorted(releases, key=rank)[0]
