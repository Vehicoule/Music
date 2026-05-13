use std::process::Command;
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;

use crate::error::CoreError;

const YTDLP_BINARY: &str = "yt-dlp";
const YTDLP_TIMEOUT_SECS: u64 = 30;

/// A track returned by yt-dlp search or resolve.
#[derive(Debug, Clone, Serialize)]
pub struct YtDlpTrack {
    pub id: String,
    pub title: String,
    pub url: String,
    pub duration_seconds: Option<f64>,
    pub uploader: Option<String>,
    pub thumbnail: Option<String>,
    pub webpage_url: Option<String>,
}

/// Run yt-dlp search for a query.
/// Equivalent to: yt-dlp --flat-playlist --dump-json --no-download --default-search ytsearch "ytsearchN:query"
pub fn search(query: &str, limit: usize) -> Result<Vec<YtDlpTrack>, CoreError> {
    let clean_query = query.trim();
    if clean_query.is_empty() {
        return Ok(Vec::new());
    }

    let search_query = format!("ytsearch{}:{}", limit, clean_query);
    let args = &[
        "--flat-playlist",
        "--dump-json",
        "--no-download",
        "--default-search",
        "ytsearch",
        &search_query,
    ];

    let output = run_ytdlp(args, Duration::from_secs(YTDLP_TIMEOUT_SECS))?;
    let tracks = parse_ytdlp_output(&output)?;
    Ok(tracks)
}

/// Resolve a URL or query to a playable streaming URL.
/// Equivalent to: yt-dlp --dump-json --no-download --format bestaudio/best "URL"
pub fn resolve(url_or_query: &str) -> Result<YtDlpTrack, CoreError> {
    let clean = url_or_query.trim();
    if clean.is_empty() {
        return Err(CoreError::new("ytdlp_invalid_input", "empty URL or query"));
    }

    let args = &[
        "--dump-json",
        "--no-download",
        "--format",
        "bestaudio/best",
        clean,
    ];

    let output = run_ytdlp(args, Duration::from_secs(YTDLP_TIMEOUT_SECS))?;
    let track = parse_ytdlp_single(&output)?;
    Ok(track)
}

/// Resolve a direct YouTube URL to a playable URL with high-quality audio format.
pub fn resolve_url(url: &str) -> Result<YtDlpTrack, CoreError> {
    resolve(url)
}

/// Check if yt-dlp is available on the system.
pub fn is_available() -> bool {
    Command::new(YTDLP_BINARY)
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Get yt-dlp version string.
pub fn version() -> Option<String> {
    Command::new(YTDLP_BINARY)
        .arg("--version")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
}

// ── Internal helpers ──

fn run_ytdlp(args: &[&str], _timeout: Duration) -> Result<String, CoreError> {
    let owned_args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let result = std::thread::spawn(move || {
        let cmd: Vec<&str> = owned_args.iter().map(|s| s.as_str()).collect();
        Command::new(YTDLP_BINARY).args(&cmd).output()
    })
    .join()
    .map_err(|_| CoreError::new("ytdlp_thread_panic", "yt-dlp thread panicked"))?;

    let output = result.map_err(|error| {
        CoreError::new(
            "ytdlp_spawn_failed",
            format!("failed to run yt-dlp: {error}"),
        )
    })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(CoreError::new("ytdlp_error", stderr.trim().to_string()));
    }

    String::from_utf8(output.stdout)
        .map_err(|error| CoreError::new("ytdlp_invalid_utf8", error.to_string()))
}

fn parse_ytdlp_output(output: &str) -> Result<Vec<YtDlpTrack>, CoreError> {
    let mut tracks = Vec::new();
    for line in output.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let value: Value = serde_json::from_str(line)
            .map_err(|error| CoreError::new("ytdlp_parse_failed", error.to_string()))?;
        if let Some(track) = json_to_track(&value) {
            tracks.push(track);
        }
    }
    Ok(tracks)
}

