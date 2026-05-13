# yt-dlp Unified Python Plan
## 2026-05-13 — Python yt-dlp everywhere

## Strategy

Use the **same** Python yt-dlp package on all platforms — no standalone
binary, no Dart port. Only packaging differs per platform.

| Platform | Python runtime | yt-dlp source | Call method |
|----------|---------------|---------------|-------------|
| Windows  | System Python  | pip / uv     | `python -m yt_dlp` |
| macOS    | System Python  | pip / uv     | `python -m yt_dlp` |
| Linux    | System Python  | pip / uv     | `python -m yt_dlp` |
| Android  | Chaquopy (embedded CPython 3.11) | pip in build.gradle | Kotlin → Python → yt_dlp |

## Why this works

yt-dlp IS Python. The standalone exe is just PyInstaller wrapping Python +
yt-dlp. Calling it via `python -m yt_dlp` uses the same code without the 15 MB
wrapper. On desktop, Python is a reasonable dependency for a music app. On
Android, Chaquopy has been shipping Python in apps since 2015.

## Phase 1: Desktop — call via Python

### Task 1: Update ytdlp.rs to use Python

**File:** `native/streambox_core/src/services/ytdlp.rs`

Replace hardcoded binary name with Python-based invocation:

```rust
#[cfg(not(target_os = "android"))]
const YTDLP_BINARY: &str = "python";

#[cfg(not(target_os = "android"))]
fn ytdlp_command() -> Command {
    let mut cmd = Command::new(YTDLP_BINARY);
    cmd.arg("-m").arg("yt_dlp");
    cmd
}

#[cfg(target_os = "android")]
fn ytdlp_command() -> Command {
    // On Android, yt-dlp is called via Chaquopy from Kotlin side.
    // This function should never be called on Android; if it is, return
    // an error immediately.
    panic!("yt-dlp must be called via Chaquopy on Android");
}
```

**Arguments stay the same** — just prepend `python -m yt_dlp`:

```rust
pub fn search(query: &str, limit: usize) -> Result<Vec<YtDlpTrack>, CoreError> {
    let search_query = format!("ytsearch{}:{}", limit, clean_query);
    let args = &[
        "-m", "yt_dlp",
        "--flat-playlist", "--dump-json", "--no-download",
        "--default-search", "ytsearch", &search_query,
    ];
    // ...
}
```

**is_available()** checks for Python + yt-dlp:

```rust
pub fn is_available() -> bool {
    Command::new("python")
        .args(["-m", "yt_dlp", "--version"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
```

### Task 2: Update tests

Remove tests that spawn `ping`/`sleep` (shell commands) and replace with
Python-based tests:

```rust
#[test]
fn test_ytdlp_available() {
    // Verifies python -m yt_dlp --version works
    assert!(is_available());
}
```

### Task 3: Add Python version check to diagnostics

Update `RuntimeDebugResponse` to include Python version:

```rust
struct RuntimeDebugResponse {
    api_version: String,
    ytdlp_available: bool,
    python_version: String,     // NEW
}
```

## Phase 2: Android — Chaquopy

### Task 4: Add Chaquopy Gradle plugin

**File:** `frontend/android/build.gradle.kts` (top-level)

```kotlin
plugins {
    id("com.chaquo.python") version "17.0.0" apply false
}
```

**File:** `frontend/android/app/build.gradle.kts` (module-level)

```kotlin
plugins {
    id("com.chaquo.python")
}

android {
    defaultConfig {
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }
}

chaquopy {
    defaultConfig {
        pip {
            install("yt-dlp")
        }
    }
}
```

### Task 5: Create Android yt-dlp bridge

**File:** `frontend/android/app/src/main/kotlin/com/vehicoule/streambox/YtDlpBridge.kt`

```kotlin
class YtDlpBridge {
    private val pyModule = Python.getInstance().getModule("yt_dlp")

    fun search(query: String, limit: Int): String {
        // Call yt-dlp search from Python, return JSON
        val result = pyModule.callAttr("YoutubeDL", mapOf(
            "quiet" to true,
            "extract_flat" to true,
            "default_search" to "ytsearch"
        )).callAttr("extract_info", "ytsearch$limit:$query", false)
        return result.toString()
    }

    fun resolve(url: String): String {
        val result = pyModule.callAttr("YoutubeDL", mapOf(
            "quiet" to true,
            "format" to "bestaudio/best"
        )).callAttr("extract_info", url, false)
        return result.toString()
    }
}
```

### Task 6: Wire Android bridge to Flutter

**File:** `frontend/lib/src/core/rust_core_client.dart`

On Android, `resolve()` and `discoverPlayable()` call the Kotlin bridge
via MethodChannel instead of going through Rust FFI:

```dart
Future<ResolveResponse> resolve(TrackMetadata track, {...}) async {
    if (Platform.isAndroid) {
        final json = await _channel.invokeMethod('ytdlp_resolve', {
            'url': track.sourceUrl ?? track.id,
        });
        return ResolveResponse.fromJson(jsonDecode(json));
    }
    // Desktop: use Rust FFI as before
    return nativeCore.ytdlpResolveJson({...});
}
```

## Phase 3: Cross-platform testing

### Task 7: Add Android integration tests

- Test Chaquopy Python → yt-dlp call on Android emulator
- Test fallback when Python unavailable

### Task 8: Desktop CI

- Add Python to CI runner dependencies
- `pip install yt-dlp` or `uv tool install yt-dlp` in CI setup
- Run yt-dlp tests in CI on all desktop platforms

## Execution order

| Task | Platform | Depends on |
|------|----------|-----------|
| 1 | Desktop | None |
| 2 | Desktop | Task 1 |
| 3 | Desktop | Task 1 |
| 4 | Android | None |
| 5 | Android | Task 4 |
| 6 | Both (Flutter) | Tasks 1, 5 |
| 7 | Android | Tasks 4-6 |
| 8 | Desktop CI | Task 1 |

## Trade-offs

| Aspect | Python approach | Standalone binary |
|--------|----------------|-------------------|
| Android support | Chaquopy (~15 MB) | None |
| Desktop dep | Python 3.8+ + pip | Nothing |
| Binary size overhead | 0 (uses system Python) | +15 MB per platform |
| Build complexity | Chaquopy Gradle setup | CMake copy step |
| yt-dlp updates | `pip install -U yt-dlp` / `yt-dlp -U` | Auto-download exe |
| Same code everywhere | Yes | No (Android uses Dart port) |
| Antivirus risk | None (no bundled exe) | PyInstaller false positives |
