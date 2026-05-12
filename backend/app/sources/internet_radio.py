from __future__ import annotations

from app.schemas import AdapterCapability, AdapterName, ResolveRequest, SourceCandidate
from app.sources.base import SourceAdapter


DEFAULT_STATIONS = [
    {
        "title": "SomaFM Groove Salad",
        "url": "https://ice1.somafm.com/groovesalad-128-mp3",
        "mime_type": "audio/mpeg",
    },
    {
        "title": "SomaFM Deep Space One",
        "url": "https://ice1.somafm.com/deepspaceone-128-mp3",
        "mime_type": "audio/mpeg",
    },
]


class InternetRadioAdapter(SourceAdapter):
    async def capability(self) -> AdapterCapability:
        return AdapterCapability(
            name=AdapterName.internet_radio,
            enabled=True,
            healthy=True,
            label="Internet radio",
            supports_live_stream=True,
            notes="Streams configured live radio station URLs.",
        )

    async def resolve(self, request: ResolveRequest) -> list[SourceCandidate]:
        query = f"{request.track.title} {request.track.artist_label}".lower()
        candidates = []
        for station in DEFAULT_STATIONS:
            if request.source_url and str(request.source_url) == station["url"]:
                candidates.append(self._station_candidate(station))
            elif (
                station["title"].lower() in query
                or request.track.title.lower() in station["title"].lower()
            ):
                candidates.append(self._station_candidate(station))
        return candidates

    def _station_candidate(self, station: dict[str, str]) -> SourceCandidate:
        return SourceCandidate(
            adapter=AdapterName.internet_radio,
            url=station["url"],
            title=station["title"],
            mime_type=station["mime_type"],
            is_live=True,
        )
