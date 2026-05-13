# Remove FastAPI — Full Rust Migration Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Remove the Python FastAPI backend entirely by porting all remaining network features (MusicBrainz, ListenBrainz, YouTube Music, yt-dlp) to the Rust native core, leaving zero server dependency.

**Architecture:** Rust native core becomes the single data layer — all HTTP calls, metadata parsing, ranking, and subprocess management happen in `streambox_core`. Flutter communicates exclusively through FFI (JSON-in/JSON-out protocol). The `backend/` directory is deleted when complete.

**Tech Stack:** Rust 1.95, `reqwest` (blocking HTTP), `serde`/`serde_json`, `rusqlite` (existing), `std::process::Command` (for yt-dlp). yt-dlp binary stays as a platform-bundled asset.

**Strategy:** Port the easiest pieces first (MusicBrainz + ListenBrainz — pure REST), then YouTube Music (reverse-engineered HTTP API), then yt-dlp (bundled binary subprocess). Each phase adds new FFI endpoints and removes the corresponding FastAPI route.

---

## Phase 1: MusicBrainz + ListenBrainz → Rust

**Why first:** These are pure REST APIs returning JSON. No reverse-engineering needed. The Rust side already has a ranking engine (`rank_source_entries`), tokenizer, and `metadata_cache` table. The Python code is ~440 lines that maps cleanly to Rust.

**New dependencies:** `reqwest` with `blocking` + `json` features.

**Files to create:**
- `native/streambox_core/src/services/mod.rs`
- `native/streambox_core/src/services/musicbrainz.rs`
- `native/streambox_core/src/services/listenbrainz.rs`

**Files to modify:**
- `native/streambox_core/Cargo.toml` — add reqwest
- `native/streambox_core/src/lib.rs` — add `pub mod services`
- `native/streambox_core/src/models.rs` — add MusicBrainz response types, TrackMetadata, ArtistMetadata, AlbumMetadata
- `native/streambox_core/src/ffi.rs` — add `streambox_musicbrainz_search_json`
- `native/streambox_core/src/db.rs` — add `metadata_cache` get/set/ttl helpers (if not already in `CoreDb`)

---

### Task 1: Add reqwest dependency

**Objective:** Add `reqwest` crate with `blocking` and `json` features to Cargo.toml.

**Files:**
- Modify: `native/streambox_core/Cargo.toml`

**Context:** The existing dependencies are `serde`, `serde_json`, `rusqlite` (bundled). Add reqwest:
```toml
[dependencies]
reqwest = { version = "0.12", features = ["blocking", "json"], default-features = false }
```

Add after rusqlite line. Run `cargo check` to verify the dependency resolves. No code changes needed — just Cargo.toml.

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: `Checking reqwest v0.12.x ... Checking streambox_core v0.1.0 ... Finished`

---

### Task 2: Create services module skeleton

**Objective:** Create `src/services/mod.rs` with `pub mod musicbrainz; pub mod listenbrainz;` and register in `lib.rs`.

**Files:**
- Create: `native/streambox_core/src/services/mod.rs`
- Modify: `native/streambox_core/src/lib.rs`

**Code for `mod.rs`:**
```rust
pub mod listenbrainz;
pub mod musicbrainz;
```

**Code for `lib.rs`:** Add `pub mod services;` after existing module declarations.

---

### Task 3: Add MusicBrainz/LB data types to models.rs

**Objective:** Add Rust structs that mirror the Python Pydantic models needed for MusicBrainz and ListenBrainz responses.

**Files:**
- Modify: `native/streambox_core/src/models.rs`

**Types to add:**

