use std::collections::HashSet;
use std::thread;
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use serde_json::Value;

use crate::error::CoreError;
use crate::models::{AlbumMetadata, ArtistMetadata, MusicBrainzTrack};
use crate::services::listenbrainz::ListenBrainzClient;

const MUSICBRAINZ_BASE_URL: &str = "https://musicbrainz.org/ws/2";
const USER_AGENT: &str = "Streambox/0.1.0 ( personal-music-player@localhost )";
const THROTTLE_MS: u64 = 1050;
const REQUEST_TIMEOUT: u64 = 10;
const SOFT: &[&str] = &[
    "a",
    "an",
    "and",
    "feat",
    "featuring",
    "in",
    "of",
    "the",
    "to",
];
const CUE: &[&str] = &[
    "acoustic",
    "cover",
    "covers",
    "dance",
    "instrumental",
    "karaoke",
    "live",
    "orchestra",
    "piano",
    "remix",
    "symphony",
    "tribute",
];

// ── QueryVariant ──────────────────────────────────────────────────────────────

struct QueryVariant {
    query: String,
    dismax: bool,
}

fn query_variants(query: &str) -> Vec<QueryVariant> {
    let mut variants = Vec::new();
    variants.push(QueryVariant {
        query: query.to_string(),
        dismax: true,
    });

    let words: Vec<&str> = query.split_whitespace().collect();
    let soft_set: HashSet<&str> = SOFT.iter().copied().collect();
    if words.len() >= 3 {
        let last_lower = words[words.len() - 1].to_lowercase();
        if !soft_set.contains(last_lower.as_str()) {
            let title = words[..words.len() - 1].join(" ");
            let artist = words[words.len() - 1];
            variants.push(QueryVariant {
                query: format!("recording:\"{title}\" AND artist:\"{artist}\""),
                dismax: false,
            });
        }
    }

    let fuzzy_terms: Vec<String> = core_tokens(query)
        .into_iter()
        .filter(|t| t.len() > 3)
        .collect();
    if !fuzzy_terms.is_empty() {
        let parts: Vec<String> = fuzzy_terms
            .iter()
            .map(|t| format!("recording:{t}~"))
            .collect();
        variants.push(QueryVariant {
            query: parts.join(" AND "),
            dismax: false,
        });
    }

    variants
}

// ── Token helpers ─────────────────────────────────────────────────────────────

fn tokens(value: &str) -> HashSet<String> {
    crate::ranking::tokenize(value).into_iter().collect()
}

fn core_tokens(value: &str) -> HashSet<String> {
    let all = crate::ranking::tokenize(value);
    crate::ranking::core_tokens(&all, SOFT)
        .into_iter()
        .collect()
}

fn cue_set() -> HashSet<String> {
    CUE.iter().map(|s| s.to_string()).collect()
}

// ── strip_parenthetical ───────────────────────────────────────────────────────
//
// Delegated to `crate::ranking::strip_parenthetical`.

fn strip_parenthetical(value: &str) -> String {
    crate::ranking::strip_parenthetical(value)
}

// ── normalize_title ───────────────────────────────────────────────────────────

fn normalize_title(value: &str) -> String {
    crate::ranking::normalize_title(value, SOFT)
}

fn artist_label(artists: &[ArtistMetadata]) -> String {
    artists
        .iter()
        .map(|a| a.name.as_str())
        .collect::<Vec<&str>>()
        .join(", ")
}

// ── Deduplication helpers ─────────────────────────────────────────────────────

fn dedupe_recordings(recordings: Vec<Value>) -> Vec<Value> {
    let mut seen = HashSet::new();
    let mut deduped = Vec::new();
    for recording in recordings {
        let rec_id = recording.get("id").and_then(|v| v.as_str()).unwrap_or("");
        if rec_id.is_empty() || seen.contains(rec_id) {
            continue;
        }
        seen.insert(rec_id.to_string());
        deduped.push(recording);
    }
    deduped
}

