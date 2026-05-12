from app.schemas import PlaybackItem, TrackMetadata


def sample_item() -> dict:
    track = TrackMetadata(id="recording-1", title="Test Song", artists=[{"name": "Test Artist"}])
    item = PlaybackItem(track=track)
    return item.model_dump(mode="json")


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_sources(client):
    response = client.get("/api/sources")
    assert response.status_code == 200
    names = {item["name"] for item in response.json()}
    assert "direct_url" in names
    assert "internet_radio" in names


def test_playlist_crud(client):
    create = client.post("/api/playlists", json={"name": "Favorites", "tracks": [sample_item()]})
    assert create.status_code == 201
    playlist = create.json()
    assert playlist["name"] == "Favorites"
    assert len(playlist["tracks"]) == 1

    update = client.put(
        f"/api/playlists/{playlist['id']}",
        json={"name": "Road", "tracks": []},
    )
    assert update.status_code == 200
    assert update.json()["name"] == "Road"
    assert update.json()["tracks"] == []


def test_favorites_and_history(client):
    item = sample_item()
    favorite = client.post("/api/favorites", json={"item": item})
    assert favorite.status_code == 201
    assert client.get("/api/favorites").json()[0]["item"]["track"]["title"] == "Test Song"

    history = client.post("/api/history", json={"item": item})
    assert history.status_code == 201
    assert client.get("/api/history").json()[0]["track"]["title"] == "Test Song"


def test_resolve_returns_warnings(client, monkeypatch):
    from app.main import app
    from app.schemas import DiscoverWarning

    async def fake_resolve_with_warnings(_request):
        return [], [DiscoverWarning(code="yt_dlp_warning", message="resolver failed")]

    monkeypatch.setattr(app.state.sources, "resolve_with_warnings", fake_resolve_with_warnings)
    response = client.post("/api/resolve", json={"track": sample_item()["track"]})

    assert response.status_code == 200
    assert response.json()["warnings"][0]["message"] == "resolver failed"


def test_runtime_debug_endpoint(client):
    response = client.get("/api/debug/runtime")

    assert response.status_code == 200
    payload = response.json()
    assert payload["api_version"] == "0.3.0"
    assert payload["expected_ytdlp_path"].endswith(".venv\\Scripts\\yt-dlp.exe")
    assert isinstance(payload["venv_scripts_on_path"], bool)
    assert payload["ytdlp_launch_mode"] in {"binary", "python_module"}
    assert "PATH" not in payload


def test_resolve_debug_endpoint(client, monkeypatch):
    from app.main import app
    from app.schemas import AdapterName, ResolverDebugAttempt

    async def fake_resolve_debug(_request):
        return [
            ResolverDebugAttempt(
                adapter=AdapterName.ytdlp,
                target='ytsearch3:"Track"',
                candidate_count=1,
                first_title="Track official audio",
                first_url_host="googlevideo.example",
                headers_present=True,
            )
        ]

    monkeypatch.setattr(app.state.sources, "resolve_debug", fake_resolve_debug)
    response = client.post(
        "/api/resolve/debug",
        json={"track": {"id": "1", "title": "Track", "artists": [{"name": "Artist"}]}},
    )

    assert response.status_code == 200
    assert response.json()["attempts"][0]["first_title"] == "Track official audio"


def test_album_detail_endpoint(client, monkeypatch):
    from app.main import app
    from app.schemas import AlbumDetail, DiscoverItem, DiscoverKind, SearchMode

    async def fake_album_detail(_browse_id):
        return AlbumDetail(
            title="Subliminal",
            tracks=[
                DiscoverItem(
                    mode=SearchMode.stream,
                    kind=DiscoverKind.song,
                    track=TrackMetadata(
                        id="ytmusic:56BRFlaxsGw",
                        title="Bella",
                        artists=[],
                        source="ytmusic",
                        source_url="https://music.youtube.com/watch?v=56BRFlaxsGw",
                    ),
                    label="YouTube Music",
                )
            ],
        )

    monkeypatch.setattr(app.state.sources, "ytmusic_album_detail", fake_album_detail)

    response = client.get("/api/albums/MPREb_album")

    assert response.status_code == 200
    assert response.json()["title"] == "Subliminal"
    assert response.json()["tracks"][0]["track"]["title"] == "Bella"


def test_artist_detail_endpoint(client, monkeypatch):
    from app.main import app
    from app.schemas import ArtistDetail, DetailSection

    async def fake_artist_detail(_browse_id):
        return ArtistDetail(
            name="GIMS",
            sections=[DetailSection(label="Top songs", items=[])],
        )

    monkeypatch.setattr(app.state.sources, "ytmusic_artist_detail", fake_artist_detail)

    response = client.get("/api/artists/UC-gims")

    assert response.status_code == 200
    assert response.json()["name"] == "GIMS"
    assert response.json()["sections"][0]["label"] == "Top songs"