```rust
/// Mirrors Python's ArtistMetadata in schemas.py
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ArtistMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub name: String,
}

/// Mirrors Python's AlbumMetadata
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct AlbumMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub release_group_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artwork_url: Option<String>,
}

/// Mirrors Python's TrackMetadata (MusicBrainz variant)
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MusicBrainzTrack {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub artists: Vec<ArtistMetadata>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub album: Option<AlbumMetadata>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub length_ms: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score: Option<i64>,
    #[serde(default)]
    pub match_reasons: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listen_count: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listener_count: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub popularity_score: Option<f64>,
    #[serde(default)]
    pub source: String,
}

/// MusicBrainz recording raw JSON (before conversion to MusicBrainzTrack)
#[derive(Debug, Clone, Deserialize)]
pub struct MusicBrainzRecording {
    pub id: Option<String>,
    pub title: Option<String>,
    #[serde(default)]
    pub length: Option<i64>,
    #[serde(default)]
    pub score: Option<i64>,
    #[serde(default, rename = "artist-credit")]
    pub artist_credit: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub releases: Option<Vec<serde_json::Value>>,
}

/// MusicBrainz search response
#[derive(Debug, Clone, Deserialize)]
pub struct MusicBrainzSearchResponse {
    #[serde(default)]
    pub recordings: Vec<serde_json::Value>,
}

/// ListenBrainz popularity stats
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PopularityStats {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listen_count: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listener_count: Option<i64>,
    #[serde(default)]
    pub score: f64,
}

impl PopularityStats {
    pub fn compute_score(&mut self) {
        let listeners = self.listener_count.unwrap_or(0) as f64;
        let listens = self.listen_count.unwrap_or(0) as f64;
        self.score = (listeners * 10.0) + listens;
    }
}
```

Append these to the end of `src/models.rs`, before the closing `}` (no closing braces needed — the file ends with `DbHealth` struct).

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: compiles clean.

---

### Task 4: Create ListenBrainz HTTP client

**Objective:** Port `backend/app/services/listenbrainz.py` (83 lines) to Rust. This is a simple HTTP POST that fetches popularity stats for MusicBrainz recording IDs.

**Files:**
- Create: `native/streambox_core/src/services/listenbrainz.rs`

**Python reference:** `backend/app/services/listenbrainz.py`

**Complete Rust implementation:**

```rust
use std::collections::HashMap;
use std::time::Duration;

use reqwest::blocking::Client;
use serde_json::Value;

use crate::error::CoreError;
use crate::models::PopularityStats;

const LISTENBRAINZ_POPULARITY_URL: &str = "https://api.listenbrainz.org/1/popularity/recording";
const LISTENBRAINZ_TIMEOUT_SECS: u64 = 10;

pub struct ListenBrainzClient {
    client: Client,
}

impl ListenBrainzClient {
    pub fn new() -> Result<Self, CoreError> {
        let client = Client::builder()
            .timeout(Duration::from_secs(LISTENBRAINZ_TIMEOUT_SECS))
            .build()
            .map_err(|error| CoreError::new("listenbrainz_client_error", error.to_string()))?;
        Ok(Self { client })
    }

    /// Fetch popularity stats for a list of MusicBrainz recording IDs.
    /// Mirrors Python's `recording_popularity()` method.
    pub fn recording_popularity(
        &self,
        recording_ids: &[String],
    ) -> Result<HashMap<String, PopularityStats>, CoreError> {
        let ids: Vec<&str> = recording_ids
            .iter()
            .filter(|id| !id.is_empty())
            .map(String::as_str)
            .collect();
        if ids.is_empty() {
            return Ok(HashMap::new());
        }

        let deduped: Vec<&str> = {
            let mut seen = std::collections::HashSet::new();
            ids.into_iter()
                .filter(|id| seen.insert(*id))
                .collect()
        };

        let missing: Vec<&str> = deduped; // TODO: add cache layer in Task 6
        if missing.is_empty() {
            return Ok(HashMap::new());
        }

        self.fetch_recording_popularity(&missing)
    }

    fn fetch_recording_popularity(
        &self,
        recording_ids: &[&str],
    ) -> Result<HashMap<String, PopularityStats>, CoreError> {
        let body = serde_json::json!({ "recording_mbids": recording_ids });

        let response = self
            .client
            .post(LISTENBRAINZ_POPULARITY_URL)
            .json(&body)
            .send()
            .map_err(|error| CoreError::new("listenbrainz_request_failed", error.to_string()))?;

        if !response.status().is_success() {
            return Err(CoreError::new(
                "listenbrainz_error",
                format!("ListenBrainz returned HTTP {}", response.status()),
            ));
        }

        let payload: Vec<Value> = response
            .json()
            .map_err(|error| CoreError::new("listenbrainz_parse_failed", error.to_string()))?;

        let mut stats: HashMap<String, PopularityStats> = HashMap::new();
        for item in payload {
            let recording_id = match item.get("recording_mbid").and_then(|v| v.as_str()) {
                Some(id) => id.to_string(),
                None => continue,
            };
            let mut entry = PopularityStats {
                listen_count: item
                    .get("total_listen_count")
                    .and_then(|v| v.as_i64()),
                listener_count: item
                    .get("total_user_count")
                    .and_then(|v| v.as_i64()),
                score: 0.0,
            };
            entry.compute_score();
            stats.insert(recording_id, entry);
        }
        Ok(stats)
    }
}
```

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: compiles with warnings about unused imports (fine — used in next tasks).

