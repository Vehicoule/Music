from __future__ import annotations

from dataclasses import dataclass, replace
import re
import time
import unicodedata

from app.core.db import Database
from app.schemas import (
    AdapterName,
    AlbumMetadata,
    ArtistMetadata,
    SearchScope,
    SourceCandidate,
    TrackMetadata,
)

try:
    from rapidfuzz import fuzz
except ImportError:  # pragma: no cover - exercised when optional wheel is unavailable locally.
    fuzz = None


_CUE_WORDS = {
    "acoustic",
    "cover",
    "covers",
    "instrumental",
    "karaoke",
    "live",
    "orchestra",
    "piano",
    "remix",
    "symphony",
    "tribute",
}
_OFFICIAL_WORDS = {"official", "audio", "video", "lyrics", "topic"}
_SOFT_WORDS = {"a", "an", "and", "feat", "featuring", "in", "of", "the", "to"}
_INDEX_MIN_CONFIDENCE = 72
_RANK_BASE_SCORE = 30


@dataclass(frozen=True)
class SourceIndexEntry:
    source_provider: str
    source_id: str
    source_url: str
    title: str
    artist: str = ""
    album: str = ""
    duration_seconds: float | None = None
    confidence_score: float = 0
    rank_reason: str = ""
    artwork_url: str = ""
    source_kind: str = ""
    raw_title: str = ""
    canonical_title: str = ""
    canonical_artist: str = ""
    parse_source: str = ""

    @property
    def normalized_text(self) -> str:
        return _normalize_text(f"{self.artist} {self.title} {self.album}")

    def to_track(self) -> TrackMetadata:
        return TrackMetadata(
            id=f"{self.source_provider}:{self.source_id}",
            title=self.title,
            artists=[ArtistMetadata(name=self.artist or self.source_provider.title())],
            album=AlbumMetadata(title=self.album) if self.album else None,
            length_ms=int(self.duration_seconds * 1000) if self.duration_seconds else None,
            confidence_score=self.confidence_score,
            rank_reason=self.rank_reason,
            artwork_url=self.artwork_url or None,
            source_provider=self.source_provider,
            source_id=self.source_id,
            source_url=self.source_url,
            source_kind=self.source_kind or None,
            raw_title=self.raw_title or None,
            canonical_title=self.canonical_title or self.title,
            canonical_artist=self.canonical_artist or self.artist,
            parse_source=self.parse_source or None,
            source=self.source_provider,
        )


