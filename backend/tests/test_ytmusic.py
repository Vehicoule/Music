from app.core.config import Settings
from app.core.db import Database
from app.schemas import AdapterName, ResolveRequest, SearchScope, TrackMetadata
from app.sources.ytmusic import YtMusicAdapter


async def test_ytmusic_structured_song_result_preserves_artist_title_and_artwork():
    calls = []

    class FakeClient:
        def search(self, query, filter, limit):
            calls.append(filter)
            assert query == "bella gims"
            assert limit == 12
            if filter == "videos":
                return []
            return [
                {
                    "resultType": "song",
                    "videoId": "56BRFlaxsGw",
                    "title": "Bella",
                    "artists": [{"name": "GIMS", "id": "UC-gims"}],
                    "album": {"name": "Subliminal", "id": "MPREb_album"},
                    "duration_seconds": 278,
                    "thumbnails": [{"url": "https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg"}],
                }
            ]

    adapter = YtMusicAdapter(Settings(), client=FakeClient())

    candidates = await adapter.source_search(
        ResolveRequest(track=TrackMetadata(id="query", title="bella gims", artists=[])),
        limit=12,
    )

    assert candidates[0].adapter == AdapterName.ytmusic
    assert calls == ["songs", "videos"]
    assert candidates[0].title == "Bella"
    assert candidates[0].canonical_title == "Bella"
    assert candidates[0].canonical_artist == "GIMS"
    assert candidates[0].album_title == "Subliminal"
    assert candidates[0].artwork_url == "https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg"
    assert candidates[0].source_kind == "song"
    assert candidates[0].parse_source == "structured"
    assert candidates[0].source_url == "https://music.youtube.com/watch?v=56BRFlaxsGw"


async def test_ytmusic_queries_songs_and_videos_for_broader_results():
    calls = []

    class FakeClient:
        def search(self, query, filter, limit):
            calls.append(filter)
            if filter == "songs":
                return [
                    {
                        "resultType": "song",
                        "videoId": f"song-{index}",
                        "title": f"Call {index}",
                        "artists": [{"name": f"Song Artist {index}"}],
                        "duration_seconds": 180 + index,
                    }
                    for index in range(3)
                ]
            return [
                {
                    "resultType": "video",
                    "videoId": f"video-{index}",
                    "title": f"Video Artist {index} - Call",
                    "artists": [{"name": f"Video Artist {index}"}],
                    "duration_seconds": 200 + index,
                    "thumbnails": [{"url": f"https://i.ytimg.com/vi/video-{index}/hqdefault.jpg"}],
                }
                for index in range(8)
            ]

    adapter = YtMusicAdapter(Settings(), client=FakeClient())

    candidates = await adapter.source_search(
        ResolveRequest(track=TrackMetadata(id="query", title="artist song", artists=[])),
        limit=12,
    )

    assert calls == ["songs", "videos"]
    assert len(candidates) == 11
    assert [candidate.source_kind for candidate in candidates[:3]] == ["song", "song", "song"]
    assert candidates[3].source_kind == "video"
    assert candidates[3].parse_source == "structured"


async def test_ytmusic_deduplicates_video_when_song_has_same_video_id():
    class FakeClient:
        def search(self, query, filter, limit):
            if filter == "songs":
                return [
                    {
                        "resultType": "song",
                        "videoId": "same-id",
                        "title": "Call",
                        "artists": [{"name": "Song Artist"}],
                        "duration_seconds": 180,
                    }
                ]
            return [
                {
                    "resultType": "video",
                    "videoId": "same-id",
                    "title": "Song Artist - Call",
                    "artists": [{"name": "Song Artist"}],
                    "duration_seconds": 180,
                },
                {
                    "resultType": "video",
                    "videoId": "video-2",
                    "title": "Other Artist - Call",
                    "artists": [{"name": "Other Artist"}],
                    "duration_seconds": 200,
                },
            ]

    adapter = YtMusicAdapter(Settings(), client=FakeClient())

    candidates = await adapter.source_search(
        ResolveRequest(track=TrackMetadata(id="query", title="call", artists=[])),
        limit=12,
    )

    assert [candidate.source_id for candidate in candidates] == ["same-id", "video-2"]
    assert candidates[0].source_kind == "song"


