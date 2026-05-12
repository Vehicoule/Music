import httpx

from app.schemas import (
    AdapterName,
    AlbumSearchResult,
    ArtistSearchResult,
    DiscoverItem,
    DiscoverKind,
    DiscoverWarning,
    SearchMode,
    SearchScope,
    SourceCandidate,
    TrackMetadata,
)
from app.services.discovery import DiscoveryService, is_url, normalize_input_url
from app.services.source_index import SourceIndexEntry


def test_url_classifier_detects_http_urls():
    assert is_url("https://youtu.be/example")
    assert is_url("https://example.com/audio.mp3")
    assert not is_url("daft punk around the world")


def test_url_normalizer_handles_youtube_variants():
    expected = "https://www.youtube.com/watch?v=rYEDA3JcQqw"
    assert normalize_input_url("youtube.com/watch?v=rYEDA3JcQqw&list=abc") == expected
    assert normalize_input_url("https://music.youtube.com/watch?v=rYEDA3JcQqw&start_radio=1") == expected
    assert normalize_input_url("https://youtu.be/rYEDA3JcQqw") == expected
    assert normalize_input_url("?v=rYEDA3JcQqw&list=abc") == expected
    assert normalize_input_url("v=rYEDA3JcQqw") == expected


async def test_discover_returns_playable_items_for_url():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def resolve_with_warnings(self, request):
            assert request.source_url is not None
            return [
                SourceCandidate(
                    adapter=AdapterName.ytdlp,
                    url="https://cdn.example.test/audio.m4a",
                    title="Resolved title",
                )
            ], []

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover(
        "https://youtu.be/example"
    )

    assert response.mode == "url"
    assert response.items[0].source is not None
    assert response.items[0].track.title == "Resolved title"
    assert response.warnings == []


async def test_discover_returns_resolver_warning_for_url():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def resolve_with_warnings(self, _request):
            return [], [DiscoverWarning(code="yt_dlp_warning", message="resolver failed")]

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover(
        "https://youtu.be/example"
    )

    assert response.items == []
    assert response.warnings[0].message == "resolver failed"


async def test_discover_returns_metadata_items_for_text():
    class MusicBrainzStub:
        async def search_tracks(self, query):
            assert query == "daft punk"
            return [TrackMetadata(id="1", title="One More Time", artists=[{"name": "Daft Punk"}])]

    class SourcesStub:
        async def resolve(self, _request):
            return []

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover("daft punk")

    assert response.mode == "metadata"
    assert response.items[0].track.title == "One More Time"
    assert response.items[0].source is None


async def test_discover_scoped_song_search_uses_only_ytmusic_not_ytdlp():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            raise AssertionError("MusicBrainz should not run when YouTube Music returns songs")

    class SourcesStub:
        async def ytmusic_search(self, query, scope=SearchScope.all, limit=12):
            assert query == "bella"
            assert scope == SearchScope.songs
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id="ytmusic:56BRFlaxsGw",
                        title="Bella",
                        artists=[{"name": "GIMS"}],
                        artwork_url="https://img/song.jpg",
                        source_provider="ytmusic",
                        source_id="56BRFlaxsGw",
                        source_url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                        source_kind="song",
                        source="ytmusic",
                    ),
                    label="YouTube Music",
                )
            ]

        async def source_search_with_warnings(self, _request, limit=12):
            raise AssertionError("yt-dlp flat discovery must not run during text search")

    class SourceIndexStub:
        def search(self, _query, scope=SearchScope.all):
            assert scope == SearchScope.songs
            return []

        def upsert_many(self, entries):
            self.entries = entries

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("bella", scope=SearchScope.songs)

    assert response.scope == SearchScope.songs
    assert response.items[0].kind == DiscoverKind.song
    assert response.items[0].track.title == "Bella"