fn dedupe_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut output = Vec::new();
    for value in values {
        if seen.insert(value.clone()) {
            output.push(value);
        }
    }
    output
}

// ── best_release ──────────────────────────────────────────────────────────────

fn best_release(releases: &[Value]) -> Value {
    if releases.is_empty() {
        return Value::Null;
    }

    let cue = cue_set();

    let mut ranked: Vec<(&Value, i32, &str)> = releases
        .iter()
        .map(|release| {
            let rg = release.get("release-group").and_then(|v| v.as_object());
            let title = release.get("title").and_then(|v| v.as_str()).unwrap_or("");
            let rg_title = rg
                .and_then(|m| m.get("title"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let text = format!("{title} {rg_title}");

            let mut score = 0i32;
            if release.get("status").and_then(|v| v.as_str()) == Some("Official") {
                score += 8;
            }
            if let Some(primary) = rg
                .and_then(|m| m.get("primary-type"))
                .and_then(|v| v.as_str())
            {
                if matches!(primary, "Album" | "Single" | "EP") {
                    score += 6;
                }
            }
            if tokens(&text).is_disjoint(&cue) {
                score += 4;
            }
            let date = release
                .get("date")
                .and_then(|v| v.as_str())
                .unwrap_or("9999");

            (release, -score, date)
        })
        .collect();

    ranked.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| a.2.cmp(b.2)));
    ranked
        .into_iter()
        .next()
        .map(|(r, _, _)| r)
        .unwrap_or(&releases[0])
        .clone()
}

// ── recording_to_track ───────────────────────────────────────────────────────