async def test_ytmusic_scoped_search_returns_typed_songs_albums_artists_and_videos():
    calls = []

    class FakeClient:
        def search(self, query, filter, limit):
            calls.append(filter)
            assert query == "gims"
            assert limit == 12
            return {
                "songs": [
                    {
                        "resultType": "song",
                        "videoId": "song-1",
                        "title": "Bella",
                        "artists": [{"name": "GIMS", "id": "UC-gims"}],
                        "album": {"name": "Subliminal", "id": "MPREb_album"},
                        "duration_seconds": 278,
                        "thumbnails": [{"url": "https://img/song.jpg"}],
                    }
                ],
                "albums": [
                    {
                        "resultType": "album",
                        "browseId": "MPREb_album",
                        "playlistId": "OLAK5uy_album",
                        "title": "Subliminal",
                        "artists": [{"name": "GIMS", "id": "UC-gims"}],
                        "year": "2013",
                        "thumbnails": [{"url": "https://img/album.jpg"}],
                    }
                ],
                "artists": [
                    {
                        "resultType": "artist",
                        "browseId": "UC-gims",
                        "artist": "GIMS",
                        "thumbnails": [{"url": "https://img/artist.jpg"}],
                    }
                ],
                "videos": [
                    {
                        "resultType": "video",
                        "videoId": "video-1",
                        "title": "GIMS - Bella",
                        "artists": [{"name": "GIMS", "id": "UC-gims"}],
                        "duration_seconds": 280,
                    }
                ],
            }[filter]

    adapter = YtMusicAdapter(Settings(), client=FakeClient())

    results = await adapter.search("gims", scope=SearchScope.all, limit=12)

    assert calls == ["songs", "albums", "artists", "videos"]
    assert [item.kind for item in results] == ["song", "album", "artist", "video"]
    assert results[0].track.title == "Bella"
    assert results[0].track.artist_label == "GIMS"
    assert results[1].album_result.title == "Subliminal"
    assert results[1].album_result.artwork_url == "https://img/album.jpg"
    assert results[2].artist_result.name == "GIMS"
    assert results[2].artist_result.artwork_url == "https://img/artist.jpg"
    assert results[3].track.source_kind == "video"


async def test_ytmusic_scoped_search_only_calls_requested_scope():
    calls = []

    class FakeClient:
        def search(self, query, filter, limit):
            calls.append(filter)
            if filter == "artists":
                return [{"browseId": "UC-gims", "artist": "GIMS"}]
            return []

    adapter = YtMusicAdapter(Settings(), client=FakeClient())

    results = await adapter.search("gims", scope=SearchScope.artists, limit=12)

    assert calls == ["artists"]
    assert len(results) == 1
    assert results[0].kind == "artist"


async def test_ytmusic_album_detail_returns_playable_tracks(tmp_path):
    calls = []

    class FakeClient:
        def get_album(self, browse_id):
            calls.append(browse_id)
            return {
                "title": "Subliminal",
                "year": "2013",
                "audioPlaylistId": "OLAK5uy_album",
                "artists": [{"name": "GIMS", "id": "UC-gims"}],
                "thumbnails": [{"url": "https://img/album.jpg"}],
                "tracks": [
                    {
                        "videoId": "56BRFlaxsGw",
                        "title": "Bella",
                        "artists": [{"name": "GIMS", "id": "UC-gims"}],
                        "duration_seconds": 278,
                    }
                ],
            }

    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    adapter = YtMusicAdapter(Settings(), client=FakeClient(), db=db)

    detail = await adapter.album_detail("MPREb_album")

    assert calls == ["MPREb_album"]
    assert detail.title == "Subliminal"
    assert detail.artist_label == "GIMS"
    assert detail.artwork_url == "https://img/album.jpg"
    assert detail.tracks[0].kind == "song"
    assert detail.tracks[0].track.title == "Bella"
    assert detail.tracks[0].track.source_url == "https://music.youtube.com/watch?v=56BRFlaxsGw"


async def test_ytmusic_artist_detail_returns_typed_sections(tmp_path):
    class FakeClient:
        def get_artist(self, browse_id):
            assert browse_id == "UC-gims"
            return {
                "name": "GIMS",
                "channelId": "UC-gims-channel",
                "thumbnails": [{"url": "https://img/artist.jpg"}],
                "songs": {
                    "results": [
                        {
                            "videoId": "song-1",
                            "title": "Bella",
                            "artists": [{"name": "GIMS"}],
                            "duration_seconds": 278,
                        }
                    ]
                },
                "albums": {
                    "results": [
                        {
                            "browseId": "MPREb_album",
                            "title": "Subliminal",
                            "artists": [{"name": "GIMS"}],
                            "year": "2013",
                        }
                    ]
                },
                "videos": {
                    "results": [
                        {
                            "videoId": "video-1",
                            "title": "GIMS - Bella",
                            "artists": [{"name": "GIMS"}],
                            "duration_seconds": 280,
                        }
                    ]
                },
            }

    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    adapter = YtMusicAdapter(Settings(), client=FakeClient(), db=db)

    detail = await adapter.artist_detail("UC-gims")

    assert detail.name == "GIMS"
    assert detail.artwork_url == "https://img/artist.jpg"
    assert [section.label for section in detail.sections] == ["Top songs", "Albums", "Videos"]
    assert detail.sections[0].items[0].track.title == "Bella"
    assert detail.sections[1].items[0].album_result.title == "Subliminal"
    assert detail.sections[2].items[0].kind == "video"


async def test_ytmusic_search_uses_cache_for_repeated_queries(tmp_path):
    calls = 0

    class FakeClient:
        def search(self, query, filter, limit):
            nonlocal calls
            calls += 1
            return [
                {
                    "resultType": "artist",
                    "browseId": "UC-gims",
                    "artist": "GIMS",
                }
            ]

    db = Database(tmp_path / "cache.sqlite3")
    db.init()
    adapter = YtMusicAdapter(Settings(), client=FakeClient(), db=db)

    first = await adapter.search("gims", scope=SearchScope.artists, limit=12)
    second = await adapter.search("gims", scope=SearchScope.artists, limit=12)

    assert calls == 1
    assert first[0].artist_result.name == "GIMS"
    assert second[0].artist_result.name == "GIMS"
