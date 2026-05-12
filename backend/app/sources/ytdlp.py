from __future__ import annotations

import asyncio
import hashlib
import json
import shutil
import subprocess
import time
from typing import Any
from urllib.parse import urlparse

from app.core.config import Settings
from app.core.db import Database
from app.schemas import (
    AdapterCapability,
    AdapterName,
    ResolveRequest,
    ResolverDebugAttempt,
    SourceCandidate,
)
from app.sources.base import SourceAdapter


class YtDlpAdapter(SourceAdapter):
    def __init__(self, settings: Settings, db: Database | None = None) -> None:
        self.settings = settings
        self.db = db
        self.last_warning: str | None = None

    async def capability(self) -> AdapterCapability:
        launch_mode = self._launch_mode()
        binary_found = launch_mode is not None
        return AdapterCapability(
            name=AdapterName.ytdlp,
            enabled=self.settings.enable_ytdlp,
            healthy=binary_found,
            label="yt-dlp resolver",
            supports_search=True,
            supports_direct_url=True,
            notes=(
                "Resolves playable URLs through the yt-dlp python module."
                if launch_mode == "python_module"
                else "Resolves playable URLs without downloading or rehosting content."
            ),
        )

    async def resolve(self, request: ResolveRequest) -> list[SourceCandidate]:
        self.last_warning = None
        capability = await self.capability()
        if not capability.enabled or not capability.healthy:
            self.last_warning = "yt-dlp is not available in the backend environment."
            return []

        candidates: list[SourceCandidate] = []
        warnings: list[str] = []
        for target in self._targets(request):
            cached = self._cached_candidates(target)
            if cached:
                candidates.extend(cached)
                break

            target_candidates, warning = await self._resolve_target(target, request)
            if target_candidates:
                self._cache_candidates(target, target_candidates)
                candidates.extend(target_candidates)
                break
            if warning:
                warnings.append(warning)

        if warnings and not candidates:
            self.last_warning = "\n".join(warnings)
        return candidates[:3]

    async def source_search(
        self, request: ResolveRequest, limit: int = 12
    ) -> list[SourceCandidate]:
        self.last_warning = None
        capability = await self.capability()
        if not capability.enabled or not capability.healthy:
            self.last_warning = "yt-dlp is not available in the backend environment."
            return []

        candidates: list[SourceCandidate] = []
        warnings: list[str] = []
        seen: set[str] = set()
        deadline = time.monotonic() + self.settings.ytdlp_discovery_timeout_seconds
        for target in self._source_search_targets(request, limit=limit):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                warnings.append("yt-dlp source discovery timed out.")
                break
            target_candidates, warning = await self._resolve_source_target(
                target,
                request,
                timeout=remaining,
            )
            for candidate in target_candidates:
                key = candidate.source_id or candidate.source_url or candidate.url
                if key in seen:
                    continue
                seen.add(key)
                candidates.append(candidate)
            if warning:
                warnings.append(warning)

        if warnings and not candidates:
            self.last_warning = "\n".join(warnings)
        candidates.sort(key=lambda candidate: _candidate_rank(candidate, request), reverse=True)
        return candidates[:limit]

    async def _resolve_source_target(
        self,
        target: str,
        request: ResolveRequest,
        timeout: float | None = None,
    ) -> tuple[list[SourceCandidate], str | None]:
        command = [
            *self._command_prefix(),
            "--dump-single-json",
            "--flat-playlist",
            "--no-download",
            target,
        ]
        try:
            process = await asyncio.to_thread(
                subprocess.run,
                command,
                capture_output=True,
                timeout=max(0.5, timeout or self.settings.ytdlp_discovery_timeout_seconds),
                check=False,
            )
        except (subprocess.TimeoutExpired, OSError):
            return [], "yt-dlp source discovery timed out or could not be started."

        if process.returncode != 0 or not process.stdout:
            detail = _friendly_ytdlp_detail(
                process.stderr.decode("utf-8", errors="replace").strip()
            )
            return [], detail or "yt-dlp source discovery did not return results."

        try:
            payload = json.loads(process.stdout.decode("utf-8"))
        except json.JSONDecodeError:
            return [], "yt-dlp source discovery returned an unreadable response."

        candidates = self._payload_to_source_candidates(payload, request)
        if not candidates:
            return [], "yt-dlp source discovery returned no source results."
        return candidates, None

    async def resolve_debug(self, request: ResolveRequest) -> list[ResolverDebugAttempt]:
        capability = await self.capability()
        if not capability.enabled or not capability.healthy:
            return [
                ResolverDebugAttempt(
                    adapter=AdapterName.ytdlp,
                    target="",
                    warning="yt-dlp is not available in the backend environment.",
                )
            ]

        attempts: list[ResolverDebugAttempt] = []
        for target in self._targets(request):
            candidates, warning = await self._resolve_target(target, request)
            first = candidates[0] if candidates else None
            host = urlparse(first.url).netloc if first else None
            attempts.append(
                ResolverDebugAttempt(
                    adapter=AdapterName.ytdlp,
                    target=target,
                    candidate_count=len(candidates),
                    first_title=first.title if first else None,
                    first_url_host=host,
                    first_duration_seconds=first.duration_seconds if first else None,
                    headers_present=bool(first.headers) if first else False,
                    warning=warning,
                )
            )
            if candidates:
                break
        return attempts

    async def _resolve_target(
        self,
        target: str,
        request: ResolveRequest,
    ) -> tuple[list[SourceCandidate], str | None]:
        command = [
            *self._command_prefix(),
            "--dump-single-json",
            "--no-playlist",
            "--no-download",
            "--format",
            "bestaudio/best",
            target,
        ]
        try:
            process = await asyncio.to_thread(
                subprocess.run,
                command,
                capture_output=True,
                timeout=self.settings.ytdlp_timeout_seconds,
                check=False,
            )
        except (subprocess.TimeoutExpired, OSError):
            return [], "yt-dlp timed out or could not be started."

        if process.returncode != 0 or not process.stdout:
            detail = _friendly_ytdlp_detail(
                process.stderr.decode("utf-8", errors="replace").strip()
            )
            return [], detail or "yt-dlp did not return a playable result."

        try:
            payload = json.loads(process.stdout.decode("utf-8"))
        except json.JSONDecodeError:
            return [], "yt-dlp returned an unreadable response."

        candidates = self._payload_to_candidates(payload, request)
        if not candidates:
            return [], "yt-dlp returned metadata but no audio stream URL."
        return candidates, None

    def _launch_mode(self) -> str | None:
        if self.settings.ytdlp_python:
            return "python_module"
        if shutil.which(self.settings.ytdlp_binary) is not None:
            return "binary"
        return None

    def _command_prefix(self) -> list[str]:
        if self.settings.ytdlp_python:
            return [self.settings.ytdlp_python, "-m", "yt_dlp"]
        return [self.settings.ytdlp_binary]

    def _targets(self, request: ResolveRequest) -> list[str]:
        if request.source_url:
            return [str(request.source_url)]

        artist = request.track.artist_label
        title = request.track.title.strip()
        targets: list[str] = []
        if artist and artist != "Unknown artist":
            targets.append(f'ytsearch3:"{title}" "{artist}" official audio')
            targets.append(f'ytsearch2:"{artist}" - "{title}"')
        targets.append(f'ytsearch3:"{title}" official audio')
        targets.append(f'ytsearch2:"{title}"')
        return _dedupe(targets)

    def _source_search_targets(self, request: ResolveRequest, limit: int = 12) -> list[str]:
        query = request.track.title.strip()
        if not query:
            return []
        targets = [
            f"ytsearch{limit}:{query}",
            f'ytsearch{min(limit, 8)}:"{query}" official audio',
        ]
        inferred = _infer_query_title_artist(query)
        if inferred:
            title, artist = inferred
            targets.extend(
                [
                    f'ytsearch{min(limit, 8)}:"{artist}" "{title}" official audio',
                    f"ytsearch{min(limit, 8)}:{artist} - {title}",
                ]
            )
        return _dedupe(targets)

    def _payload_to_candidates(
        self,
        payload: dict[str, Any],
        request: ResolveRequest | None = None,
    ) -> list[SourceCandidate]:
        entries = payload.get("entries")
        payloads = [item for item in entries if isinstance(item, dict)] if entries else [payload]
        candidates = [
            candidate
            for candidate in (self._payload_to_candidate(item) for item in payloads)
            if candidate is not None
        ]
        if request is not None:
            candidates.sort(key=lambda candidate: _candidate_rank(candidate, request), reverse=True)
        return candidates

    def _payload_to_source_candidates(
        self,
        payload: dict[str, Any],
        request: ResolveRequest | None = None,
    ) -> list[SourceCandidate]:
        entries = payload.get("entries")
        payloads = [item for item in entries if isinstance(item, dict)] if entries else [payload]
        candidates = [
            candidate
            for candidate in (self._payload_to_source_candidate(item) for item in payloads)
            if candidate is not None
        ]
        if request is not None:
            candidates.sort(key=lambda candidate: _candidate_rank(candidate, request), reverse=True)
        return candidates

    def _payload_to_source_candidate(self, payload: dict[str, Any]) -> SourceCandidate | None:
        source_id = payload.get("id")
        source_url = payload.get("webpage_url") or payload.get("original_url")
        if not source_url:
            source_url = _youtube_watch_url(source_id or payload.get("url"))
        if not source_url:
            return None

        duration = payload.get("duration")
        return SourceCandidate(
            adapter=AdapterName.ytdlp,
            url=source_url,
            title=payload.get("title") or "YouTube result",
            duration_seconds=float(duration) if duration else None,
            source_provider="youtube",
            source_id=source_id,
            source_url=source_url,
            source_kind="video",
            raw_title=payload.get("title"),
            artwork_url=_thumbnail_url(payload.get("thumbnails") or payload.get("thumbnail")),
            parse_source="parsed_title",
        )

    def _payload_to_candidate(self, payload: dict[str, Any]) -> SourceCandidate | None:
        selected = self._selected_format(payload)
        direct_url = selected.get("url")
        if not direct_url:
            return None

        duration = payload.get("duration")
        return SourceCandidate(
            adapter=AdapterName.ytdlp,
            url=direct_url,
            title=payload.get("title") or "Resolved stream",
            mime_type=selected.get("mime_type") or selected.get("audio_ext") or selected.get("ext"),
            duration_seconds=float(duration) if duration else None,
            source_provider="youtube",
            source_id=payload.get("id"),
            source_url=payload.get("webpage_url") or payload.get("original_url"),
            is_live=bool(payload.get("is_live")),
            headers=selected.get("http_headers") or payload.get("http_headers") or {},
        )

    def _selected_format(self, payload: dict[str, Any]) -> dict[str, Any]:
        requested_downloads = payload.get("requested_downloads") or []
        if requested_downloads and requested_downloads[0].get("url"):
            return requested_downloads[0]
        if payload.get("url"):
            return payload

        formats = payload.get("formats") or []
        audio_formats = [
            item
            for item in formats
            if item.get("url") and (item.get("acodec") not in {None, "none"})
        ]
        audio_formats.sort(key=lambda item: item.get("abr") or item.get("tbr") or 0, reverse=True)
        return audio_formats[0] if audio_formats else {}

    def _cached_candidates(self, target: str) -> list[SourceCandidate]:
        if self.db is None:
            return []
        cached = self.db.get_cache(_cache_key(target), self.settings.source_match_cache_ttl_seconds)
        if not cached:
            return []
        return [SourceCandidate.model_validate(item) for item in cached]

    def _cache_candidates(self, target: str, candidates: list[SourceCandidate]) -> None:
        if self.db is None:
            return
        self.db.set_cache(
            _cache_key(target),
            [candidate.model_dump(mode="json") for candidate in candidates],
        )