async def test_discover_album_and_artist_scopes_return_non_playable_typed_results():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, _query, scope=SearchScope.all, limit=12):
            if scope == SearchScope.albums:
                return [
                    DiscoverItem(
                        mode=SearchMode.stream,
                        kind=DiscoverKind.album,
                        album_result=AlbumSearchResult(
                            title="Subliminal",
                            artists=[{"name": "GIMS"}],
                            browse_id="MPREb_album",
                            playlist_id="OLAK5uy_album",
                            year="2013",
                            artwork_url="https://img/album.jpg",
                        ),
                        label="YouTube Music",
                    )
                ]
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.artist,
                    artist_result=ArtistSearchResult(
                        name="GIMS",
                        browse_id="UC-gims",
                        artwork_url="https://img/artist.jpg",
                    ),
                    label="YouTube Music",
                )
            ]

    class SourceIndexStub:
        def search(self, _query, scope=SearchScope.all):
            return []

        def upsert_many(self, _entries):
            pass

    album_response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("gims", scope=SearchScope.albums)
    artist_response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("gims", scope=SearchScope.artists)

    assert album_response.items[0].kind == DiscoverKind.album
    assert album_response.items[0].track is None
    assert album_response.items[0].album_result.title == "Subliminal"
    assert artist_response.items[0].kind == DiscoverKind.artist
    assert artist_response.items[0].artist_result.name == "GIMS"


async def test_discover_uses_musicbrainz_fallback_without_playable_hint_when_ytmusic_is_unavailable():
    class MusicBrainzStub:
        async def search_tracks(self, query):
            assert query == "rolling in the"
            return [TrackMetadata(id="1", title="Rolling in the Deep", artists=[{"name": "Adele"}])]

    class SourcesStub:
        async def resolve_with_warnings(self, _request):
            raise AssertionError("yt-dlp should not provide playable hints for normal search")

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover("rolling in the")

    assert response.items[0].track.artists[0].name == "Adele"
    assert response.warnings == []


async def test_discover_playable_returns_source_confirmed_items():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def resolve_with_warnings(self, request):
            assert request.adapters == [AdapterName.ytdlp]
            return [
                SourceCandidate(
                    adapter=AdapterName.ytdlp,
                    url="https://cdn.example.test/audio.m4a",
                    title="Adele - Rolling in the Deep Official Audio",
                )
            ], []

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover_playable(
        "rolling in the deep"
    )

    assert response.mode == "stream"
    assert response.items[0].label == "Top playable match"
    assert response.items[0].source is not None


async def test_discover_metadata_failure_returns_warning():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            raise httpx.ConnectTimeout("timeout")

    class SourcesStub:
        async def resolve(self, _request):
            return []

    response = await DiscoveryService(MusicBrainzStub(), SourcesStub()).discover("anything")

    assert response.items == []
    assert response.warnings[0].code == "metadata_unavailable"


async def test_discover_returns_local_source_index_before_musicbrainz(tmp_path):
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            raise AssertionError("MusicBrainz should not be called for strong index hits")

    class SourcesStub:
        async def resolve_with_warnings(self, _request):
            raise AssertionError("yt-dlp should not be called for strong index hits")

    class SourceIndexStub:
        def search(self, query, scope=SearchScope.all):
            assert query == "roling in the dep"
            assert scope == SearchScope.songs
            return [
                SourceIndexEntry(
                    source_provider="ytmusic",
                    source_id="rYEDA3JcQqw",
                    source_url="https://music.youtube.com/watch?v=rYEDA3JcQqw",
                    title="Rolling in the Deep",
                    artist="Adele",
                    album="21",
                    duration_seconds=228,
                    confidence_score=93,
                    rank_reason="fuzzy source match",
                    source_kind="song",
                    parse_source="structured",
                )
            ]

        def upsert_many(self, _entries):
            raise AssertionError("upsert should not run for cached hits")

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("roling in the dep", scope=SearchScope.songs)

    assert response.mode == "stream"
    assert response.items[0].track.artist_label == "Adele"
    assert response.items[0].track.source_url == "https://music.youtube.com/watch?v=rYEDA3JcQqw"
    assert response.warnings == []


async def test_discover_source_first_does_not_surface_ytdlp_unavailable_warning():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, _query, scope=SearchScope.all, limit=12):
            return []

        async def source_search_with_warnings(self, _request, limit=12):
            raise AssertionError("yt-dlp source discovery should not run for text search")

    class SourceIndexStub:
        def search(self, _query):
            return []

        def upsert_many(self, _entries):
            pass

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("rolling in the deep")

    assert response.items == []
    assert response.warnings == []


