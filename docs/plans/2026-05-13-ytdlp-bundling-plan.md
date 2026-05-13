# yt-dlp Multi-Platform Availability Plan
## 2026-05-13 (revised for Windows/macOS/Linux/Android)

## Problem

yt-dlp is required for playback resolution but is not bundled. Must work
across 4 platforms with different constraints:

| Platform | yt-dlp binary | Subprocess | Constraints |
|----------|--------------|------------|-------------|
| Windows  | `yt-dlp.exe` (PyInstaller, 15 MB) | Yes | Works |
| macOS    | `yt-dlp_macos` (universal2, 15 MB) | Yes | Works |
| Linux    | `yt-dlp_linux` (x64, 15 MB) | Yes | Works |
| Android  | None exists | Restricted | No PyInstaller for ARM; subprocess limited |

Android can't run yt-dlp at all. Desktop can, but the binary must be present.

## Strategy

**Desktop (Win/Mac/Linux): Auto-download on first use**
- App checks for yt-dlp on startup
- If missing, downloads platform-appropriate binary from GitHub releases
- Stores in app data directory
- Self-updates via `yt-dlp -U`

**Android: Metadata-only mode**
- Discovery/search still works via source index + MusicBrainz
- Playback resolution unavailable (no yt-dlp on Android)
- Show clear message: "Streaming playback requires desktop version"
- Future: explore pure-Dart HTTP-based YouTube resolution for Android

**Graceful degradation everywhere:**
- `is_available()` returns false → discovery uses MusicBrainz
- Search results still appear (metadata), just can't play on Android
- No crash, no cryptic errors

## Implementation Plan

### Phase 1: Desktop auto-download

**Task 1: Add auto-download to Rust core**

New module: `native/streambox_core/src/services/ytdlp_download.rs`

```
fn ensure_ytdlp_available() -> Result<PathBuf, CoreError> {
    // 1. Check data dir for existing binary
    // 2. If missing, download from:
    //    https://github.com/yt-dlp/yt-dlp/releases/download/{VERSION}/{file}
    //    - Windows: yt-dlp.exe
    //    - macOS: yt-dlp_macos
    //    - Linux: yt-dlp_linux
    // 3. Verify hash
    // 4. Return path
}

fn ytdlp_binary_path() -> Result<PathBuf, CoreError> {
    // Check order: bundled → data dir → PATH → download
}
```

**Pin version** in `native/streambox_core/ytdlp-version.txt`:
```
2026.03.17
```

**Task 2: Update ytdlp.rs binary resolution**

Replace hardcoded `YTDLP_BINARY` with `ytdlp_binary_path()`:
```
const YTDLP_VERSION: &str = include_str!("../ytdlp-version.txt");

fn resolve_ytdlp() -> Result<String, CoreError> {
    // 1. Check data/<version>/yt-dlp(.exe)
    // 2. Check PATH
    // 3. Ensure available (download if needed)
}
```

**Task 3: Expose download progress via FFI**

Add FFI endpoint so Flutter can show download progress:
```
streambox_ytdlp_download_json() → { status: "downloading"|"ready"|"error", progress: 0-100 }
```

### Phase 2: Android awareness

**Task 4: Platform detection in Rust**

`streambox_platform_info_json` already returns `target_os`. Android
reports `target_os = "android"`.

**Task 5: Android-specific logic**

```
fn is_available() -> bool {
    if cfg!(target_os = "android") {
        return false; // Never available on Android
    }
    ytdlp_binary_path().is_ok()
}
```

**Task 6: Flutter diagnostics per platform**

- Desktop: "yt-dlp not found. Downloading..." or "Install manually from..."
- Android: "Streaming playback requires the desktop version of Streambox. Search and library features work normally."

### Phase 3: Graceful degradation

**Task 7: Discovery without yt-dlp**

When yt-dlp unavailable:
- `discover()` skips the yt-dlp phase entirely
- Returns source index + MusicBrainz results
- Items are marked `kind: "metadata"` (non-playable)
- No crash, no hang

**Task 8: Resolve error handling**

When `resolve()` called without yt-dlp:
- Desktop: return error with download instructions
- Android: return error "Playback unavailable on Android"

## Execution Order

| Task | Description | Platform impact |
|------|-------------|-----------------|
| 1 | Auto-download module | Desktop only |
| 2 | Update binary resolution | All (no-op on Android) |
| 3 | Download progress FFI | Desktop only |
| 4 | Platform detection | All |
| 5 | Android skip logic | Android only |
| 6 | Per-platform diagnostics | Flutter (all) |
| 7 | Discovery degradation | All |
| 8 | Resolve error messages | All |

## Comparison with previous plan

| Aspect | Bundled binary (old) | Auto-download + Android skip (new) |
|--------|---------------------|-----------------------------------|
| Android | Broken | Works (metadata-only) |
| Desktop first run | Works instantly | ~30s download on first launch |
| Build complexity | CMake integration | None (runtime download) |
| Binary size | +15 MB per platform | 0 build-time cost |
| Update strategy | Manual rebuild | Auto `yt-dlp -U` |
| Offline first run | Works | Fails gracefully (shows download prompt) |
| Antivirus | Bundled exe may trigger | Same risk on download |
