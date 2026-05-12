from pathlib import Path

from app.core.db import Database
from app.schemas import AdapterName, SourceCandidate
from app.services.source_index import (
    SourceIndex,
    SourceIndexEntry,
    rank_source_entries,
    source_entries_from_candidates,
)


def test_source_index_returns_fuzzy_source_matches(tmp_path: Path):
    db = Database(tmp_path / "index.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="youtube",
            source_id="rYEDA3JcQqw",
            source_url="https://www.youtube.com/watch?v=rYEDA3JcQqw",
            title="Rolling in the Deep",
            artist="Adele",
            album="21",
            duration_seconds=228,
            confidence_score=98,
            rank_reason="official source match",
        )
    )

    matches = index.search("roling in the dep")

    assert matches
    assert matches[0].artist == "Adele"
    assert matches[0].source_id == "rYEDA3JcQqw"
    assert matches[0].confidence_score >= 80


def test_source_ranking_prefers_original_over_covers():
    entries = [
        SourceIndexEntry(
            source_provider="youtube",
            source_id="cover",
            source_url="https://www.youtube.com/watch?v=cover",
            title="Rolling in the Deep",
            artist="The Piano Guys",
            album="Piano Cover",
            duration_seconds=231,
            confidence_score=97,
        ),
        SourceIndexEntry(
            source_provider="youtube",
            source_id="adele",
            source_url="https://www.youtube.com/watch?v=adele",
            title="Rolling in the Deep",
            artist="Adele",
            album="21",
            duration_seconds=228,
            confidence_score=91,
        ),
    ]

    ranked = rank_source_entries("rolling in the deep adele", entries)

    assert ranked[0].source_id == "adele"
    assert "artist" in ranked[0].rank_reason


def test_source_ranking_respects_explicit_cover_query():
    entries = [
        SourceIndexEntry(
            source_provider="youtube",
            source_id="original",
            source_url="https://www.youtube.com/watch?v=original",
            title="Rolling in the Deep",
            artist="Adele",
            album="21",
            duration_seconds=228,
            confidence_score=95,
        ),
        SourceIndexEntry(
            source_provider="youtube",
            source_id="cover",
            source_url="https://www.youtube.com/watch?v=cover",
            title="Rolling in the Deep",
            artist="The Piano Guys",
            album="Piano Cover",
            duration_seconds=231,
            confidence_score=90,
        ),
    ]

    ranked = rank_source_entries("rolling in the deep piano cover", entries)

    assert ranked[0].source_id == "cover"
    assert "requested-version" in ranked[0].rank_reason


def test_source_index_does_not_return_unrelated_recent_rows(tmp_path: Path):
    db = Database(tmp_path / "index.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="youtube",
            source_id="rYEDA3JcQqw",
            source_url="https://www.youtube.com/watch?v=rYEDA3JcQqw",
            title="Rolling in the Deep",
            artist="Adele",
            duration_seconds=234,
            confidence_score=250,
        )
    )

    matches = index.search("daft punk around the world")

    assert matches == []


def test_source_index_does_not_return_weak_cached_hits_for_short_queries(tmp_path: Path):
    db = Database(tmp_path / "index.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="youtube",
            source_id="mira-bella",
            source_url="https://www.youtube.com/watch?v=mira",
            title="Bella",
            artist="MIRA",
            duration_seconds=173,
            confidence_score=96,
        )
    )

    matches = index.search("bella gims")

    assert matches == []


def test_source_index_confidence_does_not_compound_across_queries(tmp_path: Path):
    db = Database(tmp_path / "index.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="youtube",
            source_id="rYEDA3JcQqw",
            source_url="https://www.youtube.com/watch?v=rYEDA3JcQqw",
            title="Rolling in the Deep",
            artist="Adele",
            duration_seconds=234,
            confidence_score=250,
        )
    )

    first = index.search("rolling in the deep")[0].confidence_score
    second = index.search("rolling in the deep")[0].confidence_score

    assert second == first
    assert second < 200