async def test_discover_prefers_fresh_ytmusic_items_over_weaker_index_hits():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, _query, scope=SearchScope.all, limit=12):
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id="ytmusic:K0HSD_i2DvA",
                        title="Around The World",
                        artists=[{"name": "Daft Punk"}],
                        source_provider="ytmusic",
                        source_id="K0HSD_i2DvA",
                        source_url="https://music.youtube.com/watch?v=K0HSD_i2DvA",
                        source_kind="song",
                        source="ytmusic",
                    ),
                    label="YouTube Music",
                )
            ]

    class SourceIndexStub:
        def __init__(self):
            self.upserted = []

        def search(self, _query, scope=SearchScope.all):
            return [
                SourceIndexEntry(
                    source_provider="ytmusic",
                    source_id="rYEDA3JcQqw",
                    source_url="https://music.youtube.com/watch?v=rYEDA3JcQqw",
                    title="Rolling in the Deep",
                    artist="Adele",
                    duration_seconds=234,
                    confidence_score=71,
                    source_kind="song",
                    parse_source="structured",
                )
            ]

        def upsert_many(self, entries):
            self.upserted = entries

    source_index = SourceIndexStub()

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=source_index
    ).discover("daft punk around the world")

    assert response.items[0].track.artist_label == "Daft Punk"
    assert response.items[0].track.title == "Around The World"
    assert source_index.upserted[0].source_id == "K0HSD_i2DvA"


async def test_discover_uses_ytmusic_search_instead_of_old_index_hits_for_all_scope():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, query, scope=SearchScope.all, limit=12):
            assert query == "bella gims"
            assert scope == SearchScope.all
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id="ytmusic:56BRFlaxsGw",
                        title="Bella",
                        artists=[{"name": "Maitre Gims"}],
                        source_provider="ytmusic",
                        source_id="56BRFlaxsGw",
                        source_url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                        source_kind="song",
                        source="ytmusic",
                    ),
                    label="YouTube Music",
                )
            ]

    class SourceIndexStub:
        def __init__(self):
            self.upserted = []

        def search(self, _query, scope=SearchScope.all):
            return [
                SourceIndexEntry(
                    source_provider="ytmusic",
                    source_id="mira-bella",
                    source_url="https://music.youtube.com/watch?v=mira",
                    title="Bella",
                    artist="MIRA",
                    duration_seconds=173,
                    confidence_score=96,
                    source_kind="song",
                    parse_source="structured",
                )
            ]

        def upsert_many(self, entries):
            self.upserted = entries

    source_index = SourceIndexStub()

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=source_index
    ).discover("bella gims")

    assert response.items[0].track.artist_label == "Maitre Gims"
    assert response.items[0].track.title == "Bella"
    assert source_index.upserted[0].source_id == "56BRFlaxsGw"


async def test_discover_does_not_return_weak_index_hit_after_ytmusic_timeout():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, _query, scope=SearchScope.all, limit=12):
            raise TimeoutError("ytmusic timed out")

    class SourceIndexStub:
        def search(self, _query, scope=SearchScope.all):
            return [
                SourceIndexEntry(
                    source_provider="ytmusic",
                    source_id="mira-bella",
                    source_url="https://music.youtube.com/watch?v=mira",
                    title="Bella",
                    artist="MIRA",
                    duration_seconds=173,
                    confidence_score=74,
                    source_kind="song",
                    parse_source="structured",
                )
            ]

        def upsert_many(self, _entries):
            raise AssertionError("weak timed-out cache hits should not be upserted")

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("bella gims")

    assert response.items == []


async def test_discover_uses_broad_ytmusic_search_and_returns_many_items():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, query, scope=SearchScope.all, limit=12):
            assert query == "bella"
            assert scope == SearchScope.all
            assert limit == 12
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id=f"ytmusic:video-{index}",
                        title="Bella",
                        artists=[{"name": f"Artist {index}"}],
                        source_provider="ytmusic",
                        source_id=f"video-{index}",
                        source_url=f"https://music.youtube.com/watch?v=video-{index}",
                        source_kind="song",
                        source="ytmusic",
                    ),
                    label="YouTube Music",
                )
                for index in range(8)
            ]

    class SourceIndexStub:
        def search(self, _query, scope=SearchScope.all):
            return []

        def upsert_many(self, _entries):
            pass

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("bella")

    assert response.mode == "stream"
    assert len(response.items) == 8