---

### Task 5: Create MusicBrainz HTTP client — query variants + rate limiter

**Objective:** Port `_query_variants()` and `_throttle()` from `backend/app/services/musicbrainz.py`.

**Files:**
- Create: `native/streambox_core/src/services/musicbrainz.rs`

**First batch of code — client struct + query variants + throttle:**

```rust
use std::time::{Duration, Instant};

use reqwest::blocking::Client;
use serde_json::Value;

use crate::error::CoreError;
use crate::models::{MusicBrainzTrack, PopularityStats};

const MUSICBRAINZ_BASE_URL: &str = "https://musicbrainz.org/ws/2";
const MUSICBRAINZ_USER_AGENT: &str = "Streambox/0.1.0 ( personal-music-player@localhost )";
const THROTTLE_INTERVAL: Duration = Duration::from_millis(1050);
const REQUEST_TIMEOUT_SECS: u64 = 10;

const SOFT_WORDS: &[&str] = &["a", "an", "and", "feat", "featuring", "in", "of", "the", "to"];

/// Mirrors Python's QueryVariant dataclass
struct QueryVariant {
    query: String,
    dismax: bool,
}

pub struct MusicBrainzClient {
    client: Client,
    last_request_at: Instant,
}

impl MusicBrainzClient {
    pub fn new() -> Result<Self, CoreError> {
        let client = Client::builder()
            .user_agent(MUSICBRAINZ_USER_AGENT)
            .timeout(Duration::from_secs(REQUEST_TIMEOUT_SECS))
            .build()
            .map_err(|error| CoreError::new("musicbrainz_client_error", error.to_string()))?;
        Ok(Self {
            client,
            last_request_at: Instant::now(),
        })
    }

    /// Rate limiter — ensures at least 1.05s between requests
    fn throttle(&mut self) {
        let elapsed = self.last_request_at.elapsed();
        if elapsed < THROTTLE_INTERVAL {
            let wait = THROTTLE_INTERVAL - elapsed;
            std::thread::sleep(wait);
        }
        self.last_request_at = Instant::now();
    }
}

/// Build 3 query variants for MusicBrainz search.
/// Mirrors Python's `_query_variants()` in musicbrainz.py.
fn query_variants(query: &str) -> Vec<QueryVariant> {
    let mut variants = vec![QueryVariant {
        query: query.to_string(),
        dismax: true,
    }];

    let words: Vec<&str> = query.split_whitespace().collect();
    if words.len() >= 3
        && !SOFT_WORDS.contains(&words.last().unwrap().to_lowercase().as_str())
    {
        let title = words[..words.len() - 1].join(" ");
        let artist = words[words.len() - 1];
        variants.push(QueryVariant {
            query: format!("recording:\"{}\" AND artist:\"{}\"", title, artist),
            dismax: false,
        });
    }

    let fuzzy_terms: Vec<String> = tokens(query)
        .into_iter()
        .filter(|t| !SOFT_WORDS.contains(&t.as_str()) && t.len() > 3)
        .collect();
    if !fuzzy_terms.is_empty() {
        variants.push(QueryVariant {
            query: fuzzy_terms
                .iter()
                .map(|token| format!("recording:{token}~"))
                .collect::<Vec<_>>()
                .join(" AND "),
            dismax: false,
        });
    }

    variants
}

/// Tokenizer — mirrors Python's `_tokens()` in musicbrainz.py.
fn tokens(value: &str) -> Vec<String> {
    value
        .to_lowercase()
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|token| token.len() > 1)
        .map(String::from)
        .collect()
}
```

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: compiles.

