use std::path::Path;

use crate::db;
use crate::error::CoreError;
use crate::models::{MusicBrainzTrack, SourceIndexEntry};
use crate::services::musicbrainz::MusicBrainzClient;
use crate::services::ytdlp;

pub const DISCOVER_RESULT_LIMIT: usize = 12;

/// Represents a single discovery result. Mirrors Python's DiscoverItem.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DiscoverResult {
    pub mode: String, // "stream" | "metadata"
    pub kind: String, // "song" | "video" | "metadata"
    pub label: String,
    pub track: DiscoverTrack,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DiscoverTrack {
    pub id: String,
    pub title: String,
    pub artists: Vec<ArtistRef>,
    pub album: Option<AlbumRef>,
    pub length_ms: Option<i64>,
    pub artwork_url: Option<String>,
    pub source_provider: Option<String>,
    pub source_id: Option<String>,
    pub source_url: Option<String>,
    pub source_kind: Option<String>,
    pub canonical_title: Option<String>,
    pub canonical_artist: Option<String>,
    pub confidence_score: Option<f64>,
    pub rank_reason: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ArtistRef {
    pub name: String,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct AlbumRef {
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
}

/// Full discover pipeline. Two-phase: SourceIndex → MusicBrainz (yt-dlp phase
/// moved to Dart-side YtDlpEngine/NewPipeEngine).
/// Returns (items, warnings).
pub fn discover(
    database_path: &Path,
    query: &str,
    limit: usize,
) -> Result<(Vec<DiscoverResult>, Vec<String>), CoreError> {
    let clean_query = query.trim();
    if clean_query.is_empty() {
        return Ok((vec![], vec![]));
    }

    // 1. Try SourceIndex for high-confidence cached results (>=90 confidence)
    if let Ok(entries) = db::search_source_index_entries(database_path, clean_query, limit, None) {
        if entries
            .first()
            .map(|e| e.confidence_score >= 90.0)
            .unwrap_or(false)
        {
            let items = entries
                .into_iter()
                .take(limit)
                .map(source_index_to_discover)
                .collect();
            return Ok((items, vec![]));
        }
    }

    // Phase 2 (yt-dlp search) removed — moved to Dart-side YtDlpEngine / NewPipeEngine.
    // The Rust FFI yt-dlp endpoints remain for backward compatibility but are deprecated.

    // 3. Fall back to MusicBrainz metadata search
    match MusicBrainzClient::new() {
        Ok(mut mb_client) => match mb_client.search_tracks(clean_query, limit) {
            Ok(tracks) => {
                let items: Vec<DiscoverResult> =
                    tracks.into_iter().map(mb_track_to_discover).collect();
                let warnings = if items.is_empty() {
                    vec!["No matching tracks found.".to_string()]
                } else {
                    vec![]
                };
                Ok((items, warnings))
            }
            Err(_) => Ok((vec![], vec!["MusicBrainz unavailable.".to_string()])),
        },
        Err(_) => Ok((vec![], vec!["MusicBrainz unavailable.".to_string()])),
    }
}

fn ytdlp_track_to_discover(track: ytdlp::YtDlpTrack) -> DiscoverResult {
    let (title, artist) = split_title_artist(&track.title);
    let canonical_title = track.title.clone();
    let canonical_artist = track.uploader.clone();

    DiscoverResult {
        mode: "stream".to_string(),
        kind: "song".to_string(),
        label: "YouTube Music".to_string(),
        track: DiscoverTrack {
            id: track.id.clone(),
            title: title.unwrap_or_else(|| track.title.clone()),
            artists: {
                let a = artist
                    .unwrap_or_else(|| track.uploader.unwrap_or_else(|| "YouTube".to_string()));
                vec![ArtistRef { name: a }]
            },
            album: None,
            length_ms: track.duration_seconds.map(|d| (d * 1000.0) as i64),
            artwork_url: track.thumbnail,
            source_provider: Some("youtube".to_string()),
            source_id: Some(track.id),
            source_url: Some(track.url),
            source_kind: Some("song".to_string()),
            canonical_title: Some(canonical_title),
            canonical_artist,
            confidence_score: None,
            rank_reason: None,
        },
    }
}

fn mb_track_to_discover(track: MusicBrainzTrack) -> DiscoverResult {
    DiscoverResult {
        mode: "metadata".to_string(),
        kind: "metadata".to_string(),
        label: "MusicBrainz".to_string(),
        track: DiscoverTrack {
            id: track.id,
            title: track.title,
            artists: track
                .artists
                .into_iter()
                .map(|a| ArtistRef { name: a.name })
                .collect(),
            album: track.album.map(|a| AlbumRef {
                title: a.title,
                id: a.id,
            }),
            length_ms: track.length_ms,
            artwork_url: None,
            source_provider: None,
            source_id: None,
            source_url: None,
            source_kind: None,
            canonical_title: None,
            canonical_artist: None,
            confidence_score: None,
            rank_reason: None,
        },
    }
}

fn source_index_to_discover(entry: SourceIndexEntry) -> DiscoverResult {
    let is_video = entry.source_kind == "video";
    DiscoverResult {
        mode: "stream".to_string(),
        kind: if is_video { "video" } else { "song" }.to_string(),
        label: if entry.source_provider == "ytmusic" {
            "YouTube Music".to_string()
        } else {
            "Source index".to_string()
        },
        track: DiscoverTrack {
            id: format!("{}:{}", entry.source_provider, entry.source_id),
            title: if entry.canonical_title.is_empty() {
                entry.title.clone()
            } else {
                entry.canonical_title.clone()
            },
            artists: if entry.canonical_artist.is_empty() {
                vec![ArtistRef {
                    name: entry.source_provider.clone(),
                }]
            } else {
                vec![ArtistRef {
                    name: entry.canonical_artist.clone(),
                }]
            },
            album: None,
            length_ms: entry.duration_seconds.map(|d| (d * 1000.0) as i64),
            artwork_url: if entry.artwork_url.is_empty() {
                None
            } else {
                Some(entry.artwork_url)
            },
            source_provider: Some(entry.source_provider),
            source_id: Some(entry.source_id),
            source_url: Some(entry.source_url),
            source_kind: Some(entry.source_kind),
            canonical_title: if entry.canonical_title.is_empty() {
                None
            } else {
                Some(entry.canonical_title)
            },
            canonical_artist: if entry.canonical_artist.is_empty() {
                None
            } else {
                Some(entry.canonical_artist)
            },
            confidence_score: Some(entry.confidence_score),
            rank_reason: if entry.rank_reason.is_empty() {
                None
            } else {
                Some(entry.rank_reason)
            },
        },
    }
}

fn discover_to_source_index_entry(item: &DiscoverResult) -> SourceIndexEntry {
    SourceIndexEntry {
        source_provider: item.track.source_provider.clone().unwrap_or_default(),
        source_id: item.track.source_id.clone().unwrap_or_default(),
        source_url: item.track.source_url.clone().unwrap_or_default(),
        title: item.track.title.clone(),
        artist: item.track.canonical_artist.clone().unwrap_or_default(),
        album: String::new(),
        duration_seconds: item.track.length_ms.map(|ms| ms as f64 / 1000.0),
        confidence_score: 0.0,
        rank_reason: String::new(),
        artwork_url: item.track.artwork_url.clone().unwrap_or_default(),
        source_kind: item.track.source_kind.clone().unwrap_or_default(),
        raw_title: item.track.title.clone(),
        canonical_title: item
            .track
            .canonical_title
            .clone()
            .unwrap_or_else(|| item.track.title.clone()),
        canonical_artist: item.track.canonical_artist.clone().unwrap_or_default(),
        parse_source: "structured".to_string(),
    }
}

/// Try to split "Artist - Title" format.
/// Always treats text before " - " as artist and text after as title.
fn split_title_artist(input: &str) -> (Option<String>, Option<String>) {
    if let Some(pos) = input.find(" - ") {
        let left = input[..pos].trim();
        let right = input[pos + 3..].trim();
        // Conventional format: "Artist - Title"
        // Right is typically the title
        return (Some(right.to_string()), Some(left.to_string()));
    }
    (None, None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_title_artist() {
        let (title, artist) = split_title_artist("Daft Punk - Around the World");
        assert_eq!(title.unwrap(), "Around the World");
        assert_eq!(artist.unwrap(), "Daft Punk");
    }

    #[test]
    fn test_split_no_separator() {
        let (title, artist) = split_title_artist("Around the World");
        assert!(title.is_none());
        assert!(artist.is_none());
    }

    #[test]
    fn test_source_index_to_result() {
        let entry = SourceIndexEntry {
            source_provider: "youtube".to_string(),
            source_id: "abc123".to_string(),
            source_url: "https://youtube.com/watch?v=abc123".to_string(),
            title: "Test Song".to_string(),
            artist: "Test Artist".to_string(),
            album: String::new(),
            duration_seconds: Some(180.0),
            confidence_score: 95.0,
            rank_reason: "artist structured".to_string(),
            artwork_url: "https://img.example.com/art.jpg".to_string(),
            source_kind: "song".to_string(),
            raw_title: "Test Song".to_string(),
            canonical_title: "Test Song".to_string(),
            canonical_artist: "Test Artist".to_string(),
            parse_source: "structured".to_string(),
        };
        let result = source_index_to_discover(entry);
        assert_eq!(result.track.title, "Test Song");
        assert_eq!(result.track.artists[0].name, "Test Artist");
        assert_eq!(
            result.track.source_url.as_deref(),
            Some("https://youtube.com/watch?v=abc123")
        );
        assert!((result.track.confidence_score.unwrap() - 95.0).abs() < 0.01);
    }

    #[test]
    fn test_discover_empty_query() {
        let (items, warnings) = discover(Path::new(":memory:"), "", 10).unwrap();
        assert!(items.is_empty());
        assert!(warnings.is_empty());
    }

    #[test]
    fn test_ytdlp_track_to_discover_with_dash() {
        let track = ytdlp::YtDlpTrack {
            id: "test123".to_string(),
            title: "Artist Name - Song Title".to_string(),
            url: "https://youtube.com/watch?v=test123".to_string(),
            duration_seconds: Some(210.0),
            uploader: Some("Artist Name".to_string()),
            thumbnail: Some("https://img.jpg".to_string()),
            webpage_url: Some("https://youtube.com/watch?v=test123".to_string()),
        };
        let result = ytdlp_track_to_discover(track);
        assert_eq!(result.track.title, "Song Title");
        assert_eq!(result.track.artists[0].name, "Artist Name");
        assert_eq!(result.track.source_provider.as_deref(), Some("youtube"));
    }

    #[test]
    fn test_ytdlp_track_to_discover_no_dash() {
        let track = ytdlp::YtDlpTrack {
            id: "vid456".to_string(),
            title: "Just a Video Title".to_string(),
            url: "https://youtube.com/watch?v=vid456".to_string(),
            duration_seconds: None,
            uploader: None,
            thumbnail: None,
            webpage_url: None,
        };
        let result = ytdlp_track_to_discover(track);
        assert_eq!(result.track.title, "Just a Video Title");
        assert_eq!(result.track.artists[0].name, "YouTube");
        assert!(result.track.length_ms.is_none());
    }

    #[test]
    fn test_discover_to_source_index_roundtrip() {
        let result = DiscoverResult {
            mode: "stream".to_string(),
            kind: "song".to_string(),
            label: "Test".to_string(),
            track: DiscoverTrack {
                id: "youtube:abc".to_string(),
                title: "Test Title".to_string(),
                artists: vec![ArtistRef {
                    name: "Test Artist".to_string(),
                }],
                album: None,
                length_ms: Some(180000),
                artwork_url: Some("https://art.jpg".to_string()),
                source_provider: Some("youtube".to_string()),
                source_id: Some("abc".to_string()),
                source_url: Some("https://youtube.com/watch?v=abc".to_string()),
                source_kind: Some("song".to_string()),
                canonical_title: Some("Test Title".to_string()),
                canonical_artist: Some("Test Artist".to_string()),
                confidence_score: None,
                rank_reason: None,
            },
        };
        let entry = discover_to_source_index_entry(&result);
        assert_eq!(entry.title, "Test Title");
        assert_eq!(entry.artist, "Test Artist");
        assert_eq!(entry.source_provider, "youtube");
        assert_eq!(entry.duration_seconds, Some(180.0));
    }
}
