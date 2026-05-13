# Multi-Engine Streaming Plan
## 2026-05-13 — adapted from Spotube's proven architecture

Based on [Spotube](https://github.com/krtirtho/spotube)'s 3-engine approach.

## Architecture

```
abstract interface class TrackResolver {
  Future<List<Track>> search(String query);
  Future<SourceCandidate> resolve(String urlOrId);
}

     ┌─────────────────┐
     │  TrackResolver   │
     └────────┬────────┘
              │
   ┌──────────┼──────────┐
   │          │          │
   ▼          ▼          ▼
YtDlpEngine  NewPipe    YouTubeExplode
(desktop)    (mobile)   (fallback)

Rust FFI     flutter_   youtube_explode
→ yt-dlp     newpipe_   _dart
             extractor   (pure Dart)
```

## Engines

### 1. YtDlpEngine — Desktop (Rust FFI)

Already built. Our `streambox_ytdlp_search_json` / `streambox_ytdlp_resolve_json`
FFI endpoints. Wraps them in the `TrackResolver` interface.

```dart
class YtDlpEngine implements TrackResolver {
  static bool get isAvailable => Platform.isWindows ||
      Platform.isMacOS || Platform.isLinux;

  @override
  Future<List<DiscoverItem>> search(String query) async {
    final response = await nativeCore.ytdlpSearchJson({
      'query': query, 'limit': 15,
    });
    // parse → List<DiscoverItem>
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    final response = await nativeCore.ytdlpResolveJson({'url': url});
    // parse → SourceCandidate
  }
}
```

### 2. NewPipeEngine — Android

New: wraps `flutter_new_pipe_extractor` plugin.

```dart
class NewPipeEngine implements TrackResolver {
  static bool get isAvailable => Platform.isAndroid;

  @override
  Future<List<DiscoverItem>> search(String query) async {
    final results = await NewPipeExtractor.search(
      query,
      contentFilters: [SearchContentFilters.musicSongs],
    );
    // parse → List<DiscoverItem>
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    final info = await NewPipeExtractor.getVideoInfo(url);
    final stream = info.audioStreams.first;
    return SourceCandidate(
      adapter: 'newpipe',
      url: stream.content,
      title: info.name,
      durationSeconds: info.duration.toDouble(),
    );
  }
}
```

### 3. YouTubeExplodeEngine — Universal fallback

Optional. `youtube_explode_dart` is pure Dart, works everywhere with zero
native deps. Useful if both yt-dlp and NewPipe fail.

```dart
class YouTubeExplodeEngine implements TrackResolver {
  static bool get isAvailable => true; // always

  // Uses youtube_explode_dart package
}
```

## Engine selection

No user preference UI needed. Auto-select based on platform:

```dart
TrackResolver createResolver(NativeCore nativeCore) {
  if (Platform.isAndroid) return NewPipeEngine();
  return YtDlpEngine(nativeCore);
}
```

Discovery stays in Rust. Only search/resolve routes through engines.

## Implementation

### Phase 1: Interface + desktop (P0)

| # | Task | Files |
|---|------|-------|
| 1 | Define `TrackResolver` interface | `lib/src/resolver/track_resolver.dart` |
| 2 | `YtDlpEngine` wraps existing Rust FFI | `lib/src/resolver/yt_dlp_engine.dart` |
| 3 | Wire `HomeScreen` to use `TrackResolver` | `lib/src/screens/home_screen.dart` |
| 4 | Deprecate `discoverPlayable()` on RustCoreClient | `lib/src/core/rust_core_client.dart` |
| 5 | `pubspec.yaml` — no new deps needed | `pubspec.yaml` |

### Phase 2: Android (P1)

| # | Task | Files |
|---|------|-------|
| 6 | Add `flutter_new_pipe_extractor: ^0.4.0` | `pubspec.yaml` |
| 7 | `NewPipeEngine` implementation | `lib/src/resolver/newpipe_engine.dart` |
| 8 | Platform-based resolver factory | `lib/src/resolver/resolver_factory.dart` |
| 9 | Android manifest permissions | `android/app/src/main/AndroidManifest.xml` |

### Phase 3: Polish (P2)

| # | Task | Files |
|---|------|-------|
| 10 | Add `youtube_explode_dart` fallback | `pubspec.yaml`, new engine file |
| 11 | Update diagnostics to show active engine | `lib/src/screens/home_screen.dart` |
| 12 | Remove old `streambox_ytdlp_*` deprecation warnings | `native/streambox_core/src/ffi.rs` |

## Dependencies

| Package | Size | Platform | Purpose |
|---------|------|----------|---------|
| `flutter_new_pipe_extractor` | ~2 MB | Android | YouTube/YouTube Music search + stream extraction |
| `youtube_explode_dart` | ~500 KB | All | Pure Dart YouTube client (fallback) |
| *(none new for desktop)* | 0 | Desktop | Existing Rust FFI → yt-dlp |

## What stays in Rust

Rust core keeps everything EXCEPT yt-dlp search/resolve. Those move to Dart
engines. Rust still handles:

- SQLite database (playlists, favorites, history)
- Source index (FTS5)
- MusicBrainz metadata
- ListenBrainz popularity
- Unified discovery (`discover()`) — uses source index + MusicBrainz only
- Health diagnostics
- Platform info

## What moves to Dart

Only two operations: `search()` and `resolve()`. These were always external
process calls from Rust anyway — moving them to Dart puts them closer to the
platform layer where Android can swap in NewPipe.

## Rust FFI changes

Remove 3 endpoints:
- ~~`streambox_ytdlp_search_json`~~ → Dart `YtDlpEngine.search()`
- ~~`streambox_ytdlp_resolve_json`~~ → Dart `YtDlpEngine.resolve()`
- ~~`streambox_ytdlp_available_json`~~ → replaced by engine availability check

Keep `ytdlp.rs` service module (still used by `discovery.rs` internally), but
remove the FFI wrappers.

`discover()` in `discovery.rs` currently calls yt-dlp as one phase of a
3-phase pipeline. Update it to skip the yt-dlp phase — Dart handles
playable search separately.

## Execution order

1. Phase 1 first (desktop-only, no new deps, 5 tasks)
2. Test on Windows — search + resolve still work
3. Phase 2 (Android, 4 tasks)
4. Test on Android emulator
5. Phase 3 (fallback engine + polish)

## Test plan

- Desktop: `flutter test` — YtDlpEngine.search/resolve with mock
- Android: emulator — NewPipeEngine.search/resolve with real API
- Rust: `cargo test` — verify discover still works without yt-dlp phase