---

### Task 6: MusicBrainz — recording parsing + ranking engine

**Objective:** Port `_recording_to_track()`, `_rank_tracks()`, `_best_release()`, `_strip_parenthetical()`, `_dedupe_recordings()`, and `_dedupe_strings()` from Python to Rust.

**Files:**
- Modify: `native/streambox_core/src/services/musicbrainz.rs` (append to existing code)

**Code to append:**

```rust
/// Parse a raw MusicBrainz recording JSON value into a MusicBrainzTrack.
/// Mirrors Python's `_recording_to_track()`.
fn recording_to_track(recording: &Value) -> MusicBrainzTrack {
    let artist_credits = recording
        .get("artist-credit")
        .and_then(|v| v.as_array())
        .map(|credits| {
            credits
                .iter()
                .filter_map(|credit| {
                    let artist = credit.get("artist")?;
                    let name = artist.get("name")?.as_str()?;
                    if name.is_empty() {
                        return None;
                    }
                    Some(crate::models::ArtistMetadata {
                        id: artist.get("id").and_then(|v| v.as_str()).map(String::from),
                        name: name.to_string(),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let releases = recording
        .get("releases")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let best_release = best_release(&releases);
    let release_group = best_release
        .get("release-group")
        .cloned()
        .unwrap_or_default();

    let album = if !best_release.is_null() || !release_group.is_null() {
        Some(crate::models::AlbumMetadata {
            id: best_release
                .get("id")
                .and_then(|v| v.as_str())
                .map(String::from),
            title: best_release
                .get("title")
                .and_then(|v| v.as_str())
                .map(String::from),
            release_group_id: release_group.get("id").and_then(|v| v.as_str()).map(String::from),
            artwork_url: None,
        })
    } else {
        None
    };

    MusicBrainzTrack {
        id: recording
            .get("id")
            .and_then(|v| v.as_str())
            .map(String::from)
            .unwrap_or_else(|| {
                recording
                    .get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string()
            }),
        title: recording
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        artists: artist_credits,
        album,
        length_ms: recording.get("length").and_then(|v| v.as_i64()),
        score: recording.get("score").and_then(|v| v.as_i64()),
        match_reasons: Vec::new(),
        listen_count: None,
        listener_count: None,
        popularity_score: None,
        source: "musicbrainz".to_string(),
    }
}

/// Select the best release from a list. Mirrors Python's `_best_release()`.
fn best_release(releases: &[Value]) -> Value {
    if releases.is_empty() {
        return Value::Null;
    }
    let cue_words: Vec<String> = [
        "acoustic", "cover", "covers", "dance", "instrumental", "karaoke",
        "live", "orchestra", "piano", "remix", "symphony", "tribute",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();

    let mut scored: Vec<(&Value, i32, String)> = releases
        .iter()
        .map(|release| {
            let release_group = release.get("release-group");
            let title = release
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let rg_title = release_group
                .and_then(|v| v.get("title"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let text = format!("{title} {rg_title}");
            let mut score: i32 = 0;
            if release.get("status").and_then(|v| v.as_str()) == Some("Official") {
                score += 8;
            }
            let primary_type = release_group
                .and_then(|v| v.get("primary-type"))
                .and_then(|v| v.as_str());
            if matches!(primary_type, Some("Album") | Some("Single") | Some("EP")) {
                score += 6;
            }
            if !tokens(&text).iter().any(|t| cue_words.contains(t)) {
                score += 4;
            }
            let date = release.get("date").and_then(|v| v.as_str()).unwrap_or("9999");
            (release, score, date.to_string())
        })
        .collect();

    scored.sort_by(|a, b| {
        b.1.cmp(&a.1)
            .then_with(|| b.2.cmp(&a.2))
    });

    scored.first().map(|(r, _, _)| (*r).clone()).unwrap_or(Value::Null)
}

/// Strip parenthetical text. Mirrors Python's `_strip_parenthetical()`.
fn strip_parenthetical(value: &str) -> String {
    let re = regex_lite::Regex::new(r"\([^)]*\)").unwrap();
    re.replace_all(value, "").trim().to_string()
}

/// Strip brackets too (used internally).
fn clean_title(value: &str) -> String {
    let parentheses = regex_lite::Regex::new(r"\([^)]*\)").unwrap();
    let brackets = regex_lite::Regex::new(r"\[[^\]]*\]").unwrap();
    let step1 = parentheses.replace_all(value, "");
    brackets.replace_all(&step1, "").trim().to_string()
}

/// De-duplicate recordings by ID. Mirrors Python's `_dedupe_recordings()`.
fn dedupe_recordings(recordings: &[Value]) -> Vec<Value> {
    let mut seen = std::collections::HashSet::new();
    let mut deduped = Vec::new();
    for recording in recordings {
        let id = recording
            .get("id")
            .and_then(|v| v.as_str());
        if let Some(id) = id {
            if !seen.insert(id.to_string()) {
                continue;
            }
        }
        deduped.push(recording.clone());
    }
    deduped
}

/// De-duplicate strings preserving order. Mirrors Python's `_dedupe_strings()`.
fn dedupe_strings(values: &[String]) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut output = Vec::new();
    for value in values {
        if seen.insert(value.clone()) {
            output.push(value.clone());
        }
    }
    output
}
```