async def test_discover_prefers_ytmusic_structured_results_over_generic_youtube():
    class MusicBrainzStub:
        async def search_tracks(self, _query):
            return []

    class SourcesStub:
        async def ytmusic_search(self, query, scope=SearchScope.all, limit=12):
            assert query == "bella gims"
            return [
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id="ytmusic:56BRFlaxsGw",
                        title="Bella",
                        artists=[{"name": "GIMS"}],
                        album={"title": "Subliminal"},
                        artwork_url="https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg",
                        source_provider="ytmusic",
                        source_id="56BRFlaxsGw",
                        source_url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                        source_kind="song",
                        source="ytmusic",
                    ),
                    label="YouTube Music",
                )
            ]

    class SourceIndexStub:
        def search(self, _query, scope=SearchScope.all):
            return []

        def upsert_many(self, _entries):
            pass

    response = await DiscoveryService(
        MusicBrainzStub(), SourcesStub(), source_index=SourceIndexStub()
    ).discover("bella gims")

    top = response.items[0].track
    assert top.title == "Bella"
    assert top.artist_label == "GIMS"
    assert top.album.title == "Subliminal"
    assert top.artwork_url == "https://i.ytimg.com/vi/56BRFlaxsGw/hqdefault.jpg"
    assert top.source_provider == "ytmusic"


def test_debug_search_endpoint_explains_ranking(client, monkeypatch):
    from app.main import app
    from app.services.source_index import SourceIndexEntry

    def fake_search(_query, scope=SearchScope.all):
        return [
            SourceIndexEntry(
                source_provider="youtube",
                source_id="rYEDA3JcQqw",
                source_url="https://www.youtube.com/watch?v=rYEDA3JcQqw",
                title="Rolling in the Deep",
                artist="Adele",
                confidence_score=94,
                rank_reason="artist exact-title",
            )
        ]

    monkeypatch.setattr(app.state.source_index, "search", fake_search)
    response = client.get("/api/debug/search?q=rolling%20in%20the%20deep")

    assert response.status_code == 200
    payload = response.json()
    assert payload["query"] == "rolling in the deep"
    assert "phase_timings_ms" in payload
    assert "result_source" in payload
    assert "providers_queried" in payload
    assert payload["source_index_hits"][0]["artist"] == "Adele"
    assert payload["source_index_hits"][0]["rank_reason"] == "artist exact-title"


def test_discover_endpoint_uses_metadata(client, monkeypatch):
    from app.main import app

    async def fake_search_tracks(_query):
        return [TrackMetadata(id="1", title="Track", artists=[{"name": "Artist"}])]

    async def fake_ytmusic_search(_query, scope=SearchScope.all, limit=12):
        return []

    monkeypatch.setattr(app.state.source_index, "search", lambda _query, scope=SearchScope.all: [])
    monkeypatch.setattr(app.state.sources, "ytmusic_search", fake_ytmusic_search)
    monkeypatch.setattr(app.state.musicbrainz, "search_tracks", fake_search_tracks)
    response = client.get("/api/discover?q=track")

    assert response.status_code == 200
    assert response.json()["items"][0]["track"]["title"] == "Track"


def test_discover_playable_endpoint(client, monkeypatch):
    from app.main import app

    async def fake_resolve_with_warnings(_request):
        return [
            SourceCandidate(
                adapter=AdapterName.ytdlp,
                url="https://cdn.example.test/audio.m4a",
                title="Track official audio",
            )
        ], []

    monkeypatch.setattr(app.state.sources, "resolve_with_warnings", fake_resolve_with_warnings)
    response = client.get("/api/discover/playable?q=track")

    assert response.status_code == 200
    assert response.json()["items"][0]["label"] == "Top playable match"
