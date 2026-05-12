use rusqlite::{params, Connection};
use serde_json::{json, Value};
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
fn migration_preserves_existing_playlist_rows() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("playlist.sqlite3");
    let track = sample_item("legacy-track", "Legacy Track");
    let connection = legacy_connection(&database_path);
    seed_playlist(&connection, &track);
    drop(connection);

    db::init_database(&database_path).unwrap();

    let playlists = db::list_playlists(&database_path).unwrap();
    assert_eq!(playlists.len(), 1);
    assert_eq!(playlists[0].id, "playlist-1");
    assert_eq!(playlists[0].name, "Legacy Playlist");
    assert_eq!(playlists[0].tracks, vec![track]);
}

#[test]
fn migration_preserves_existing_favorite_rows() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("favorite.sqlite3");
    let favorite_item = sample_json_item("favorite-track", "Favorite Track");
    let connection = legacy_connection(&database_path);
    seed_favorite(&connection, &favorite_item);
    drop(connection);

    db::init_database(&database_path).unwrap();

    let favorites = db::list_favorites(&database_path).unwrap();
    assert_eq!(favorites.len(), 1);
    assert_eq!(favorites[0].id, "favorite-1");
    assert_eq!(favorites[0].item, favorite_item);
}

#[test]
fn migration_preserves_existing_history_rows() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("history.sqlite3");
    let history_item = sample_json_item("history-track", "History Track");
    let connection = legacy_connection(&database_path);
    seed_history(&connection, &history_item);
    drop(connection);

    db::init_database(&database_path).unwrap();

    let core_db = db::CoreDb::open(Some(database_path.to_str().unwrap())).unwrap();
    let history = core_db.list_history(10).unwrap();
    assert_eq!(history, vec![history_item]);
}

#[test]
fn migration_repairs_legacy_source_index_payload_schema() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("legacy-source-index.sqlite3");
    let connection = Connection::open(&database_path).unwrap();
    create_v1_v2_schema(&connection);
    connection
        .execute_batch(
            r#"
            CREATE TABLE metadata_cache(
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE TABLE source_index(
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL DEFAULT '',
                artist TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                payload TEXT NOT NULL
            );
            INSERT INTO source_index(id, title, artist, album, payload)
            VALUES ('legacy', 'Bad', 'Legacy', '', '{}');
            "#,
        )
        .unwrap();
    connection
        .pragma_update(None, "user_version", 3_i64)
        .unwrap();
    drop(connection);

    db::init_database(&database_path).unwrap();

    let connection = Connection::open(&database_path).unwrap();
    assert_eq!(user_version(&connection), SCHEMA_VERSION);
    assert!(table_columns(&connection, "source_index").contains(&"source_provider".to_string()));
    let legacy_count: i64 = connection
        .query_row("SELECT COUNT(*) FROM source_index", [], |row| row.get(0))
        .unwrap();
    assert_eq!(legacy_count, 0);
}

#[test]
fn migration_rejects_newer_schema_versions() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("future.sqlite3");
    let connection = Connection::open(&database_path).unwrap();
    connection
        .pragma_update(None, "user_version", SCHEMA_VERSION + 1)
        .unwrap();
    drop(connection);

    let error = db::init_database(&database_path).unwrap_err();

    assert_eq!(error.code, "unsupported_schema_version");
}

fn legacy_connection(database_path: &std::path::Path) -> Connection {
    let connection = Connection::open(database_path).unwrap();
    create_v1_v2_schema(&connection);
    connection
        .pragma_update(None, "user_version", 0_i64)
        .unwrap();
    connection
}

fn seed_playlist(connection: &Connection, track: &PlaybackItem) {
    let track_json = serde_json::to_string(track).unwrap();
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
}

fn seed_favorite(connection: &Connection, favorite_item: &Value) {
    let favorite_json = serde_json::to_string(favorite_item).unwrap();
    connection
        .execute(
            "INSERT INTO favorites(id, item_json, created_at) VALUES (?, ?, ?)",
            params!["favorite-1", favorite_json, 1_700_000_002_i64],
        )
        .unwrap();
}

fn seed_history(connection: &Connection, history_item: &Value) {
    let history_json = serde_json::to_string(history_item).unwrap();
    connection
        .execute(
            "INSERT INTO history(id, item_json, played_at) VALUES (?, ?, ?)",
            params!["history-1", history_json, 1_700_000_003_i64],
        )
        .unwrap();
}

fn sample_json_item(id: &str, title: &str) -> Value {
    json!({
        "id": id,
        "track": {"id": id, "title": title},
        "source": null,
        "added_at": "2026-05-12T00:00:00Z"
    })
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

fn table_columns(connection: &Connection, name: &str) -> Vec<String> {
    let mut statement = connection
        .prepare(&format!("PRAGMA table_info({name})"))
        .unwrap();
    statement
        .query_map([], |row| row.get::<_, String>(1))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
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