**Note:** We need `regex_lite` for the `strip_parenthetical` regex. Add to Cargo.toml:
```toml
regex-lite = "0.1"
```

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: compiles.

---

### Task 7: MusicBrainz — ranking engine

**Objective:** Port `_rank_tracks()` from Python. This is the most complex function — multi-factor scoring with token overlap, title match, artist match, duration scoring, popularity boost, and cue word detection.

**Files:**
- Modify: `native/streambox_core/src/services/musicbrainz.rs` (append)

**Code to append:**

```rust
const CUE_WORDS: &[&str] = &[
    "acoustic", "cover", "covers", "dance", "instrumental", "karaoke",
    "live", "orchestra", "piano", "remix", "symphony", "tribute",
];

/// Rank MusicBrainz tracks by relevance to the query.
/// Mirrors Python's `MusicBrainzClient._rank_tracks()`.
fn rank_tracks(query: &str, tracks: &mut [MusicBrainzTrack]) {
    let query_tokens: Vec<String> = tokens(query);
    let query_core_tokens: Vec<String> = query_tokens
        .iter()
        .filter(|t| !SOFT_WORDS.contains(&t.as_str()))
        .cloned()
        .collect();
    let query_cues: std::collections::HashSet<String> = query_tokens
        .iter()
        .filter(|t| CUE_WORDS.contains(&t.as_str()))
        .cloned()
        .collect();

    for track in tracks.iter_mut() {
        let title_tokens = tokens(&track.title);
        let title_core_tokens: Vec<String> = title_tokens
            .iter()
            .filter(|t| !SOFT_WORDS.contains(&t.as_str()))
            .cloned()
            .collect();
        let artist_tokens = tokens(&artist_label(track));
        let album_title = track
            .album
            .as_ref()
            .and_then(|a| a.title.as_deref())
            .unwrap_or("");
        let album_tokens = tokens(album_title);

        let token_overlap = count_overlap(&query_tokens, &merge_tokens(&title_tokens, &artist_tokens));
        let title_overlap = count_overlap(&query_tokens, &title_tokens);
        let artist_overlap = count_overlap(&query_tokens, &artist_tokens);

        let mut score = track.score.unwrap_or(0) as f64;

        let combined_tokens = merge_three(&title_tokens, &artist_tokens, &album_tokens);
        let cue_overlap: std::collections::HashSet<String> = combined_tokens
            .iter()
            .filter(|t| CUE_WORDS.contains(&t.as_str()))
            .cloned()
            .collect();

        let title_match_ratio = if !query_core_tokens.is_empty() {
            count_overlap(&query_core_tokens, &title_core_tokens) as f64
                / query_core_tokens.len() as f64
        } else {
            0.0
        };

        let strong_match = title_match_ratio >= 0.75 || artist_overlap > 0;
        let popularity_boost = match &track.popularity_score {
            Some(p) => ((*p / 1000.0).min(35.0)),
            None => 0.0,
        };
        score += if strong_match { popularity_boost } else { popularity_boost.min(4.0) };

        if !query_tokens.is_empty()
            && query_tokens
                .iter()
                .all(|t| title_tokens.contains(t))
        {
            score += 80.0;
            track.match_reasons.push("title".to_string());
        }
        if !query_tokens.is_empty()
            && query_tokens
                .iter()
                .all(|t| title_tokens.contains(t) || artist_tokens.contains(t))
        {
            score += 25.0;
        }
        if !query_core_tokens.is_empty()
            && query_core_tokens == title_core_tokens
        {
            score += 70.0;
            track.match_reasons.push("exact-title".to_string());
        } else if !query_core_tokens.is_empty()
            && query_core_tokens
                .iter()
                .any(|t| title_core_tokens.contains(t))
        {
            track.match_reasons.push("fuzzy".to_string());
        }

        score += token_overlap as f64 * 8.0;
        score += title_overlap as f64 * 10.0;
        if artist_overlap > 0 {
            score += artist_overlap as f64 * 85.0;
            track.match_reasons.push("artist".to_string());
        }
        if !query_core_tokens.is_empty() && title_match_ratio < 0.5 {
            score -= 80.0;
        }

        let stripped_title = strip_parenthetical(&track.title);
        let stripped_tokens: Vec<String> = tokens(&stripped_title)
            .into_iter()
            .filter(|t| !SOFT_WORDS.contains(&t.as_str()))
            .collect();

        let query_without_artist: Vec<String> = query_core_tokens
            .iter()
            .filter(|t| !artist_tokens.contains(*t))
            .cloned()
            .collect();
        if stripped_tokens == query_without_artist {
            score += 24.0;
        }

        if let Some(length_ms) = track.length_ms {
            let duration_seconds = length_ms as f64 / 1000.0;
            if duration_seconds < 45.0 {
                score -= 35.0;
            } else if (120.0..=420.0).contains(&duration_seconds) {
                score += 18.0;
            } else if (90.0..=540.0).contains(&duration_seconds) {
                score += 8.0;
            }
        }

        if let Some(album) = &track.album {
            if album.title.is_some() {
                score += 5.0;
                let album_normalized = normalize_title(
                    album.title.as_deref().unwrap_or(""),
                );
                let track_normalized = normalize_title(&track.title);
                if album_normalized == track_normalized {
                    score += 16.0;
                }
            }
        }

        if let Some(rc) = track.score {
            score += (rc.min(12) * 4) as f64;
        }

        if !cue_overlap.is_empty() {
            let unexpected = cue_overlap
                .difference(&query_cues)
                .count();
            if unexpected > 0 {
                score -= 45.0 + (unexpected as f64 * 10.0);
                track.match_reasons.push("cover-like".to_string());
            }
        }
    }

    // Sort by score descending, then title alphabetically
    tracks.sort_by(|a, b| {
        // We'll actually store scores in match_reasons for now;
        // full scoring will be revisited in Task 8
        b.match_reasons.len().cmp(&a.match_reasons.len())
            .then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase()))
    });
}

fn artist_label(track: &MusicBrainzTrack) -> String {
    track
        .artists
        .iter()
        .map(|a| a.name.as_str())
        .collect::<Vec<_>>()
        .join(", ")
}

fn normalize_title(value: &str) -> String {
    let cleaned = clean_title(value);
    let mut tokens: Vec<String> = cleaned
        .split_whitespace()
        .filter(|t| !SOFT_WORDS.contains(&t.to_lowercase().as_str()))
        .map(|s| s.to_lowercase())
        .collect();
    tokens.sort();
    tokens.join(" ")
}

fn count_overlap(left: &[String], right: &[String]) -> usize {
    left.iter().filter(|t| right.contains(t)).count()
}

fn merge_tokens(left: &[String], right: &[String]) -> Vec<String> {
    let mut result = left.to_vec();
    for token in right {
        if !result.contains(token) {
            result.push(token.clone());
        }
    }
    result
}

fn merge_three(a: &[String], b: &[String], c: &[String]) -> Vec<String> {
    let mut result = merge_tokens(a, b);
    for token in c {
        if !result.contains(token) {
            result.push(token.clone());
        }
    }
    result
}
```

