use rusqlite::{params, Connection};
use serde_json::json;
use streambox_core::db::{self, SCHEMA_VERSION};
use streambox_core::models::PlaybackItem;

#[test]
fn empty_database_initializes_current_schema() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("empty.sqlite3");

    db::init_database(&database_path).unwrap();

    let connection = Connection::open(&database_path).unwrap();
    assert_eq!(user_version(&connection), SCHEMA_VERSION);
    assert_tables_exist(
        &connection,
        &[
            "playlists",
            "playlist_tracks",
            "favorites",
            "history",
            "metadata_cache",
            "source_index",
            "source_index_fts",
        ],
    );

    let source_index_version: String = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = 'source-index:schema-version:v4'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(source_index_version, "\"4\"");
}

#[test]
fn older_user_version_upgrades_incrementally_to_current_schema() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("v2.sqlite3");
    let connection = Connection::open(&database_path).unwrap();
    create_v1_v2_schema(&connection);
    connection
        .pragma_update(None, "user_version", 2_i64)
        .unwrap();
    drop(connection);

    db::init_database(&database_path).unwrap();

    let connection = Connection::open(&database_path).unwrap();
    assert_eq!(user_version(&connection), SCHEMA_VERSION);
    assert_tables_exist(
        &connection,
        &["metadata_cache", "source_index", "source_index_fts"],
    );
}

#[test]
fn fastapi_initialized_metadata_cache_upgrades_for_rust_source_index() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("fastapi.sqlite3");
    let connection = Connection::open(&database_path).unwrap();
    create_fastapi_schema(&connection);
    drop(connection);

    db::init_database(&database_path).unwrap();

    let connection = Connection::open(&database_path).unwrap();
    assert_eq!(user_version(&connection), SCHEMA_VERSION);
    assert_tables_exist(
        &connection,
        &["metadata_cache", "source_index", "source_index_fts"],
    );
    assert_table_columns(
        &connection,
        "metadata_cache",
        &["cache_key", "payload", "created_at", "updated_at"],
    );

    let source_index_version: String = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = 'source-index:schema-version:v4'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(source_index_version, "\"4\"");
}

#[test]
fn migration_preserves_existing_playlist_favorite_and_history_data() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("legacy.sqlite3");
    let connection = Connection::open(&database_path).unwrap();
    create_v1_v2_schema(&connection);

    let track = sample_item("legacy-track", "Legacy Track");
    let track_json = serde_json::to_string(&track).unwrap();
    let favorite_item = json!({
        "id": "favorite-track",
        "track": {"id": "favorite-track", "title": "Favorite Track"},
        "source": null,
        "added_at": "2026-05-12T00:00:00Z"
    });
    let favorite_json = serde_json::to_string(&favorite_item).unwrap();
    let history_item = json!({
        "id": "history-track",
        "track": {"id": "history-track", "title": "History Track"},
        "source": null,
        "added_at": "2026-05-12T00:00:00Z"
    });
    let history_json = serde_json::to_string(&history_item).unwrap();

    connection
        .execute(
            "INSERT INTO playlists(id, name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            params!["playlist-1", "Legacy Playlist", "Keep me", 1_700_000_000_i64, 1_700_000_001_i64],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO playlist_tracks(playlist_id, position, item_json) VALUES (?, ?, ?)",
            params!["playlist-1", 0_i64, track_json],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO favorites(id, item_json, created_at) VALUES (?, ?, ?)",
            params!["favorite-1", favorite_json, 1_700_000_002_i64],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO history(id, item_json, played_at) VALUES (?, ?, ?)",
            params!["history-1", history_json, 1_700_000_003_i64],
        )
        .unwrap();
    connection
        .pragma_update(None, "user_version", 0_i64)
        .unwrap();
    drop(connection);

    db::init_database(&database_path).unwrap();

    let playlists = db::list_playlists(&database_path).unwrap();
    assert_eq!(playlists.len(), 1);
    assert_eq!(playlists[0].id, "playlist-1");
    assert_eq!(playlists[0].name, "Legacy Playlist");
    assert_eq!(playlists[0].tracks, vec![track]);

    let favorites = db::list_favorites(&database_path).unwrap();
    assert_eq!(favorites.len(), 1);
    assert_eq!(favorites[0].id, "favorite-1");
    assert_eq!(favorites[0].item, favorite_item);

    let core_db = db::CoreDb::open(Some(database_path.to_str().unwrap())).unwrap();
    let history = core_db.list_history(10).unwrap();
    assert_eq!(history, vec![history_item]);
}

fn create_v1_v2_schema(connection: &Connection) {
    connection
        .execute_batch(
            r#"
            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                played_at INTEGER NOT NULL
            );

            CREATE TABLE favorites (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE playlist_tracks (
                playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                item_json TEXT NOT NULL,
                PRIMARY KEY (playlist_id, position)
            );
            "#,
        )
        .unwrap();
}

fn create_fastapi_schema(connection: &Connection) {
    connection
        .execute_batch(
            r#"
            CREATE TABLE metadata_cache (
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE playlist_tracks (
                playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                item_json TEXT NOT NULL,
                PRIMARY KEY (playlist_id, position)
            );

            CREATE TABLE favorites (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE history (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                played_at INTEGER NOT NULL
            );

            CREATE TABLE source_index (
                source_provider TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                duration_seconds REAL,
                normalized_text TEXT NOT NULL,
                confidence_score REAL NOT NULL DEFAULT 0,
                rank_reason TEXT NOT NULL DEFAULT '',
                artwork_url TEXT NOT NULL DEFAULT '',
                source_kind TEXT NOT NULL DEFAULT '',
                raw_title TEXT NOT NULL DEFAULT '',
                canonical_title TEXT NOT NULL DEFAULT '',
                canonical_artist TEXT NOT NULL DEFAULT '',
                parse_source TEXT NOT NULL DEFAULT '',
                last_matched_at INTEGER NOT NULL,
                PRIMARY KEY (source_provider, source_id)
            );
            "#,
        )
        .unwrap();
}

fn assert_tables_exist(connection: &Connection, expected_tables: &[&str]) {
    for table in expected_tables {
        let exists: bool = connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type IN ('table', 'virtual table') AND name = ?)",
                [table],
                |row| row.get(0),
            )
            .unwrap();
        assert!(exists, "missing table {table}");
    }
}

fn assert_table_columns(connection: &Connection, table_name: &str, expected_columns: &[&str]) {
    let columns = connection
        .prepare(&format!("PRAGMA table_info({table_name})"))
        .unwrap()
        .query_map([], |row| row.get::<_, String>(1))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();

    for column in expected_columns {
        assert!(
            columns.iter().any(|existing| existing == column),
            "missing column {column}; found {columns:?}"
        );
    }
}

fn user_version(connection: &Connection) -> i64 {
    connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .unwrap()
}

fn sample_item(id: &str, title: &str) -> PlaybackItem {
    PlaybackItem {
        id: format!("playback-{id}"),
        track: json!({
            "id": id,
            "title": title,
            "artists": [{"id": "artist-1", "name": "Artist"}],
            "source": "musicbrainz"
        }),
        source: Some(json!({
            "adapter": "direct_url",
            "url": "https://example.invalid/audio.mp3",
            "title": title,
            "headers": {}
        })),
        added_at: "2026-05-12T00:00:00Z".to_string(),
    }
}
