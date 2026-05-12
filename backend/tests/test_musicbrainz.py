from pathlib import Path

from app.core.config import Settings
from app.core.db import Database
from app.schemas import TrackMetadata
from app.services.listenbrainz import PopularityStats
from app.services.musicbrainz import MusicBrainzClient, _query_variants


def test_recording_parser_maps_core_metadata(tmp_path: Path):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)

    track = client._recording_to_track(
        {
            "id": "abc",
            "title": "Song",
            "length": 123000,
            "artist-credit": [{"artist": {"id": "artist-1", "name": "Artist"}}],
            "releases": [
                {
                    "id": "release-1",
                    "title": "Album",
                    "release-group": {"id": "group-1"},
                }
            ],
        }
    )

    assert track.id == "abc"
    assert track.title == "Song"
    assert track.artists[0].name == "Artist"
    assert track.album is not None
    assert track.album.release_group_id == "group-1"


def test_ranking_prefers_strong_title_artist_matches(tmp_path: Path):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)
    strong = TrackMetadata(
        id="1",
        title="Rolling in the Deep",
        artists=[{"name": "Adele"}],
        length_ms=234000,
        score=95,
    )
    weak = TrackMetadata(
        id="2",
        title="Rolling in the Doe",
        artists=[{"name": "Big Sean"}],
        length_ms=30000,
        score=100,
    )

    ranked = client._rank_tracks("rolling in the deep adele", [weak, strong])

    assert ranked[0].id == "1"


def test_ranking_prefers_canonical_plain_title_over_cover_cues(tmp_path: Path):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)
    canonical = TrackMetadata(
        id="adele",
        title="Rolling in the Deep",
        artists=[{"name": "Adele"}],
        album={"title": "Rolling in the Deep"},
        length_ms=228000,
        score=92,
        release_count=12,
    )
    cover = TrackMetadata(
        id="cover",
        title="Rolling in the Deep",
        artists=[{"name": "The Piano Guys"}],
        album={"title": "Instrumental Neo Classical Music"},
        length_ms=231000,
        score=100,
        release_count=1,
    )

    ranked = client._rank_tracks("rolling in the deep", [cover, canonical])

    assert ranked[0].id == "adele"


def test_ranking_respects_explicit_cover_query(tmp_path: Path):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)
    original = TrackMetadata(
        id="original",
        title="Rolling in the Deep",
        artists=[{"name": "Adele"}],
        album={"title": "Rolling in the Deep"},
        length_ms=228000,
        score=92,
        release_count=12,
    )
    cover = TrackMetadata(
        id="cover",
        title="Rolling in the Deep",
        artists=[{"name": "The Piano Guys"}],
        album={"title": "Piano Cover"},
        length_ms=231000,
        score=100,
        release_count=1,
    )

    ranked = client._rank_tracks("rolling in the deep piano cover", [cover, original])

    assert ranked[0].id == "cover"


def test_query_variants_do_not_treat_stopword_as_artist():
    variants = [variant.query for variant in _query_variants("rolling in the")]

    assert 'recording:"rolling in" AND artist:"the"' not in variants


async def test_popularity_boosts_matching_tracks(tmp_path: Path):
    class ListenBrainzStub:
        async def recording_popularity(self, recording_ids):
            return {
                recording_ids[0]: PopularityStats(listen_count=500_000, listener_count=20_000),
                recording_ids[1]: PopularityStats(listen_count=100, listener_count=10),
            }

    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db, ListenBrainzStub())
    tracks = [
        TrackMetadata(id="popular", title="Rolling in the Deep", artists=[{"name": "Adele"}]),
        TrackMetadata(id="cover", title="Rolling in the Deep", artists=[{"name": "Cover Band"}]),
    ]

    updated = await client._attach_popularity(tracks)
    ranked = client._rank_tracks("rolling in the deep", updated)

    assert ranked[0].id == "popular"
    assert "popular" in ranked[0].match_reasons


def test_popularity_cannot_promote_weak_title_match(tmp_path: Path):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)
    strong = TrackMetadata(
        id="strong",
        title="Rolling in the Deep",
        artists=[{"name": "Adele"}],
        popularity_score=100,
        length_ms=228000,
        score=90,
    )
    weak_popular = TrackMetadata(
        id="weak",
        title="Rolling In The Ground",
        artists=[{"name": "Blue in Heaven"}],
        popularity_score=1_000_000,
        length_ms=309000,
        score=100,
    )

    ranked = client._rank_tracks("rolling in the deep adele", [weak_popular, strong])

    assert ranked[0].id == "strong"


async def test_search_does_not_block_on_artwork(tmp_path: Path, monkeypatch):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)

    async def fake_get_json(*_args, **_kwargs):
        return {
            "recordings": [
                {
                    "id": "abc",
                    "title": "Song",
                    "score": 90,
                    "length": 200000,
                    "artist-credit": [{"artist": {"name": "Artist"}}],
                    "releases": [{"id": "release-1", "title": "Album"}],
                }
            ]
        }

    async def fail_artwork(*_args, **_kwargs):
        raise AssertionError("artwork should not be fetched during search")

    monkeypatch.setattr(client, "_get_json", fake_get_json)
    monkeypatch.setattr(client, "_cover_art_url", fail_artwork)

    tracks = await client.search_tracks("song artist")

    assert tracks[0].title == "Song"


async def test_artwork_failure_does_not_fail_search(tmp_path: Path, monkeypatch):
    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    client = MusicBrainzClient(Settings(database_path=db.path), db)
    track = client._recording_to_track(
        {
            "id": "abc",
            "title": "Song",
            "artist-credit": [{"artist": {"name": "Artist"}}],
            "releases": [{"id": "release-1", "title": "Album"}],
        }
    )

    async def fail_artwork(*_args, **_kwargs):
        raise ValueError("bad response")

    monkeypatch.setattr(client, "_cover_art_url", fail_artwork)
    tracks = await client._attach_artwork([track])

    assert tracks[0].title == "Song"