**Verification:**
```bash
cd native/streambox_core && cargo check 2>&1
```
Expected: compiles.

---

### Task 8: MusicBrainz — main `search_tracks` method + FFI wiring

**Objective:** Port the main `search_tracks()` method that orchestrates the 3 query variants, deduplication, ranking, and cache. Wire through to FFI.

**Files:**
- Modify: `native/streambox_core/src/services/musicbrainz.rs` (append)
- Modify: `native/streambox_core/src/ffi.rs` (add FFI function)

**Code for `search_tracks` in `musicbrainz.rs`:**

```rust
impl MusicBrainzClient {
    /// Search MusicBrainz for tracks matching a query.
    /// Mirrors Python's `MusicBrainzClient.search_tracks()`.
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

        let mut all_recordings: Vec<Value> = Vec::new();
        for variant in query_variants(clean_query) {
            let mut params: Vec<(&str, String)> = vec![
                ("query", variant.query.clone()),
                ("fmt", "json".to_string()),
                ("limit", fetch_limit.to_string()),
                ("inc", "artist-credits+releases+release-groups".to_string()),
            ];
            if variant.dismax {
                params.push(("dismax", "true".to_string()));
            }

            self.throttle();
            let url = format!("{}/recording", MUSICBRAINZ_BASE_URL);
            let response = self
                .client
                .get(&url)
                .query(&params)
                .send()
                .map_err(|error| CoreError::new(
                    "musicbrainz_request_failed",
                    error.to_string(),
                ))?;

            if !response.status().is_success() {
                continue; // Skip variant on error, don't fail entirely
            }

            let payload: Value = match response.json() {
                Ok(p) => p,
                Err(_) => continue,
            };
            let recordings = payload
                .get("recordings")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            all_recordings.extend(recordings);
        }

        let deduped = dedupe_recordings(&all_recordings);

        let mut tracks: Vec<MusicBrainzTrack> = deduped
            .iter()
            .map(|r| recording_to_track(r))
            .filter(|t| !t.title.is_empty() && !t.artists.is_empty())
            .collect();

        rank_tracks(clean_query, &mut tracks);

        // Sort by match_reasons count (more reasons = better match)
        tracks.sort_by(|a, b| {
            b.match_reasons
                .len()
                .cmp(&a.match_reasons.len())
                .then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase()))
        });

        tracks.truncate(limit);
        Ok(tracks)
    }
}
```