class SourceIndex:
    def __init__(self, db: Database) -> None:
        self.db = db

    def upsert_many(self, entries: list[SourceIndexEntry]) -> None:
        for entry in entries:
            self.upsert(entry)

    def upsert(self, entry: SourceIndexEntry) -> None:
        now = int(time.time())
        with self.db.connect() as db:
            db.execute(
                """
                INSERT INTO source_index(
                    source_provider, source_id, source_url, title, artist, album,
                    duration_seconds, normalized_text, confidence_score, rank_reason,
                    artwork_url, source_kind, raw_title, canonical_title, canonical_artist,
                    parse_source, last_matched_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_provider, source_id) DO UPDATE SET
                    source_url = excluded.source_url,
                    title = excluded.title,
                    artist = excluded.artist,
                    album = excluded.album,
                    duration_seconds = excluded.duration_seconds,
                    normalized_text = excluded.normalized_text,
                    confidence_score = excluded.confidence_score,
                    rank_reason = excluded.rank_reason,
                    artwork_url = excluded.artwork_url,
                    source_kind = excluded.source_kind,
                    raw_title = excluded.raw_title,
                    canonical_title = excluded.canonical_title,
                    canonical_artist = excluded.canonical_artist,
                    parse_source = excluded.parse_source,
                    last_matched_at = excluded.last_matched_at
                """,
                (
                    entry.source_provider,
                    entry.source_id,
                    entry.source_url,
                    entry.title,
                    entry.artist,
                    entry.album,
                    entry.duration_seconds,
                    entry.normalized_text,
                    entry.confidence_score,
                    entry.rank_reason,
                    entry.artwork_url,
                    entry.source_kind,
                    entry.raw_title,
                    entry.canonical_title,
                    entry.canonical_artist,
                    entry.parse_source,
                    now,
                ),
            )
            row = db.execute(
                """
                SELECT source_provider, source_id FROM source_index
                WHERE source_provider = ? AND source_id = ?
                """,
                (entry.source_provider, entry.source_id),
            ).fetchone()
            if row:
                db.execute(
                    "DELETE FROM source_index_fts WHERE source_provider = ? AND source_id = ?",
                    (entry.source_provider, entry.source_id),
                )
                db.execute(
                    """
                    INSERT INTO source_index_fts(source_provider, source_id, normalized_text)
                    VALUES (?, ?, ?)
                    """,
                    (entry.source_provider, entry.source_id, entry.normalized_text),
                )

    def search(
        self, query: str, limit: int = 15, scope: SearchScope = SearchScope.all
    ) -> list[SourceIndexEntry]:
        clean_query = query.strip()
        if not clean_query:
            return []
        entries = self._fts_search(clean_query, limit=max(limit * 2, 30))
        if not entries:
            entries = self._fuzzy_scan(limit=max(limit * 6, 120))
        entries = [entry for entry in entries if _matches_scope(entry, scope)]
        ranked = rank_source_entries(clean_query, entries)
        return [entry for entry in ranked if entry.confidence_score >= _INDEX_MIN_CONFIDENCE][:limit]

    def _fts_search(self, query: str, limit: int) -> list[SourceIndexEntry]:
        tokens = _tokens(query) - _SOFT_WORDS
        if not tokens:
            return []
        fts_query = " OR ".join(f"{token}*" for token in sorted(tokens))
        try:
            with self.db.connect() as db:
                rows = db.execute(
                    """
                    SELECT si.*
                    FROM source_index_fts fts
                    JOIN source_index si
                        ON si.source_provider = fts.source_provider
                        AND si.source_id = fts.source_id
                    WHERE source_index_fts MATCH ?
                    ORDER BY si.confidence_score DESC, si.last_matched_at DESC
                    LIMIT ?
                    """,
                    (fts_query, limit),
                ).fetchall()
        except Exception:
            return []
        return [_row_to_entry(row) for row in rows]

    def _fuzzy_scan(self, limit: int) -> list[SourceIndexEntry]:
        with self.db.connect() as db:
            rows = db.execute(
                """
                SELECT * FROM source_index
                ORDER BY last_matched_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [_row_to_entry(row) for row in rows]

def source_entries_from_candidates(
    query: str, candidates: list[SourceCandidate]
) -> list[SourceIndexEntry]:
    entries: list[SourceIndexEntry] = []
    for candidate in candidates:
        source_url = candidate.source_url
        source_id = candidate.source_id
        provider = candidate.source_provider or _provider_from_adapter(candidate.adapter)
        if not source_url or not source_id:
            continue
        parse_source = candidate.parse_source or "parsed_title"
        if candidate.parse_source == "structured":
            artist = candidate.canonical_artist or ""
            title = candidate.canonical_title or candidate.title
        else:
            artist, title = _split_artist_title(candidate.title, query)
            if not title:
                title = candidate.title
        entry = SourceIndexEntry(
            source_provider=provider,
            source_id=source_id,
            source_url=source_url,
            title=title,
            artist=artist,
            album=candidate.album_title or "",
            duration_seconds=candidate.duration_seconds,
            confidence_score=candidate.confidence_score or 0,
            artwork_url=candidate.artwork_url or "",
            source_kind=candidate.source_kind or "video",
            raw_title=candidate.raw_title or candidate.title,
            canonical_title=candidate.canonical_title or title,
            canonical_artist=candidate.canonical_artist or artist,
            parse_source=parse_source,
        )
        entries.append(entry)
    return rank_source_entries(query, entries)


def rank_source_entries(query: str, entries: list[SourceIndexEntry]) -> list[SourceIndexEntry]:
    query_tokens = _tokens(query)
    query_core = query_tokens - _SOFT_WORDS
    query_cues = query_tokens & _CUE_WORDS
    ranked: list[SourceIndexEntry] = []

    for entry in entries:
        title_tokens = _tokens(entry.title)
        artist_tokens = _tokens(entry.artist)
        album_tokens = _tokens(entry.album)
        combined = title_tokens | artist_tokens | album_tokens
        cue_overlap = combined & _CUE_WORDS
        reasons: list[str] = []
        score = float(_RANK_BASE_SCORE)

        title_similarity = _similarity(" ".join(query_core), " ".join(title_tokens - _SOFT_WORDS))
        combined_similarity = _similarity(query, f"{entry.artist} {entry.title}")
        best_similarity = max(title_similarity, combined_similarity)
        if best_similarity < 50:
            continue

        score += best_similarity * 0.55
        if entry.parse_source == "structured":
            score += 40
            reasons.append("structured")
        elif entry.parse_source == "parsed_title":
            score -= 20
        if entry.source_kind == "song":
            score += 25
            reasons.append("song")
        elif entry.source_kind == "video":
            score -= 4
        if query_core and query_core <= title_tokens:
            score += 35
            reasons.append("exact-title")
        if artist_tokens and query_tokens & artist_tokens:
            score += 70
            reasons.append("artist")
        if query_core and len(query_core & title_tokens) / len(query_core) >= 0.7:
            score += 20
            reasons.append("fuzzy")

        if entry.duration_seconds:
            if 120 <= entry.duration_seconds <= 420:
                score += 12
            elif entry.duration_seconds < 45 or entry.duration_seconds > 900:
                score -= 35

        if _tokens(entry.title) & _OFFICIAL_WORDS:
            score += 10
            reasons.append("official")

        unexpected_cues = cue_overlap - query_cues
        if unexpected_cues:
            score -= 55 + len(unexpected_cues) * 12
            reasons.append("filtered-version")
        if query_cues and cue_overlap:
            score += 45
            reasons.append("requested-version")

        if not reasons and combined_similarity >= 70:
            reasons.append("source-match")

        if not reasons:
            continue

        ranked.append(
            replace(
                entry,
                confidence_score=max(0, round(score, 2)),
                rank_reason=" ".join(dict.fromkeys(reasons)) or "source-match",
            )
        )

    return sorted(ranked, key=lambda item: (-item.confidence_score, item.title.lower()))


def _row_to_entry(row) -> SourceIndexEntry:
    return SourceIndexEntry(
        source_provider=row["source_provider"],
        source_id=row["source_id"],
        source_url=row["source_url"],
        title=row["title"],
        artist=row["artist"],
        album=row["album"],
        duration_seconds=row["duration_seconds"],
        confidence_score=row["confidence_score"],
        rank_reason=row["rank_reason"],
        artwork_url=row["artwork_url"] if "artwork_url" in row.keys() else "",
        source_kind=row["source_kind"] if "source_kind" in row.keys() else "",
        raw_title=row["raw_title"] if "raw_title" in row.keys() else "",
        canonical_title=row["canonical_title"] if "canonical_title" in row.keys() else "",
        canonical_artist=row["canonical_artist"] if "canonical_artist" in row.keys() else "",
        parse_source=row["parse_source"] if "parse_source" in row.keys() else "",
    )


def _split_artist_title(value: str, query: str = "") -> tuple[str, str]:
    cleaned = re.sub(r"\([^)]*\)|\[[^]]*]", "", value).strip()
    cleaned = re.sub(r"\bofficial\b|\baudio\b|\bvideo\b|\blyrics\b", "", cleaned, flags=re.I)
    cleaned = _strip_noise(cleaned)
    parts = [_strip_noise(part.strip(" -")) for part in cleaned.split("-", maxsplit=1)]
    if len(parts) == 2 and all(parts):
        left, right = parts
        query_tokens = _tokens(query)
        left_tokens = _tokens(left)
        right_tokens = _tokens(right)
        if query_tokens and len(query_tokens & left_tokens) > len(query_tokens & right_tokens):
            return right, left
        return left, right
    return "", cleaned


def _provider_from_adapter(adapter: AdapterName) -> str:
    return "youtube" if adapter == AdapterName.ytdlp else adapter.value


def _matches_scope(entry: SourceIndexEntry, scope: SearchScope) -> bool:
    if scope in {SearchScope.all, SearchScope.songs}:
        return entry.source_kind in {"", "song"} if scope == SearchScope.songs else True
    if scope == SearchScope.videos:
        return entry.source_kind == "video"
    return False


def _tokens(value: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", value.lower()) if len(token) > 1}


def _normalize_text(value: str) -> str:
    return " ".join(sorted(_tokens(value)))


def _strip_noise(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^\w\s'&.,-]", "", ascii_value, flags=re.UNICODE).strip()


def _similarity(left: str, right: str) -> float:
    if not left or not right:
        return 0.0
    if fuzz is not None:
        return float(fuzz.token_set_ratio(left, right))

    from difflib import SequenceMatcher

    return SequenceMatcher(None, left.lower(), right.lower()).ratio() * 100
