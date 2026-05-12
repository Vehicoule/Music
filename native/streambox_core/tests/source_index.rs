use rusqlite::Connection;
use streambox_core::db::{
    rebuild_source_index, search_source_index_entries, upsert_source_index_entries,
    SOURCE_INDEX_SCHEMA_KEY,
};
use streambox_core::models::SourceIndexEntry;
use tempfile::tempdir;

fn entry(source_id: &str, title: &str, artist: &str) -> SourceIndexEntry {
    SourceIndexEntry {
        source_provider: "youtube".to_string(),
        source_id: source_id.to_string(),
        source_url: format!("https://www.youtube.com/watch?v={source_id}"),
        title: title.to_string(),
        artist: artist.to_string(),
        album: String::new(),
        duration_seconds: Some(228.0),
        confidence_score: 0.0,
        rank_reason: String::new(),
        artwork_url: String::new(),
        source_kind: "song".to_string(),
        raw_title: String::new(),
        canonical_title: title.to_string(),
        canonical_artist: artist.to_string(),
        parse_source: "structured".to_string(),
    }
}

#[test]
fn source_index_ranking_prefers_artist_match_over_cover() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("streambox.sqlite3");
    let cover = SourceIndexEntry {
        album: "Piano Cover".to_string(),
        source_kind: "video".to_string(),
        ..entry("cover", "Rolling in the Deep", "The Piano Guys")
    };
    let original = entry("adele", "Rolling in the Deep", "Adele");
    upsert_source_index_entries(&path, &[cover, original]).unwrap();

    let results =
        search_source_index_entries(&path, "rolling in the deep adele", 10, Some("all")).unwrap();

    assert_eq!(results[0].source_id, "adele");
    assert!(results[0].rank_reason.contains("artist"));
}

#[test]
fn source_index_search_filters_by_scope() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("streambox.sqlite3");
    let song = SourceIndexEntry {
        source_provider: "ytmusic".to_string(),
        source_kind: "song".to_string(),
        ..entry("song-1", "Bella", "GIMS")
    };
    let video = SourceIndexEntry {
        source_provider: "ytmusic".to_string(),
        source_kind: "video".to_string(),
        ..entry("video-1", "Bella live", "GIMS")
    };
    upsert_source_index_entries(&path, &[song, video]).unwrap();

    let songs = search_source_index_entries(&path, "bella gims", 10, Some("songs")).unwrap();
    let videos = search_source_index_entries(&path, "bella gims", 10, Some("videos")).unwrap();

    assert_eq!(
        songs
            .iter()
            .map(|entry| entry.source_kind.as_str())
            .collect::<Vec<_>>(),
        vec!["song"]
    );
    assert_eq!(
        videos
            .iter()
            .map(|entry| entry.source_kind.as_str())
            .collect::<Vec<_>>(),
        vec!["video"]
    );
}

#[test]
fn source_index_schema_accepts_fastapi_metadata_cache() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("streambox.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch(
            "CREATE TABLE metadata_cache(
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );",
        )
        .unwrap();
    drop(connection);

    let status = rebuild_source_index(&path).unwrap();
    assert!(status.rebuilt);

    let connection = Connection::open(&path).unwrap();
    let version: String = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = ?",
            [SOURCE_INDEX_SCHEMA_KEY],
            |row| row.get(0),
        )
        .unwrap();
    let updated_at: i64 = connection
        .query_row(
            "SELECT updated_at FROM metadata_cache WHERE cache_key = ?",
            [SOURCE_INDEX_SCHEMA_KEY],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(version, "\"4\"");
    assert!(updated_at > 0);
}

#[test]
fn source_index_schema_rebuilds_legacy_payload_table() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("streambox.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch(
            "CREATE TABLE metadata_cache(cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL);
             CREATE TABLE source_index(id TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', artist TEXT NOT NULL DEFAULT '', album TEXT NOT NULL DEFAULT '', payload TEXT NOT NULL);
             INSERT INTO source_index(id, title, artist, album, payload) VALUES ('legacy', 'Bad', 'Legacy', '', '{}');",
        )
        .unwrap();
    drop(connection);

    let status = rebuild_source_index(&path).unwrap();
    assert!(status.rebuilt);

    let connection = Connection::open(&path).unwrap();
    let version: String = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = ?",
            [SOURCE_INDEX_SCHEMA_KEY],
            |row| row.get(0),
        )
        .unwrap();
    let count: i64 = connection
        .query_row("SELECT COUNT(*) FROM source_index", [], |row| row.get(0))
        .unwrap();

    assert_eq!(version, "\"4\"");
    assert_eq!(count, 0);
}
