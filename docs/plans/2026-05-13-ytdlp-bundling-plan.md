# yt-dlp Multi-Platform Plan — Final
## 2026-05-13

Based on [Spotube](https://github.com/krtirtho/spotube)'s proven approach:
yt-dlp on desktop, NewPipe Extractor on Android.

## Strategy

| Platform | Engine | How |
|----------|--------|-----|
| Windows  | yt-dlp | `yt_dlp_dart` Dart package (wraps yt-dlp binary) |
| macOS    | yt-dlp | same |
| Linux    | yt-dlp | same |
| Android  | NewPipe Extractor | `flutter_new_pipe_extractor` plugin |
| iOS      | NewPipe Extractor | same (if we add iOS later) |

Both engines implement the same Dart interface — Flutter picks one at startup
based on `Platform.isAndroid`.

## Why NewPipe on Android instead of Chaquopy + Python

NewPipe Extractor is a Java library purpose-built for Android:
- No Python runtime needed (~30 MB saved vs Chaquopy)
- No subprocess restrictions (native Java, runs in-process)
- Maintained by [TeamNewPipe](https://github.com/TeamNewPipe/NewPipeExtractor)
  (30K+ GitHub stars, active since 2015)
- Supports YouTube, YouTube Music, SoundCloud, Bandcamp, PeerTube
- `flutter_new_pipe_extractor` wraps it for Flutter

## Architecture

```
┌────────────────────────────────────────────┐
│              Flutter (Dart)                 │
│                                             │
│  abstract class TrackResolver {             │
│    Future<List<Track>> search(q)            │
│    Future<StreamUrl> resolve(track)         │
│  }                                         │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐ │
│  │ YtDlpResolver    │  │ NewPipeResolver │ │
│  │ (desktop)        │  │ (mobile)        │ │
│  │ uses yt_dlp_dart │  │ uses flutter_   │ │
│  │ → subprocess     │  │ new_pipe_extr.  │ │
│  └──────────────────┘  └─────────────────┘ │
└────────────────────────────────────────────┘
```

## Phase 1: Desktop — yt-dlp via yt_dlp_dart

### Task 1: Add yt_dlp_dart dependency

**File:** `frontend/pubspec.yaml`

```yaml
dependencies:
  yt_dlp_dart: ^1.1.0
```

Run `flutter pub get`.

### Task 2: Create YtDlpResolver

**File:** `frontend/lib/src/resolver/yt_dlp_resolver.dart`

```dart
import 'package:yt_dlp_dart/yt_dlp_dart.dart';

class YtDlpResolver implements TrackResolver {
  static Future<bool> isAvailable() async =>
      await YtDlp.instance.checkAvailableInPath();

  @override
  Future<List<TrackMetadata>> search(String query, {int limit = 10}) async {
    final output = await YtDlp.instance.extractInfoString(
      'ytsearch$limit:$query',
      extraArgs: ['--flat-playlist', '--no-playlist', '--quiet'],
    );
    // Parse JSON lines → List<TrackMetadata>
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    final info = await YtDlp.instance.extractInfo(
      url,
      extraArgs: ['--format', 'bestaudio/best', '--quiet'],
    ) as Map<String, dynamic>;
    return SourceCandidate(
      adapter: 'ytdlp',
      url: info['url'],
      title: info['title'],
      durationSeconds: (info['duration'] as num?)?.toDouble(),
    );
  }
}
```

### Task 3: Switch Rust FFI yt-dlp → Dart resolver (desktop)

In `RustCoreClient` or `HomeScreen`, use `YtDlpResolver` instead of
`nativeCore.ytdlpSearchJson()` / `nativeCore.ytdlpResolveJson()`.

The Rust FFI yt-dlp endpoints become **deprecated** — kept for backward
compatibility, not called by new code paths.

## Phase 2: Android — NewPipe Extractor

### Task 4: Add flutter_new_pipe_extractor dependency

**File:** `frontend/pubspec.yaml`

```yaml
dependencies:
  flutter_new_pipe_extractor: ^0.4.0
```

### Task 5: Create NewPipeResolver

**File:** `frontend/lib/src/resolver/newpipe_resolver.dart`

```dart
import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart';

class NewPipeResolver implements TrackResolver {
  final _extractor = NewPipeExtractor();

  @override
  Future<List<TrackMetadata>> search(String query, {int limit = 10}) async {
    final results = await _extractor.search(
      query,
      filter: SearchFilter.stream,  // YouTube Music
      contentFilter: [ContentFilter.music_songs],
    );
    return results.items.take(limit).map(_toTrack).toList();
  }

  @override
  Future<SourceCandidate> resolve(String url) async {
    final info = await _extractor.getStreamInfo(url);
    return SourceCandidate(
      adapter: 'newpipe',
      url: info.audioStreams!.first.url,
      title: info.name,
      durationSeconds: info.duration?.inSeconds.toDouble(),
    );
  }
}
```

### Task 6: Platform resolver selection

**File:** `frontend/lib/src/resolver/resolver.dart`

```dart
import 'dart:io' show Platform;

TrackResolver createResolver() {
  if (Platform.isAndroid || Platform.isIOS) {
    return NewPipeResolver();
  }
  return YtDlpResolver();
}
```

Call `createResolver()` in `main.dart` and pass it down instead of routing
through Rust FFI for search/resolve.

## Phase 3: Cleanup

### Task 7: Mark Rust yt-dlp FFI as deprecated

Add `#[deprecated]` to:
- `streambox_ytdlp_search_json`
- `streambox_ytdlp_resolve_json`
- `streambox_ytdlp_available_json`

Keep them compiling but add comment pointing to Dart-side resolver.

### Task 8: Update diagnostics

`runtimeDebug().ytdlpAvailable` now checks Dart-side resolver availability:
- Desktop: `YtDlpResolver.isAvailable()`
- Android: `true` (NewPipe is always available)

## Execution order

| Task | What | Approx time |
|------|------|-------------|
| 1 | Add yt_dlp_dart dep | 5 min |
| 2 | YtDlpResolver | 30 min |
| 3 | Switch desktop calls | 20 min |
| 4 | Add flutter_new_pipe_extractor dep | 5 min |
| 5 | NewPipeResolver | 30 min |
| 6 | Platform selection | 10 min |
| 7 | Deprecate Rust FFI | 10 min |
| 8 | Update diagnostics | 10 min |

## Comparison with previous plans

| Aspect | Chaquopy plan | This plan |
|--------|--------------|-----------|
| Android APK size | +30 MB (Python) | +2 MB (NewPipe) |
| Android playback | yt-dlp via Python | NewPipe native Java |
| Desktop playback | yt-dlp via Rust subprocess | yt-dlp via Dart subprocess |
| Proven approach | No | Yes (Spotube 5K+ stars) |
| Maintenance | Own Python bridge code | Upstream packages |
| Complexity | High (Chaquopy + Kotlin bridge) | Low (two Dart packages) |