fn parse_ytdlp_single(output: &str) -> Result<YtDlpTrack, CoreError> {
    let first = output.lines().next().unwrap_or("").trim();
    if first.is_empty() {
        return Err(CoreError::new(
            "ytdlp_no_output",
            "yt-dlp produced no output",
        ));
    }
    let value: Value = serde_json::from_str(first)
        .map_err(|error| CoreError::new("ytdlp_parse_failed", error.to_string()))?;
    json_to_track(&value)
        .ok_or_else(|| CoreError::new("ytdlp_parse_failed", "yt-dlp returned empty result"))
}

fn json_to_track(value: &Value) -> Option<YtDlpTrack> {
    let id = value
        .get("id")
        .or_else(|| value.get("webpage_url"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let title = value
        .get("title")
        .or_else(|| value.get("fulltitle"))
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string();

    // For flat-playlist results, the real url needs to be constructed
    let url = if let Some(u) = value.get("url").and_then(|v| v.as_str()) {
        u.to_string()
    } else if let Some(vid) = value.get("id").and_then(|v| v.as_str()) {
        format!("https://www.youtube.com/watch?v={vid}")
    } else if let Some(wp) = value.get("webpage_url").and_then(|v| v.as_str()) {
        wp.to_string()
    } else {
        return None;
    };

    let duration_seconds = value.get("duration").and_then(|v| v.as_f64()).or_else(|| {
        value
            .get("duration_string")
            .and_then(|v| v.as_str())
            .and_then(|s| parse_duration_str(s))
    });

    let uploader = value
        .get("uploader")
        .or_else(|| value.get("channel"))
        .or_else(|| value.get("artist"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let thumbnail = value
        .get("thumbnail")
        .or_else(|| {
            value
                .get("thumbnails")
                .and_then(|v| v.as_array()?.first()?.get("url"))
        })
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let webpage_url = value
        .get("webpage_url")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    Some(YtDlpTrack {
        id,
        title,
        url,
        duration_seconds,
        uploader,
        thumbnail,
        webpage_url,
    })
}

fn parse_duration_str(s: &str) -> Option<f64> {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.is_empty() {
        return None;
    }
    let mut seconds = 0.0;
    for part in parts {
        seconds = seconds * 60.0 + part.parse::<f64>().ok()?;
    }
    Some(seconds)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_duration() {
        assert!((parse_duration_str("3:45").unwrap() - 225.0).abs() < 0.01);
        assert!((parse_duration_str("1:02:30").unwrap() - 3750.0).abs() < 0.01);
        assert_eq!(parse_duration_str("invalid"), None);
    }

    #[test]
    fn test_json_to_track_basic() {
        let json = serde_json::json!({
            "id": "dQw4w9WgXcQ",
            "title": "Rick Astley - Never Gonna Give You Up",
            "duration": 212.0,
            "uploader": "Rick Astley",
            "thumbnail": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
            "webpage_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        });
        let track = json_to_track(&json).unwrap();
        assert_eq!(track.title, "Rick Astley - Never Gonna Give You Up");
        assert_eq!(track.id, "dQw4w9WgXcQ");
        assert_eq!(track.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
        assert!((track.duration_seconds.unwrap() - 212.0).abs() < 0.01);
        assert_eq!(track.uploader.as_deref(), Some("Rick Astley"));
    }

    #[test]
    fn test_json_to_track_flat_playlist_result() {
        let json = serde_json::json!({
            "id": "dQw4w9WgXcQ",
            "title": "Test Song",
            "duration": 180.0,
            "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        });
        let track = json_to_track(&json).unwrap();
        assert_eq!(track.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    }

    #[test]
    fn test_search_empty_query() {
        let result = search("", 10);
        assert!(result.unwrap().is_empty());
    }

    #[test]
    fn test_version_check() {
        // Just verify the function doesn't panic
        let _ = version();
    }
}
