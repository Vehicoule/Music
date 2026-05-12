from __future__ import annotations

from urllib.parse import urlparse

import httpx

from app.schemas import AdapterCapability, AdapterName, ResolveRequest, SourceCandidate
from app.sources.base import SourceAdapter


class DirectUrlAdapter(SourceAdapter):
    async def capability(self) -> AdapterCapability:
        return AdapterCapability(
            name=AdapterName.direct_url,
            enabled=True,
            healthy=True,
            label="Direct audio URL",
            supports_direct_url=True,
            notes="Accepts HTTPS/HTTP audio stream URLs supplied by the user.",
        )

    async def resolve(self, request: ResolveRequest) -> list[SourceCandidate]:
        if not request.source_url:
            return []
        url = str(request.source_url)
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"}:
            return []

        mime_type = await self._content_type(url)
        if mime_type and not self._looks_playable(url, mime_type):
            return []

        return [
            SourceCandidate(
                adapter=AdapterName.direct_url,
                url=url,
                title=request.track.title,
                mime_type=mime_type,
                is_live=url.endswith(".m3u8"),
            )
        ]

    async def _content_type(self, url: str) -> str | None:
        try:
            async with httpx.AsyncClient(timeout=5.0, follow_redirects=True) as client:
                response = await client.head(url)
        except httpx.HTTPError:
            return None
        if response.status_code >= 400:
            return None
        value = response.headers.get("content-type")
        return value.split(";")[0].strip().lower() if value else None

    def _looks_playable(self, url: str, mime_type: str) -> bool:
        audio_mimes = {
            "audio/aac",
            "audio/flac",
            "audio/mpeg",
            "audio/mp4",
            "audio/ogg",
            "audio/wav",
            "application/ogg",
            "application/vnd.apple.mpegurl",
            "application/x-mpegurl",
        }
        audio_suffixes = (".aac", ".flac", ".m3u8", ".m4a", ".mp3", ".ogg", ".opus", ".wav")
        return mime_type in audio_mimes or url.lower().split("?")[0].endswith(audio_suffixes)

