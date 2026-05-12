from __future__ import annotations

from dataclasses import dataclass

import httpx

from app.core.config import Settings
from app.core.db import Database


@dataclass(frozen=True)
class PopularityStats:
    listen_count: int | None = None
    listener_count: int | None = None

    @property
    def score(self) -> float:
        listens = self.listen_count or 0
        listeners = self.listener_count or 0
        return (listeners * 10.0) + listens


class ListenBrainzClient:
    def __init__(self, settings: Settings, db: Database) -> None:
        self.settings = settings
        self.db = db

    async def recording_popularity(self, recording_ids: list[str]) -> dict[str, PopularityStats]:
        ids = [recording_id for recording_id in dict.fromkeys(recording_ids) if recording_id]
        if not ids:
            return {}

        cached: dict[str, PopularityStats] = {}
        missing: list[str] = []
        for recording_id in ids:
            cache_key = _recording_cache_key(recording_id)
            payload = self.db.get_cache(cache_key, self.settings.popularity_cache_ttl_seconds)
            if payload is None:
                missing.append(recording_id)
                continue
            cached[recording_id] = PopularityStats(
                listen_count=payload.get("listen_count"),
                listener_count=payload.get("listener_count"),
            )

        if missing:
            fetched = await self._fetch_recording_popularity(missing)
            cached.update(fetched)
            for recording_id, stats in fetched.items():
                self.db.set_cache(
                    _recording_cache_key(recording_id),
                    {
                        "listen_count": stats.listen_count,
                        "listener_count": stats.listener_count,
                    },
                )

        return cached

    async def _fetch_recording_popularity(
        self,
        recording_ids: list[str],
    ) -> dict[str, PopularityStats]:
        url = f"{self.settings.listenbrainz_base_url}/1/popularity/recording"
        async with httpx.AsyncClient(timeout=self.settings.listenbrainz_timeout_seconds) as client:
            response = await client.post(url, json={"recording_mbids": recording_ids})
            response.raise_for_status()
            payload = response.json()

        stats: dict[str, PopularityStats] = {}
        for item in payload:
            recording_id = item.get("recording_mbid")
            if not recording_id:
                continue
            stats[recording_id] = PopularityStats(
                listen_count=item.get("total_listen_count"),
                listener_count=item.get("total_user_count"),
            )
        return stats


def _recording_cache_key(recording_id: str) -> str:
    return f"listenbrainz:popularity:recording:v1:{recording_id}"