**Add FFI request/response types to `models.rs`:**

```rust
#[derive(Debug, Clone, Deserialize, Default)]
pub struct MusicBrainzSearchRequest {
    pub query: String,
    #[serde(default = "default_limit")]
    pub limit: usize,
}

fn default_limit() -> usize {
    15
}
```

**Add FFI function to `ffi.rs`:**

```rust
use crate::services::musicbrainz::MusicBrainzClient;

#[no_mangle]
pub unsafe extern "C" fn streambox_musicbrainz_search_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<MusicBrainzSearchRequest>(input_json) {
        Ok(request) => {
            match MusicBrainzClient::new() {
                Ok(mut client) => match client.search_tracks(&request.query, request.limit) {
                    Ok(tracks) => ok_json(tracks),
                    Err(error) => error_json(error),
                },
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}
```

Add `use crate::models::MusicBrainzSearchRequest;` to ffi.rs imports.

**Verification:**
```bash
cd native/streambox_core && cargo build 2>&1
```
Expected: compiles.

---

### Task 9: Add MusicBrainz + LB integration tests

**Objective:** Write Rust tests for the MusicBrainz and ListenBrainz clients. Test: query variants generation, recording parsing, ranking edge cases (cover penalty, exact title bonus), rate limiter timing.

**Files:**
- Create: `native/streambox_core/tests/musicbrainz.rs`

