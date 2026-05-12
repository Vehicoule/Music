import json
import subprocess

from app.core.config import Settings
from app.schemas import (
    AdapterCapability,
    AdapterName,
    ResolveRequest,
    ResolverDebugAttempt,
    SourceCandidate,
    TrackMetadata,
)
from app.sources.registry import SourceRegistry
from app.sources.internet_radio import InternetRadioAdapter
from app.sources.ytdlp import YtDlpAdapter


def test_ytdlp_payload_to_candidate_prefers_audio_format():
    adapter = YtDlpAdapter(Settings())
    candidate = adapter._payload_to_candidate(
        {
            "title": "Resolved",
            "duration": 42,
            "formats": [
                {"url": "https://example.test/video.mp4", "acodec": "none", "abr": 0},
                {"url": "https://example.test/audio.m4a", "acodec": "mp4a", "abr": 128},
            ],
        }
    )
    assert candidate is not None
    assert candidate.url == "https://example.test/audio.m4a"


def test_ytdlp_payload_to_candidate_uses_requested_download_headers():
    adapter = YtDlpAdapter(Settings())
    candidate = adapter._payload_to_candidate(
        {
            "title": "Resolved",
            "duration": 42,
            "requested_downloads": [
                {
                    "url": "https://example.test/audio.webm",
                    "ext": "webm",
                    "http_headers": {"User-Agent": "yt-dlp"},
                }
            ],
        }
    )

    assert candidate is not None
    assert candidate.url == "https://example.test/audio.webm"
    assert candidate.headers["User-Agent"] == "yt-dlp"


def test_ytdlp_payload_to_candidates_sorts_search_entries():
    adapter = YtDlpAdapter(Settings())
    request = ResolveRequest(
        track=TrackMetadata(
            id="x",
            title="Rolling in the Deep",
            artists=[{"name": "Adele"}],
            length_ms=228000,
        )
    )

    candidates = adapter._payload_to_candidates(
        {
            "entries": [
                {
                    "title": "Rolling in the Deep piano cover",
                    "duration": 228,
                    "url": "https://example.test/cover.webm",
                    "http_headers": {"User-Agent": "yt-dlp"},
                },
                {
                    "title": "Adele - Rolling in the Deep Official Audio",
                    "duration": 228,
                    "url": "https://example.test/official.webm",
                    "http_headers": {"User-Agent": "yt-dlp"},
                },
            ]
        },
        request,
    )

    assert candidates[0].url == "https://example.test/official.webm"


def test_ytdlp_metadata_targets_include_fallback_variants():
    adapter = YtDlpAdapter(Settings())
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="Song", artists=[{"name": "Artist"}])
    )

    targets = adapter._targets(request)

    assert targets[0] == 'ytsearch3:"Song" "Artist" official audio'
    assert 'ytsearch2:"Artist" - "Song"' in targets
    assert 'ytsearch2:"Song"' in targets


def test_ytdlp_source_search_targets_are_broad_and_do_not_inject_youtube_artist():
    adapter = YtDlpAdapter(Settings())
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="bella gims", artists=[])
    )

    targets = adapter._source_search_targets(request, limit=12)

    assert targets[0] == "ytsearch12:bella gims"
    assert all("YouTube" not in target for target in targets)
    assert any("official audio" in target for target in targets)


async def test_ytdlp_source_search_collects_more_than_three_candidates(monkeypatch, tmp_path):
    python = tmp_path / "python.exe"
    python.write_text("", encoding="utf-8")
    adapter = YtDlpAdapter(Settings(ytdlp_python=str(python)))
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="bella", artists=[])
    )

    async def fake_resolve_source_target(target, _request, timeout=None):
        if not target.startswith("ytsearch12:"):
            return [], None
        return [
            SourceCandidate(
                adapter=AdapterName.ytdlp,
                url=f"https://cdn.example.test/{index}.m4a",
                title=f"Artist {index} - Bella",
                source_provider="youtube",
                source_id=f"video-{index}",
                source_url=f"https://www.youtube.com/watch?v=video-{index}",
            )
            for index in range(8)
        ], None

    monkeypatch.setattr(adapter, "_resolve_source_target", fake_resolve_source_target)

    candidates = await adapter.source_search(request, limit=12)

    assert len(candidates) == 8


async def test_ytdlp_source_search_uses_flat_metadata_without_stream_extraction(monkeypatch, tmp_path):
    python = tmp_path / "python.exe"
    python.write_text("", encoding="utf-8")
    adapter = YtDlpAdapter(Settings(ytdlp_python=str(python)))
    request = ResolveRequest(track=TrackMetadata(id="x", title="bella", artists=[]))

    def fake_run(command, *, capture_output, timeout, check):
        assert "--flat-playlist" in command
        assert "--format" not in command
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout=json.dumps(
                {
                    "entries": [
                        {
                            "id": "56BRFlaxsGw",
                            "title": "Maitre Gims - Bella",
                            "duration": 278,
                            "url": "56BRFlaxsGw",
                        }
                    ]
                }
            ).encode("utf-8"),
            stderr=b"",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    candidates = await adapter.source_search(request, limit=12)

    assert candidates[0].url == "https://www.youtube.com/watch?v=56BRFlaxsGw"
    assert candidates[0].source_url == "https://www.youtube.com/watch?v=56BRFlaxsGw"