def _candidate_rank(candidate: SourceCandidate, request: ResolveRequest) -> float:
    title = candidate.title.lower()
    track_title = request.track.title.lower()
    artist = request.track.artist_label.lower()
    score = 0.0
    if track_title and track_title in title:
        score += 5
    if artist and artist != "unknown artist" and artist in title:
        score += 3
    if "official" in title:
        score += 2
    if any(word in title for word in ("cover", "karaoke", "instrumental", "remix")):
        score -= 2
    if request.track.length_ms and candidate.duration_seconds:
        expected = request.track.length_ms / 1000
        diff = abs(expected - candidate.duration_seconds)
        if diff <= 8:
            score += 3
        elif diff <= 25:
            score += 1
        elif diff > 60:
            score -= 3
    return score


def _cache_key(target: str) -> str:
    digest = hashlib.sha256(target.encode("utf-8")).hexdigest()
    return f"source-match:ytdlp:v2:{digest}"


def _dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        deduped.append(value)
    return deduped


def _infer_query_title_artist(query: str) -> tuple[str, str] | None:
    words = [word for word in query.split() if word.strip()]
    if len(words) < 2:
        return None
    return " ".join(words[:-1]), words[-1]


def _youtube_watch_url(value: str | None) -> str | None:
    if not value:
        return None
    parsed = urlparse(value)
    if parsed.scheme in {"http", "https"} and parsed.netloc:
        return value
    video_id = value.strip()
    if not video_id or "/" in video_id or " " in video_id:
        return None
    return f"https://www.youtube.com/watch?v={video_id}"


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


def _friendly_ytdlp_detail(detail: str) -> str:
    if "no supported javascript runtime" in detail.lower():
        return (
            "yt-dlp needs a supported JavaScript runtime for this YouTube URL. "
            f"Resolver detail: {detail}"
        )
    return detail