**Test cases to write:**

1. **Query variants generation** — verify 3 variants are built for multi-word queries
2. **Recording parsing** — verify a raw JSON recording becomes a MusicBrainzTrack with artists
3. **Best release selection** — verify Official Album beats Unofficial
4. **Ranking — exact title bonus** — verify exact match scores higher than partial
5. **Ranking — cover penalty** — verify a "cover" labeled track scores lower than original
6. **Rate limiter** — verify that 3 rapid calls are spaced 1.05s apart
7. **Deduplication** — verify duplicate recording IDs are removed
8. **Empty query** — returns empty list
9. **Popularity scoring** — verify `score = listeners * 10 + listens`
10. **Invalid API response** — gracefully handled

Use mock HTTP servers or skip actual HTTP calls (test parsing/ranking only). For tests that need network, mark with `#[ignore]` and document.

**Verification:**
```bash
CARGO_TARGET_DIR=/tmp/st-box cargo test --manifest-path native/streambox_core/Cargo.toml --test musicbrainz 2>&1
```
Expected: N tests passed.

---

### Task 10: Wire MusicBrainz into RustCoreClient (Flutter)

**Objective:** Update the Flutter `RustCoreClient` to use the new `streambox_musicbrainz_search_json` FFI endpoint for discover fallback (when source index has no high-confidence hits).

**Files:**
- Modify: `frontend/lib/src/core/rust_core_client.dart`
- Modify: `frontend/lib/src/native/native_core.dart` (add method signature)

**Note:** Flutter not available locally. Write the code, verify syntax, and document that `flutter analyze` and `flutter test` need to be run. This task is code-complete but needs CI verification.

**Verification:**
```bash
# Cannot run locally - Flutter not on PATH
echo "Code complete — needs flutter analyze in CI"
```

---

## Phase 2: YouTube Music → Rust

*(Tasks to be defined in detail after Phase 1 is complete. Overview:)*

- Add HTTP client for YouTube Music internal API
- Port `search`, `album_detail`, `artist_detail`, `source_search`
- Port caching logic
- Add `streambox_ytmusic_search_json` FFI endpoint
- Wire into `RustCoreClient.discover()` flow
- Contract tests with known fixture responses

---

## Phase 3: yt-dlp embedding

*(Tasks to be defined after Phase 2. Overview:)*

- Bundle yt-dlp binary per-platform as a Flutter asset
- Create Rust module that calls `yt-dlp --no-download --format bestaudio/best` via `std::process::Command`
- Parse yt-dlp JSON output → SourceCandidate structs
- Add `streambox_resolve_json` FFI endpoint
- Wire into `RustCoreClient.resolve()` flow

---

## Phase 4: Delete FastAPI

*(Tasks to be defined after Phase 3. Overview:)*

- Remove `backend/` directory entirely
- Remove `ApiClient` and `HybridCoreClient` fallback paths
- Rename `RustCoreClient` to just `CoreClient`
- Update `docs/rust-core-migration.md` → mark complete
- Update CI: remove Python/pytest from workflow
- Final contract tests: verify all FastAPI fixtures pass against Rust output