fn recording_to_track(recording: Value) -> MusicBrainzTrack {
    let artists: Vec<ArtistMetadata> = recording
        .get("artist-credit")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|credit| {
                    let artist = credit.get("artist")?;
                    let name = artist.get("name")?.as_str()?;
                    if name.is_empty() {
                        return None;
                    }
                    Some(ArtistMetadata {
                        id: artist.get("id").and_then(|v| v.as_str()).map(String::from),
                        name: name.to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let releases: Vec<Value> = recording
        .get("releases")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let release_count = releases.len();

    let release = best_release(&releases);
    let album = if release.is_null() {
        None
    } else {
        let rg = release.get("release-group");
        Some(AlbumMetadata {
            id: release.get("id").and_then(|v| v.as_str()).map(String::from),
            title: release
                .get("title")
                .and_then(|v| v.as_str())
                .map(String::from),
            release_group_id: rg
                .and_then(|v| v.get("id"))
                .and_then(|v| v.as_str())
                .map(String::from),
            artwork_url: None,
        })
    };

    let id = recording
        .get("id")
        .and_then(|v| v.as_str())
        .map(String::from)
        .unwrap_or_else(|| {
            recording
                .get("title")
                .and_then(|v| v.as_str())
                .map(urlencoding)
                .unwrap_or_default()
        });

    MusicBrainzTrack {
        id,
        title: recording
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        artists,
        album,
        length_ms: recording.get("length").and_then(|v| v.as_i64()),
        score: recording.get("score").and_then(|v| v.as_i64()),
        match_reasons: Vec::new(),
        listen_count: None,
        listener_count: None,
        popularity_score: None,
        source: "musicbrainz".to_string(),
        release_count,
    }
}

fn urlencoding(value: &str) -> String {
    value
        .chars()
        .map(|c| match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => {
                let mut buf = [0u8; 4];
                let s = c.encode_utf8(&mut buf);
                s.to_string()
            }
            ' ' => "+".to_string(),
            _ => {
                let mut buf = [0u8; 4];
                let s = c.encode_utf8(&mut buf);
                s.bytes().map(|b| format!("%{:02X}", b)).collect::<String>()
            }
        })
        .collect()
}

// ── rank_tracks ──────────────────────────────────────────────────────────────

fn rank_tracks(query: &str, tracks: Vec<MusicBrainzTrack>) -> Vec<MusicBrainzTrack> {
    let query_tokens = tokens(query);
    let query_core_tokens = core_tokens(query);
    let query_cues: HashSet<String> = query_tokens.intersection(&cue_set()).cloned().collect();
    let cue = cue_set();

    // Compute scores
    struct Ranked {
        track: MusicBrainzTrack,
        score: f64,
    }

    let mut ranked: Vec<Ranked> = tracks
        .into_iter()
        .map(|track| {
            let title_tokens = tokens(&track.title);
            let title_core_tokens = core_tokens(&track.title);
            let artist_tokens = tokens(&artist_label(&track.artists));
            let token_overlap = query_tokens
                .intersection(&title_tokens.union(&artist_tokens).cloned().collect())
                .count() as f64;
            let title_overlap = query_tokens.intersection(&title_tokens).count() as f64;
            let artist_overlap = query_tokens.intersection(&artist_tokens).count() as f64;

            let mut score: f64 = track.score.unwrap_or(0) as f64;

            let album_title = track
                .album
                .as_ref()
                .and_then(|a| a.title.as_deref())
                .unwrap_or("");
            let combined_tokens: HashSet<String> = title_tokens
                .union(&artist_tokens)
                .cloned()
                .collect::<HashSet<String>>()
                .union(&tokens(album_title))
                .cloned()
                .collect();
            let cue_overlap: HashSet<String> =
                combined_tokens.intersection(&cue).cloned().collect();

            let mut reasons: Vec<String> = track.match_reasons.clone();

            let title_match_ratio = if !query_core_tokens.is_empty() {
                let intersect = query_core_tokens.intersection(&title_core_tokens).count() as f64;
                intersect / query_core_tokens.len() as f64
            } else {
                0.0
            };

            let strong_match = title_match_ratio >= 0.75 || artist_overlap > 0.0;
            let popularity_boost = (track.popularity_score.unwrap_or(0.0) / 1000.0).min(35.0);
            score += if strong_match {
                popularity_boost
            } else {
                popularity_boost.min(4.0)
            };

            if !query_tokens.is_empty() && query_tokens.is_subset(&title_tokens) {
                score += 80.0;
                reasons.push("title".to_string());
            }
            let title_and_artist: HashSet<String> =
                title_tokens.union(&artist_tokens).cloned().collect();
            if !query_tokens.is_empty() && query_tokens.is_subset(&title_and_artist) {
                score += 25.0;
            }
            if !query_core_tokens.is_empty() && query_core_tokens == title_core_tokens {
                score += 70.0;
                reasons.push("exact-title".to_string());
            } else if !query_core_tokens.is_empty()
                && !query_core_tokens.is_disjoint(&title_core_tokens)
            {
                reasons.push("fuzzy".to_string());
            }
            score += token_overlap * 8.0;
            score += title_overlap * 10.0;
            if artist_overlap > 0.0 {
                score += artist_overlap * 85.0;
                reasons.push("artist".to_string());
            }
            if !query_core_tokens.is_empty() && title_match_ratio < 0.5 {
                score -= 80.0;
            }

            // Stripped parenthetical title
            let stripped_title_core = core_tokens(&strip_parenthetical(&track.title));
            let query_minus_artist: HashSet<String> = query_core_tokens
                .difference(&artist_tokens)
                .cloned()
                .collect();
            if stripped_title_core == query_minus_artist {
                score += 24.0;
            }

            // Duration
            if let Some(length_ms) = track.length_ms {
                let duration_seconds = length_ms as f64 / 1000.0;
                let base = crate::ranking::duration_score(Some(duration_seconds), 120.0, 420.0);
                if base == -35 {
                    score -= 35.0;
                } else if base == 12 {
                    score += 18.0; // musicbrainz overrides ideal weight
                } else if (90.0..=540.0).contains(&duration_seconds) {
                    score += 8.0;
                }
            }

            // Album
            if let Some(ref album) = track.album {
                if album.title.is_some() {
                    score += 5.0;
                    if let Some(ref album_title) = album.title {
                        if normalize_title(album_title) == normalize_title(&track.title) {
                            score += 16.0;
                        }
                    }
                }
            }

            // Release count
            if track.release_count > 0 {
                score += (track.release_count.min(12) * 4) as f64;
            }

            // Cue words not in query
            let unexpected_cues: Vec<&String> = cue_overlap.difference(&query_cues).collect();
            if !unexpected_cues.is_empty() {
                score -= 45.0 + (unexpected_cues.len() as f64 * 10.0);
                reasons.push("cover-like".to_string());
            }

            reasons = dedupe_strings(reasons);

            let mut track = track;
            track.match_reasons = reasons;
            track.match_reasons.sort();

            Ranked { track, score }
        })
        .collect();

    // Sort: reasons count desc (more reasons first), then score desc, then title asc
    ranked.sort_by(|a, b| {
        b.track
            .match_reasons
            .len()
            .cmp(&a.track.match_reasons.len())
            .then_with(|| {
                b.score
                    .partial_cmp(&a.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .then_with(|| {
                a.track
                    .title
                    .to_lowercase()
                    .cmp(&b.track.title.to_lowercase())
            })
    });

    ranked.into_iter().map(|r| r.track).collect()
}

// ── MusicBrainzClient ─────────────────────────────────────────────────────────

pub struct MusicBrainzClient {
    client: Client,
    last_request_at: std::sync::Mutex<Instant>,
}

impl MusicBrainzClient {
    pub fn new() -> Result<Self, CoreError> {
        let client = Client::builder()
            .timeout(Duration::from_secs(REQUEST_TIMEOUT))
            .user_agent(USER_AGENT)
            .build()
            .map_err(|error| CoreError::new("musicbrainz_client_error", error.to_string()))?;
        Ok(Self {
            client,
            last_request_at: std::sync::Mutex::new(
                Instant::now() - Duration::from_millis(THROTTLE_MS * 2),
            ),
        })
    }

    fn throttle(&self) {
        let mut last = self.last_request_at.lock().unwrap();
        let elapsed = last.elapsed().as_millis() as u64;
        if elapsed < THROTTLE_MS {
            thread::sleep(Duration::from_millis(THROTTLE_MS - elapsed));
        }
        *last = Instant::now();
    }

    fn get_json(&self, path: &str, params: Vec<(&str, &str)>) -> Result<Value, CoreError> {
        self.throttle();
        let url = format!("{MUSICBRAINZ_BASE_URL}{path}");
        let response = self
            .client
            .get(&url)
            .query(&params)
            .send()
            .map_err(|error| CoreError::new("musicbrainz_request_failed", error.to_string()))?;
        if !response.status().is_success() {
            return Err(CoreError::new(
                "musicbrainz_error",
                format!("MusicBrainz returned HTTP {}", response.status()),
            ));
        }
        response
            .json::<Value>()
            .map_err(|error| CoreError::new("musicbrainz_parse_failed", error.to_string()))
    }

    pub fn search_tracks(
        &mut self,
        query: &str,
        limit: usize,
    ) -> Result<Vec<MusicBrainzTrack>, CoreError> {
        let clean_query = query.trim();
        if clean_query.is_empty() {
            return Ok(Vec::new());
        }

        let fetch_limit = std::cmp::max(limit * 4, 50);
        let limit_str = fetch_limit.to_string();
        let mut recordings: Vec<Value> = Vec::new();

        for variant in query_variants(clean_query) {
            let mut params = vec![
                ("query", variant.query.as_str()),
                ("fmt", "json"),
                ("limit", limit_str.as_str()),
                ("inc", "artist-credits+releases+release-groups"),
            ];
            if variant.dismax {
                params.push(("dismax", "true"));
            }
            match self.get_json("/recording", params) {
                Ok(payload) => {
                    if let Some(recs) = payload.get("recordings").and_then(|v| v.as_array()) {
                        recordings.extend(recs.iter().cloned());
                    }
                }
                Err(_) => {
                    // Continue to next variant on error
                }
            }
        }

        let mut tracks: Vec<MusicBrainzTrack> = dedupe_recordings(recordings)
            .into_iter()
            .map(recording_to_track)
            .filter(|t| !t.title.is_empty() && !t.artists.is_empty())
            .collect();

        // Enrich tracks with ListenBrainz popularity data before ranking
        if let Ok(lb_client) = ListenBrainzClient::new() {
            let mbid_refs: Vec<String> = tracks.iter().map(|t| t.id.clone()).collect();
            if let Ok(popularity_map) = lb_client.recording_popularity(&mbid_refs) {
                for track in &mut tracks {
                    if let Some(stats) = popularity_map.get(&track.id) {
                        track.listen_count = stats.listen_count;
                        track.listener_count = stats.listener_count;
                        track.popularity_score = Some(stats.score);
                    }
                }
            }
        }

        tracks = rank_tracks(clean_query, tracks);
        tracks.truncate(limit);
        Ok(tracks)
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tokens_basic() {
        let result = tokens("Hello World");
        assert_eq!(result.len(), 2);
        assert!(result.contains("hello"));
        assert!(result.contains("world"));
    }

    #[test]
    fn test_tokens_short_skipped() {
        let result = tokens("a b c d");
        assert!(result.is_empty());
    }

    #[test]
    fn test_tokens_mixed() {
        let result = tokens("The Beat of a Drum");
        assert!(!result.contains("a"));
        assert!(result.contains("the"));
        assert!(result.contains("beat"));
    }

    #[test]
    fn test_core_tokens_removes_soft() {
        let result = core_tokens("The Beat of a Drum");
        assert!(!result.contains("the"));
        assert!(!result.contains("of"));
        assert!(!result.contains("a"));
        assert!(result.contains("beat"));
        assert!(result.contains("drum"));
    }

    #[test]
    fn test_query_variants_single_word() {
        let variants = query_variants("a"); // "a" has 1 char, won't generate fuzzy
        assert_eq!(variants.len(), 1);
        assert!(variants[0].dismax);
    }

    #[test]
    fn test_query_variants_multi_word() {
        let variants = query_variants("stairway to heaven");
        assert_eq!(variants.len(), 3);
        // variant 0: dismax
        assert!(variants[0].dismax);
        assert_eq!(variants[0].query, "stairway to heaven");
        // variant 1: recording:"stairway to" AND artist:"heaven"
        assert!(!variants[1].dismax);
        assert_eq!(
            variants[1].query,
            "recording:\"stairway to\" AND artist:\"heaven\""
        );
        // variant 2: fuzzy
        assert!(!variants[2].dismax);
    }

    #[test]
    fn test_query_variants_ends_with_soft() {
        let variants = query_variants("stairway to heaven in");
        assert_eq!(variants.len(), 2); // no variant 1 since ends with 'in'
        assert!(variants[0].dismax);
        assert!(!variants[1].dismax); // fuzzy
    }

    #[test]
    fn test_strip_parenthetical() {
        assert_eq!(strip_parenthetical("Hello (Live)"), "Hello");
        assert_eq!(
            strip_parenthetical("Hello (Live At Wembley) World"),
            "Hello  World"
        );
        assert_eq!(strip_parenthetical("No Parens"), "No Parens");
    }

    #[test]
    fn test_normalize_title() {
        // "Bohemian Rhapsody (Live)" -> core tokens: bohemian, rhapsody -> sorted: bohemian rhapsody
        let result = normalize_title("Bohemian Rhapsody (Live)");
        assert_eq!(result, "bohemian rhapsody");
    }

    #[test]
    fn test_best_release_empty() {
        let result = best_release(&[]);
        assert!(result.is_null());
    }

    #[test]
    fn test_best_release_official_wins() {
        let releases = vec![
            serde_json::json!({
                "id": "2",
                "title": "Bootleg",
                "status": "Promotion",
                "release-group": {
                    "id": "rg2",
                    "title": "Bootleg",
                    "primary-type": "Other"
                },
                "date": "2020-01-01"
            }),
            serde_json::json!({
                "id": "1",
                "title": "Official Album",
                "status": "Official",
                "release-group": {
                    "id": "rg1",
                    "title": "Official Album",
                    "primary-type": "Album"
                },
                "date": "2019-01-01"
            }),
        ];
        let result = best_release(&releases);
        assert_eq!(result.get("id").and_then(|v| v.as_str()), Some("1"));
    }

    #[test]
    fn test_dedupe_recordings() {
        let recordings = vec![
            serde_json::json!({"id": "a", "title": "Song A"}),
            serde_json::json!({"id": "b", "title": "Song B"}),
            serde_json::json!({"id": "a", "title": "Song A Dup"}),
        ];
        let result = dedupe_recordings(recordings);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_dedupe_strings() {
        let input = vec!["a".into(), "b".into(), "a".into(), "c".into()];
        let result = dedupe_strings(input);
        assert_eq!(result, vec!["a", "b", "c"]);
    }

    #[test]
    fn test_artist_label() {
        let artists = vec![
            ArtistMetadata {
                id: Some("id1".into()),
                name: "John".into(),
            },
            ArtistMetadata {
                id: Some("id2".into()),
                name: "Paul".into(),
            },
        ];
        assert_eq!(artist_label(&artists), "John, Paul");
    }

    #[test]
    fn test_ranking_basic() {
        let tracks = vec![
            MusicBrainzTrack {
                id: "1".into(),
                title: "Stairway to Heaven".into(),
                artists: vec![ArtistMetadata {
                    id: Some("id1".into()),
                    name: "Led Zeppelin".into(),
                }],
                album: Some(AlbumMetadata {
                    id: Some("a1".into()),
                    title: Some("Led Zeppelin IV".into()),
                    release_group_id: Some("rg1".into()),
                    artwork_url: None,
                }),
                length_ms: Some(482_000),
                score: Some(100),
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 10,
            },
            MusicBrainzTrack {
                id: "2".into(),
                title: "Bohemian Rhapsody".into(),
                artists: vec![ArtistMetadata {
                    id: Some("id2".into()),
                    name: "Queen".into(),
                }],
                album: Some(AlbumMetadata {
                    id: Some("a2".into()),
                    title: Some("A Night at the Opera".into()),
                    release_group_id: Some("rg2".into()),
                    artwork_url: None,
                }),
                length_ms: Some(354_000),
                score: Some(90),
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 8,
            },
        ];

        let result = rank_tracks("stairway to heaven", tracks);
        assert_eq!(result.len(), 2);
        // "Stairway to Heaven" should be first since it matches query better
        assert!(result[0].title.contains("Stairway"));
    }

    #[test]
    fn test_recording_to_track_minimal() {
        let recording = serde_json::json!({
            "id": "abc-123",
            "title": "Test Song",
            "score": "95",
            "length": 240000,
            "artist-credit": [
                {
                    "artist": {
                        "id": "art-1",
                        "name": "Test Artist"
                    }
                }
            ],
            "releases": [
                {
                    "id": "rel-1",
                    "title": "Test Album",
                    "status": "Official",
                    "release-group": {
                        "id": "rg-1",
                        "title": "Test Album",
                        "primary-type": "Album"
                    },
                    "date": "2020-01-01"
                }
            ]
        });
        let track = recording_to_track(recording);
        assert_eq!(track.id, "abc-123");
        assert_eq!(track.title, "Test Song");
        assert_eq!(track.artists.len(), 1);
        assert_eq!(track.artists[0].name, "Test Artist");
        assert!(track.album.is_some());
        assert_eq!(
            track.album.as_ref().unwrap().title.as_deref(),
            Some("Test Album")
        );
        assert_eq!(track.length_ms, Some(240_000));
        assert_eq!(track.release_count, 1);
    }

    #[test]
    fn test_recording_to_track_no_artists() {
        let recording = serde_json::json!({
            "id": "no-artist",
            "title": "No Artist Track",
            "releases": []
        });
        let track = recording_to_track(recording);
        assert!(track.artists.is_empty());
    }

    #[test]
    fn test_recording_to_track_no_releases() {
        let recording = serde_json::json!({
            "id": "no-release",
            "title": "No Release Track",
            "artist-credit": [
                {
                    "artist": {
                        "id": "art-1",
                        "name": "Some Artist"
                    }
                }
            ],
            "releases": []
        });
        let track = recording_to_track(recording);
        assert!(track.album.is_none());
        assert_eq!(track.release_count, 0);
    }

    #[test]
    fn test_rank_tracks_exact_title_match() {
        let tracks = vec![MusicBrainzTrack {
            id: "1".into(),
            title: "Bohemian Rhapsody".into(),
            artists: vec![ArtistMetadata {
                id: Some("id1".into()),
                name: "Queen".into(),
            }],
            album: None,
            length_ms: Some(354_000),
            score: Some(100),
            match_reasons: vec![],
            listen_count: None,
            listener_count: None,
            popularity_score: None,
            source: "musicbrainz".into(),
            release_count: 0,
        }];

        let result = rank_tracks("bohemian rhapsody", tracks);
        assert_eq!(result.len(), 1);
        assert!(result[0].match_reasons.contains(&"exact-title".to_string()));
    }

    #[test]
    fn test_rank_tracks_cover_penalty() {
        let tracks = vec![MusicBrainzTrack {
            id: "1".into(),
            title: "Bohemian Rhapsody (Live)".into(),
            artists: vec![ArtistMetadata {
                id: Some("id1".into()),
                name: "Queen".into(),
            }],
            album: None,
            length_ms: Some(354_000),
            score: Some(100),
            match_reasons: vec![],
            listen_count: None,
            listener_count: None,
            popularity_score: None,
            source: "musicbrainz".into(),
            release_count: 0,
        }];

        let result = rank_tracks("bohemian rhapsody", tracks);
        assert_eq!(result.len(), 1);
        // Should have cover-like in reasons since "live" is a cue word not in query
        assert!(result[0].match_reasons.contains(&"cover-like".to_string()));
    }

    #[test]
    fn test_rank_tracks_short_duration_penalty() {
        let tracks = vec![MusicBrainzTrack {
            id: "1".into(),
            title: "Short Clip".into(),
            artists: vec![ArtistMetadata {
                id: Some("id1".into()),
                name: "Clip Artist".into(),
            }],
            album: None,
            length_ms: Some(30_000), // 30 seconds
            score: Some(100),
            match_reasons: vec![],
            listen_count: None,
            listener_count: None,
            popularity_score: None,
            source: "musicbrainz".into(),
            release_count: 0,
        }];

        let result = rank_tracks("short clip", tracks);
        assert_eq!(result.len(), 1);
        // Just verify it doesn't crash
    }

    #[test]
    fn test_recording_to_track_artist_credit_empty() {
        let recording = serde_json::json!({
            "id": "empty-artist",
            "title": "Song",
            "artist-credit": []
        });
        let track = recording_to_track(recording);
        assert!(track.artists.is_empty());
    }

    #[test]
    fn test_recording_to_track_artist_credit_no_name() {
        let recording = serde_json::json!({
            "id": "no-name",
            "title": "Song",
            "artist-credit": [
                {"artist": {"id": "art-1"}}
            ]
        });
        let track = recording_to_track(recording);
        // Artist without name should be filtered out
        assert!(track.artists.is_empty());
    }

    #[test]
    fn test_urlencoding_basic() {
        let result = urlencoding("Hello World");
        assert_eq!(result, "Hello+World");
    }

    #[test]
    fn test_enrich_tracks_with_popularity_gracefully_handles_empty_ids() {
        // Verify that the enrichment step (as used in search_tracks) gracefully
        // handles tracks with empty/invalid MBIDs without crashing
        let lb_client = ListenBrainzClient::new().unwrap();
        let tracks = [
            MusicBrainzTrack {
                id: "".into(),
                title: "Empty ID".into(),
                artists: vec![ArtistMetadata {
                    id: Some("art-1".into()),
                    name: "Artist".into(),
                }],
                album: None,
                length_ms: None,
                score: None,
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 0,
            },
            MusicBrainzTrack {
                id: "".into(),
                title: "Also Empty".into(),
                artists: vec![ArtistMetadata {
                    id: Some("art-2".into()),
                    name: "Artist 2".into(),
                }],
                album: None,
                length_ms: None,
                score: None,
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 0,
            },
        ];
        // Collect MBIDs (all empty, will hit the early-return path)
        let mbid_refs: Vec<String> = tracks.iter().map(|t| t.id.clone()).collect();
        // Should return Ok with empty map (never panics, never hits network)
        let result = lb_client.recording_popularity(&mbid_refs);
        assert!(result.is_ok());
        let popularity_map = result.unwrap();
        assert!(popularity_map.is_empty());
    }

    #[test]
    fn test_popularity_enrichment_maps_correctly() {
        // Test the data mapping logic that search_tracks uses to enrich tracks
        use std::collections::HashMap;

        use crate::models::PopularityStats;

        let mut tracks = vec![
            MusicBrainzTrack {
                id: "mbid-111".into(),
                title: "Popular Song".into(),
                artists: vec![ArtistMetadata {
                    id: Some("art-1".into()),
                    name: "Popular Artist".into(),
                }],
                album: None,
                length_ms: Some(240000),
                score: Some(100),
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 1,
            },
            MusicBrainzTrack {
                id: "mbid-222".into(),
                title: "Less Popular Song".into(),
                artists: vec![ArtistMetadata {
                    id: Some("art-2".into()),
                    name: "Less Popular Artist".into(),
                }],
                album: None,
                length_ms: Some(180000),
                score: Some(90),
                match_reasons: vec![],
                listen_count: None,
                listener_count: None,
                popularity_score: None,
                source: "musicbrainz".into(),
                release_count: 1,
            },
        ];

        // Simulate the enrichment step exactly as in search_tracks
        let mut popularity_map: HashMap<String, PopularityStats> = HashMap::new();
        let mut stats1 = PopularityStats {
            listen_count: Some(5000),
            listener_count: Some(800),
            score: 0.0,
        };
        stats1.compute_score();
        popularity_map.insert("mbid-111".into(), stats1);

        let mut stats2 = PopularityStats {
            listen_count: Some(50),
            listener_count: Some(10),
            score: 0.0,
        };
        stats2.compute_score();
        popularity_map.insert("mbid-222".into(), stats2);

        // Apply enrichment (same logic as in search_tracks)
        for track in &mut tracks {
            if let Some(stats) = popularity_map.get(&track.id) {
                track.listen_count = stats.listen_count;
                track.listener_count = stats.listener_count;
                track.popularity_score = Some(stats.score);
            }
        }

        // Track 1 should have high popularity
        assert_eq!(tracks[0].listen_count, Some(5000));
        assert_eq!(tracks[0].listener_count, Some(800));
        assert!(tracks[0].popularity_score.unwrap() > 0.0);
        // score = listeners*10 + listens = 800*10 + 5000 = 13000
        assert!((tracks[0].popularity_score.unwrap() - 13000.0).abs() < 0.01);

        // Track 2 should have lower popularity
        assert_eq!(tracks[1].listen_count, Some(50));
        assert_eq!(tracks[1].listener_count, Some(10));
        // score = 10*10 + 50 = 150
        assert!((tracks[1].popularity_score.unwrap() - 150.0).abs() < 0.01);
    }
}