async def test_source_registry_source_search_with_warnings():
    class SearchAdapter:
        last_warning = None

        async def capability(self):
            return AdapterCapability(name=AdapterName.ytdlp, enabled=True, healthy=True, label="Search")

        async def resolve(self, _request):
            return []

        async def source_search(self, _request, limit=12):
            assert limit == 12
            return [
                SourceCandidate(
                    adapter=AdapterName.ytdlp,
                    url="https://cdn.example.test/audio.m4a",
                    title="Artist - Track",
                )
            ]

    registry = SourceRegistry(Settings(enable_ytdlp=False, enable_direct_url=False))
    registry.adapters = {AdapterName.ytdlp: SearchAdapter()}

    candidates, warnings = await registry.source_search_with_warnings(
        ResolveRequest(track=TrackMetadata(id="x", title="Track", artists=[])),
        limit=12,
    )

    assert candidates[0].title == "Artist - Track"
    assert warnings == []


async def test_source_registry_continues_to_ytdlp_when_ytmusic_results_are_thin():
    calls = []

    class YtMusicSearchAdapter:
        last_warning = None

        async def capability(self):
            return AdapterCapability(name=AdapterName.ytmusic, enabled=True, healthy=True, label="YT Music")

        async def resolve(self, _request):
            return []

        async def source_search(self, _request, limit=12):
            calls.append("ytmusic")
            return [
                SourceCandidate(
                    adapter=AdapterName.ytmusic,
                    url=f"https://music.youtube.com/watch?v=song-{index}",
                    title=f"Song {index}",
                    source_provider="ytmusic",
                    source_id=f"song-{index}",
                    source_url=f"https://music.youtube.com/watch?v=song-{index}",
                    source_kind="song",
                    parse_source="structured",
                )
                for index in range(3)
            ]

    class YtDlpSearchAdapter:
        last_warning = None

        async def capability(self):
            return AdapterCapability(name=AdapterName.ytdlp, enabled=True, healthy=True, label="yt-dlp")

        async def resolve(self, _request):
            return []

        async def source_search(self, _request, limit=12):
            calls.append("ytdlp")
            return [
                SourceCandidate(
                    adapter=AdapterName.ytdlp,
                    url=f"https://www.youtube.com/watch?v=video-{index}",
                    title=f"Video {index}",
                    source_provider="youtube",
                    source_id=f"video-{index}",
                    source_url=f"https://www.youtube.com/watch?v=video-{index}",
                    source_kind="video",
                    parse_source="parsed_title",
                )
                for index in range(8)
            ]

    registry = SourceRegistry(Settings(enable_ytdlp=False, enable_direct_url=False))
    registry.adapters = {
        AdapterName.ytmusic: YtMusicSearchAdapter(),
        AdapterName.ytdlp: YtDlpSearchAdapter(),
    }

    candidates, warnings = await registry.source_search_with_warnings(
        ResolveRequest(track=TrackMetadata(id="x", title="call", artists=[])),
        limit=12,
    )

    assert calls == ["ytmusic", "ytdlp"]
    assert len(candidates) == 11
    assert candidates[0].source_provider == "ytmusic"
    assert candidates[3].source_provider == "youtube"
    assert warnings == []


async def test_source_registry_skips_ytdlp_when_ytmusic_has_enough_results():
    calls = []

    class YtMusicSearchAdapter:
        last_warning = None

        async def capability(self):
            return AdapterCapability(name=AdapterName.ytmusic, enabled=True, healthy=True, label="YT Music")

        async def resolve(self, _request):
            return []

        async def source_search(self, _request, limit=12):
            calls.append("ytmusic")
            return [
                SourceCandidate(
                    adapter=AdapterName.ytmusic,
                    url=f"https://music.youtube.com/watch?v=song-{index}",
                    title=f"Song {index}",
                    source_provider="ytmusic",
                    source_id=f"song-{index}",
                    source_url=f"https://music.youtube.com/watch?v=song-{index}",
                    source_kind="song",
                    parse_source="structured",
                )
                for index in range(8)
            ]

    class YtDlpSearchAdapter:
        async def capability(self):
            return AdapterCapability(name=AdapterName.ytdlp, enabled=True, healthy=True, label="yt-dlp")

        async def resolve(self, _request):
            return []

        async def source_search(self, _request, limit=12):
            calls.append("ytdlp")
            return []

    registry = SourceRegistry(Settings(enable_ytdlp=False, enable_direct_url=False))
    registry.adapters = {
        AdapterName.ytmusic: YtMusicSearchAdapter(),
        AdapterName.ytdlp: YtDlpSearchAdapter(),
    }

    candidates, _warnings = await registry.source_search_with_warnings(
        ResolveRequest(track=TrackMetadata(id="x", title="call", artists=[])),
        limit=12,
    )

    assert calls == ["ytmusic"]
    assert len(candidates) == 8