def test_source_candidate_parser_handles_title_artist_order():
    entries = source_entries_from_candidates(
        "rolling in the deep",
        [
            SourceCandidate(
                adapter=AdapterName.ytdlp,
                url="https://cdn.example.test/audio.m4a",
                title="Rolling In The Deep - Adele 🎵",
                source_provider="youtube",
                source_id="AIYpdjQVidc",
                source_url="https://www.youtube.com/watch?v=AIYpdjQVidc",
                duration_seconds=247,
            )
        ],
    )

    assert entries[0].title == "Rolling In The Deep"
    assert entries[0].artist == "Adele"


def test_source_candidate_parser_uses_query_artist_hint():
    entries = source_entries_from_candidates(
        "bella gims",
        [
            SourceCandidate(
                adapter=AdapterName.ytdlp,
                url="https://cdn.example.test/audio.m4a",
                title="Maître Gims - Bella",
                source_provider="youtube",
                source_id="56BRFlaxsGw",
                source_url="https://www.youtube.com/watch?v=56BRFlaxsGw",
                duration_seconds=278,
            ),
            SourceCandidate(
                adapter=AdapterName.ytdlp,
                url="https://cdn.example.test/other.m4a",
                title="MIRA - Bella",
                source_provider="youtube",
                source_id="other",
                source_url="https://www.youtube.com/watch?v=other",
                duration_seconds=173,
            ),
        ],
    )

    assert entries[0].source_id == "56BRFlaxsGw"
    assert entries[0].title == "Bella"
    assert entries[0].artist == "Maitre Gims"


def test_structured_source_candidate_bypasses_title_artist_parser():
    entries = source_entries_from_candidates(
        "bella gims",
        [
            SourceCandidate(
                adapter=AdapterName.ytmusic,
                url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                title="Bella",
                source_provider="ytmusic",
                source_id="56BRFlaxsGw",
                source_url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                duration_seconds=278,
                artwork_url="https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg",
                canonical_title="Bella",
                canonical_artist="GIMS",
                album_title="Subliminal",
                source_kind="song",
                raw_title="GIMS - Bella",
                parse_source="structured",
            )
        ],
    )

    assert entries[0].title == "Bella"
    assert entries[0].artist == "GIMS"
    assert entries[0].album == "Subliminal"
    assert entries[0].artwork_url == "https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg"
    assert entries[0].source_kind == "song"
    assert entries[0].parse_source == "structured"


def test_source_index_schema_version_purges_legacy_rows(tmp_path: Path):
    db = Database(tmp_path / "index.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="youtube",
            source_id="bad",
            source_url="https://www.youtube.com/watch?v=bad",
            title="Adele",
            artist="Rolling In The Deep",
            confidence_score=250,
        )
    )

    with db.connect() as connection:
        connection.execute("DELETE FROM metadata_cache WHERE cache_key = ?", ("source-index:schema-version:v4",))

    db.init()

    assert SourceIndex(db).search("rolling in the deep") == []


def test_source_index_search_is_scope_aware(tmp_path: Path):
    db = Database(tmp_path / "streambox.sqlite3")
    db.init()
    index = SourceIndex(db)
    index.upsert(
        SourceIndexEntry(
            source_provider="ytmusic",
            source_id="song-1",
            source_url="https://music.youtube.com/watch?v=song-1",
            title="Bella",
            artist="GIMS",
            source_kind="song",
            parse_source="structured",
            confidence_score=95,
        )
    )
    index.upsert(
        SourceIndexEntry(
            source_provider="ytmusic",
            source_id="video-1",
            source_url="https://music.youtube.com/watch?v=video-1",
            title="Bella live",
            artist="GIMS",
            source_kind="video",
            parse_source="structured",
            confidence_score=85,
        )
    )

    from app.schemas import SearchScope

    assert [entry.source_kind for entry in index.search("bella gims", scope=SearchScope.songs)] == ["song"]
    assert [entry.source_kind for entry in index.search("bella gims", scope=SearchScope.videos)] == ["video"]