async def test_ytdlp_capability_accepts_python_module_launcher(tmp_path):
    python = tmp_path / "python.exe"
    python.write_text("", encoding="utf-8")
    adapter = YtDlpAdapter(Settings(ytdlp_python=str(python), ytdlp_binary="blocked.exe"))

    capability = await adapter.capability()

    assert capability.healthy is True
    assert "python module" in (capability.notes or "")


async def test_ytdlp_resolve_target_uses_threaded_subprocess(monkeypatch):
    payload = {
        "id": "video-1",
        "webpage_url": "https://www.youtube.com/watch?v=video-1",
        "title": "Artist - Song Official Audio",
        "duration": 180,
        "requested_downloads": [
            {
                "url": "https://cdn.example.test/audio.m4a",
                "ext": "m4a",
                "http_headers": {"User-Agent": "yt-dlp"},
            }
        ],
    }

    def fake_run(command, *, capture_output, timeout, check):
        assert command[0] == "yt-dlp"
        assert capture_output is True
        assert check is False
        assert timeout == 15.0
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout=json.dumps(payload).encode("utf-8"),
            stderr=b"",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)
    adapter = YtDlpAdapter(Settings(ytdlp_binary="yt-dlp"))
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="Song", artists=[{"name": "Artist"}])
    )

    candidates, warning = await adapter._resolve_target('ytsearch1:"Song"', request)

    assert warning is None
    assert candidates[0].url == "https://cdn.example.test/audio.m4a"
    assert candidates[0].source_id == "video-1"


async def test_ytdlp_resolve_target_uses_python_module_command(monkeypatch, tmp_path):
    python = tmp_path / "python.exe"
    python.write_text("", encoding="utf-8")

    def fake_run(command, *, capture_output, timeout, check):
        assert command[:3] == [str(python), "-m", "yt_dlp"]
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout=json.dumps(
                {
                    "id": "video-1",
                    "webpage_url": "https://www.youtube.com/watch?v=video-1",
                    "title": "Artist - Song",
                    "duration": 180,
                    "url": "https://cdn.example.test/audio.m4a",
                }
            ).encode("utf-8"),
            stderr=b"",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)
    adapter = YtDlpAdapter(Settings(ytdlp_python=str(python)))
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="Song", artists=[{"name": "Artist"}])
    )

    candidates, warning = await adapter._resolve_target('ytsearch1:"Song"', request)

    assert warning is None
    assert candidates[0].source_id == "video-1"


async def test_radio_adapter_matches_station():
    adapter = InternetRadioAdapter()
    request = ResolveRequest(
        track=TrackMetadata(id="x", title="SomaFM Groove Salad", artists=[{"name": "SomaFM"}])
    )
    candidates = await adapter.resolve(request)
    assert candidates
    assert candidates[0].is_live is True


async def test_source_registry_formats_blank_adapter_errors():
    class BrokenAdapter:
        async def capability(self):
            return AdapterCapability(name=AdapterName.ytdlp, enabled=True, healthy=True, label="Broken")

        async def resolve(self, _request):
            raise RuntimeError()

    registry = SourceRegistry(Settings(enable_ytdlp=False, enable_direct_url=False))
    registry.adapters = {AdapterName.ytdlp: BrokenAdapter()}

    _, warnings = await registry.resolve_with_warnings(
        ResolveRequest(track=TrackMetadata(id="x", title="Song", artists=[{"name": "Artist"}]))
    )

    assert warnings[0].message
    assert "RuntimeError" in warnings[0].message


async def test_source_registry_resolver_debug_attempts():
    class DebugAdapter:
        async def capability(self):
            return AdapterCapability(name=AdapterName.ytdlp, enabled=True, healthy=True, label="Debug")

        async def resolve(self, _request):
            return []

        async def resolve_debug(self, _request):
            return [
                ResolverDebugAttempt(
                    adapter=AdapterName.ytdlp,
                    target='ytsearch3:"Song" "Artist"',
                    candidate_count=1,
                    first_title="Song - Artist",
                    first_url_host="example.test",
                    headers_present=True,
                )
            ]

    registry = SourceRegistry(Settings(enable_ytdlp=False, enable_direct_url=False))
    registry.adapters = {AdapterName.ytdlp: DebugAdapter()}

    attempts = await registry.resolve_debug(
        ResolveRequest(track=TrackMetadata(id="x", title="Song", artists=[{"name": "Artist"}]))
    )

    assert attempts[0].candidate_count == 1
    assert attempts[0].headers_present is True
