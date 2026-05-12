use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::Value;

use crate::error::CoreError;
use crate::models::{
    DbHealth, Favorite, PlaybackItem, Playlist, PlaylistCreate, PlaylistUpdate, SourceIndexEntry,
    SourceIndexSchemaStatus,
};

pub const SCHEMA_VERSION: i64 = 5;
pub const SOURCE_INDEX_SCHEMA_KEY: &str = "source-index:schema-version:v4";
pub const SOURCE_INDEX_SCHEMA_VERSION: &str = "4";

static ID_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct CoreDb {
    connection: Connection,
}

impl CoreDb {
    pub fn open(path: Option<&str>) -> Result<Self, CoreError> {
        let path = resolve_db_path(path)?;
        let mut connection = connect(&path)?;
        init_schema(&mut connection)?;
        Ok(Self { connection })
    }

    pub fn list_history(&self, limit: usize) -> Result<Vec<Value>, CoreError> {
        let mut statement = self
            .connection
            .prepare("SELECT item_json FROM history ORDER BY played_at DESC, rowid DESC LIMIT ?")
            .map_err(|error| CoreError::new("history_list_failed", error.to_string()))?;
        let rows = statement
            .query_map(params![limit as i64], |row| row.get::<_, String>(0))
            .map_err(|error| CoreError::new("history_list_failed", error.to_string()))?;

        let mut items = Vec::new();
        for row in rows {
            let item_json =
                row.map_err(|error| CoreError::new("history_list_failed", error.to_string()))?;
            let item = serde_json::from_str(&item_json)
                .map_err(|error| CoreError::new("history_decode_failed", error.to_string()))?;
            items.push(item);
        }
        Ok(items)
    }

    pub fn add_history(&self, item: Value) -> Result<Value, CoreError> {
        let item_json = serde_json::to_string(&item)
            .map_err(|error| CoreError::new("history_encode_failed", error.to_string()))?;
        self.connection
            .execute(
                "INSERT INTO history(id, item_json, played_at) VALUES (?, ?, ?)",
                params![new_id("history")?, item_json, unix_seconds()?],
            )
            .map_err(|error| CoreError::new("history_add_failed", error.to_string()))?;
        Ok(item)
    }

    pub fn clear_history(&self) -> Result<(), CoreError> {
        self.connection
            .execute("DELETE FROM history", [])
            .map_err(|error| CoreError::new("history_clear_failed", error.to_string()))?;
        Ok(())
    }

    pub fn prune_history(&self, keep: usize) -> Result<usize, CoreError> {
        let changed = self
            .connection
            .execute(
                "DELETE FROM history
                 WHERE rowid NOT IN (
                    SELECT rowid FROM history ORDER BY played_at DESC, rowid DESC LIMIT ?
                 )",
                params![keep as i64],
            )
            .map_err(|error| CoreError::new("history_prune_failed", error.to_string()))?;
        Ok(changed)
    }
}

pub struct StreamboxDb {
    database_path: PathBuf,
}

impl StreamboxDb {
    pub fn new(database_path: Option<PathBuf>) -> Self {
        Self {
            database_path: database_path.unwrap_or_else(default_database_path),
        }
    }

    pub fn list_favorites(&self) -> Result<Vec<Favorite>, CoreError> {
        list_favorites(&self.database_path)
    }

    pub fn add_favorite(&self, item: Value) -> Result<Favorite, CoreError> {
        add_favorite(&self.database_path, item)
    }

    pub fn remove_favorite(&self, id: &str) -> Result<(), CoreError> {
        remove_favorite(&self.database_path, id)
    }
}

pub fn default_database_path() -> PathBuf {
    std::env::var_os("DATABASE_PATH")
        .or_else(|| std::env::var_os("STREAMBOX_DATABASE_PATH"))
        .or_else(|| std::env::var_os("STREAMBOX_DB_PATH"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("./data/streambox.sqlite3"))
}

pub fn init_database(path: impl AsRef<Path>) -> Result<(), CoreError> {
    let mut connection = connect(path.as_ref())?;
    init_schema(&mut connection)
}

pub fn db_health(path: impl AsRef<Path>) -> Result<DbHealth, CoreError> {
    init_database(path.as_ref())?;
    let connection = connect(path.as_ref())?;
    let user_version = connection
        .pragma_query_value(None, "user_version", |row| row.get::<_, i64>(0))
        .map_err(sql_error)?;
    let foreign_keys_enabled = connection
        .pragma_query_value(None, "foreign_keys", |row| row.get::<_, i64>(0))
        .map_err(sql_error)?
        == 1;
    Ok(DbHealth {
        path: path.as_ref().to_string_lossy().into_owned(),
        schema_version: SCHEMA_VERSION,
        user_version,
        foreign_keys_enabled,
    })
}

pub fn list_playlists(path: impl AsRef<Path>) -> Result<Vec<Playlist>, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let mut statement = connection
        .prepare("SELECT id FROM playlists ORDER BY updated_at DESC, rowid DESC")
        .map_err(sql_error)?;
    let ids = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)?;
    ids.iter()
        .map(|id| load_playlist(&connection, id))
        .collect()
}

pub fn create_playlist(
    path: impl AsRef<Path>,
    payload: PlaylistCreate,
) -> Result<Playlist, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let now = now_iso8601()?;
    let playlist = Playlist {
        id: new_id("playlist")?,
        name: payload.name,
        description: payload.description,
        tracks: payload.tracks,
        created_at: now.clone(),
        updated_at: now,
    };
    save_playlist(&connection, &playlist)?;
    Ok(playlist)
}

pub fn update_playlist(
    path: impl AsRef<Path>,
    payload: PlaylistUpdate,
) -> Result<Playlist, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let mut playlist = load_playlist(&connection, &payload.id)?;
    if let Some(name) = payload.name {
        playlist.name = name;
    }
    if let Some(description) = payload.description {
        playlist.description = description;
    }
    if let Some(tracks) = payload.tracks {
        playlist.tracks = tracks;
    }
    playlist.updated_at = now_iso8601()?;
    save_playlist(&connection, &playlist)?;
    Ok(playlist)
}

pub fn delete_playlist(path: impl AsRef<Path>, playlist_id: &str) -> Result<(), CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let changed = connection
        .execute("DELETE FROM playlists WHERE id = ?", params![playlist_id])
        .map_err(sql_error)?;
    if changed == 0 {
        Err(CoreError::new("not_found", "Playlist not found"))
    } else {
        Ok(())
    }
}

pub fn list_favorites(path: impl AsRef<Path>) -> Result<Vec<Favorite>, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let mut statement = connection
        .prepare(
            "SELECT id, item_json, created_at FROM favorites ORDER BY created_at DESC, rowid DESC",
        )
        .map_err(sql_error)?;
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .map_err(sql_error)?;

    rows.map(|row| {
        let (id, item_json, created_at) = row.map_err(sql_error)?;
        let item = serde_json::from_str(&item_json)
            .map_err(|error| CoreError::new("invalid_favorite_item", error.to_string()))?;
        Ok(Favorite {
            id,
            item,
            created_at: timestamp_to_iso8601(created_at),
        })
    })
    .collect()
}

pub fn add_favorite(path: impl AsRef<Path>, item: Value) -> Result<Favorite, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let id = new_id("favorite")?;
    let created_at = unix_seconds()?;
    let item_json = serde_json::to_string(&item)
        .map_err(|error| CoreError::new("favorite_encode_failed", error.to_string()))?;
    connection
        .execute(
            "INSERT INTO favorites(id, item_json, created_at) VALUES (?, ?, ?)",
            params![id, item_json, created_at],
        )
        .map_err(sql_error)?;
    Ok(Favorite {
        id,
        item,
        created_at: timestamp_to_iso8601(created_at),
    })
}

pub fn remove_favorite(path: impl AsRef<Path>, favorite_id: &str) -> Result<(), CoreError> {
    let connection = open_initialized(path.as_ref())?;
    connection
        .execute("DELETE FROM favorites WHERE id = ?", params![favorite_id])
        .map_err(sql_error)?;
    Ok(())
}

fn open_initialized(path: &Path) -> Result<Connection, CoreError> {
    let mut connection = connect(path)?;
    init_schema(&mut connection)?;
    Ok(connection)
}

fn connect(path: &Path) -> Result<Connection, CoreError> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)
            .map_err(|error| CoreError::new("database_open_failed", error.to_string()))?;
    }
    let connection = Connection::open(path).map_err(sql_error)?;
    connection
        .execute_batch("PRAGMA foreign_keys = ON;")
        .map_err(sql_error)?;
    Ok(connection)
}

fn init_schema(connection: &mut Connection) -> Result<(), CoreError> {
    let current_version = connection
        .pragma_query_value(None, "user_version", |row| row.get::<_, i64>(0))
        .map_err(sql_error)?;

    if current_version > SCHEMA_VERSION {
        return Err(CoreError::new(
            "unsupported_schema_version",
            format!(
                "Database schema version {current_version} is newer than supported version {SCHEMA_VERSION}"
            ),
        ));
    }

    if current_version == SCHEMA_VERSION {
        return Ok(());
    }

    let transaction = connection.transaction().map_err(sql_error)?;
    for version in (current_version + 1)..=SCHEMA_VERSION {
        match version {
            1 => migrate_to_v1(&transaction)?,
            2 => migrate_to_v2(&transaction)?,
            3 => migrate_to_v3(&transaction)?,
            4 => migrate_to_v4(&transaction)?,
            5 => migrate_to_v5(&transaction)?,
            _ => {
                return Err(CoreError::new(
                    "unsupported_schema_version",
                    format!("No migration registered for schema version {version}"),
                ));
            }
        }
    }
    transaction
        .pragma_update(None, "user_version", SCHEMA_VERSION)
        .map_err(sql_error)?;
    transaction.commit().map_err(sql_error)
}

fn migrate_to_v1(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    transaction
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                played_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS favorites (
                id TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            "#,
        )
        .map_err(sql_error)
}

fn migrate_to_v2(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    transaction
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS playlists (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS playlist_tracks (
                playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                item_json TEXT NOT NULL,
                PRIMARY KEY (playlist_id, position)
            );
            "#,
        )
        .map_err(sql_error)
}

fn migrate_to_v3(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    transaction
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS metadata_cache (
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            "#,
        )
        .map_err(sql_error)?;
    ensure_metadata_cache_schema(transaction)
}

fn migrate_to_v4(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    ensure_metadata_cache_schema(transaction)?;
    ensure_source_index_schema(transaction)?;
    sync_source_index_schema_version(transaction)
}

fn migrate_to_v5(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    ensure_source_index_schema(transaction)?;
    transaction
        .execute_batch(
            r#"
            CREATE INDEX IF NOT EXISTS idx_favorites_created_at
            ON favorites(created_at DESC);

            CREATE INDEX IF NOT EXISTS idx_history_played_at
            ON history(played_at DESC);

            CREATE INDEX IF NOT EXISTS idx_playlists_updated_at
            ON playlists(updated_at DESC);

            CREATE INDEX IF NOT EXISTS idx_source_index_last_matched_at
            ON source_index(last_matched_at DESC);

            CREATE INDEX IF NOT EXISTS idx_source_index_source_kind
            ON source_index(source_kind);

            DROP TABLE IF EXISTS source_index_fts;
            CREATE VIRTUAL TABLE source_index_fts
            USING fts5(source_provider UNINDEXED, source_id UNINDEXED, normalized_text);

            INSERT INTO source_index_fts(source_provider, source_id, normalized_text)
            SELECT source_provider, source_id, normalized_text FROM source_index;
            "#,
        )
        .map_err(sql_error)
}

fn ensure_metadata_cache_schema(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    let columns = table_columns(transaction, "metadata_cache")?;
    if !columns.iter().any(|column| column == "cache_key")
        || !columns.iter().any(|column| column == "payload")
    {
        return Err(CoreError::new(
            "incompatible_schema",
            "metadata_cache table is missing required columns",
        ));
    }
    if columns.iter().any(|column| column == "updated_at") {
        transaction
            .execute_batch(
                r#"
                ALTER TABLE metadata_cache RENAME TO metadata_cache_legacy;
                CREATE TABLE metadata_cache (
                    cache_key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                INSERT OR REPLACE INTO metadata_cache(cache_key, payload, created_at)
                SELECT cache_key, payload, COALESCE(updated_at, strftime('%s', 'now'))
                FROM metadata_cache_legacy;
                DROP TABLE metadata_cache_legacy;
                "#,
            )
            .map_err(sql_error)?;
    } else if !columns.iter().any(|column| column == "created_at") {
        transaction
            .execute_batch(
                r#"
                ALTER TABLE metadata_cache ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
                UPDATE metadata_cache
                SET created_at = COALESCE(NULLIF(created_at, 0), strftime('%s', 'now'));
                "#,
            )
            .map_err(sql_error)?;
    }
    Ok(())
}

fn ensure_source_index_schema(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    if table_exists(transaction, "source_index")?
        && !source_index_schema_is_compatible(transaction)?
    {
        transaction
            .execute_batch(
                r#"
                DROP TABLE IF EXISTS source_index_fts;
                DROP TABLE IF EXISTS source_index;
                "#,
            )
            .map_err(sql_error)?;
    }

    transaction
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS source_index (
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
        .map_err(sql_error)
}

fn sync_source_index_schema_version(
    transaction: &rusqlite::Transaction<'_>,
) -> Result<(), CoreError> {
    let payload = serde_json::to_string(SOURCE_INDEX_SCHEMA_VERSION)
        .map_err(|error| CoreError::new("source_index_schema_encode_failed", error.to_string()))?;
    transaction
        .execute(
            "INSERT INTO metadata_cache(cache_key, payload, created_at)
             VALUES (?, ?, strftime('%s', 'now'))
             ON CONFLICT(cache_key) DO UPDATE SET
                payload = excluded.payload,
                created_at = excluded.created_at",
            params![SOURCE_INDEX_SCHEMA_KEY, payload],
        )
        .map_err(sql_error)?;
    Ok(())
}

fn source_index_schema_is_compatible(
    transaction: &rusqlite::Transaction<'_>,
) -> Result<bool, CoreError> {
    let columns = table_columns(transaction, "source_index")?;
    let required = [
        "source_provider",
        "source_id",
        "source_url",
        "title",
        "artist",
        "album",
        "duration_seconds",
        "normalized_text",
        "confidence_score",
        "rank_reason",
        "artwork_url",
        "source_kind",
        "raw_title",
        "canonical_title",
        "canonical_artist",
        "parse_source",
        "last_matched_at",
    ];
    Ok(required
        .iter()
        .all(|required_column| columns.iter().any(|column| column == required_column)))
}

fn table_exists(connection: &Connection, name: &str) -> Result<bool, CoreError> {
    connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type IN ('table', 'virtual table') AND name = ?)",
            [name],
            |row| row.get(0),
        )
        .map_err(sql_error)
}

fn table_columns(connection: &Connection, name: &str) -> Result<Vec<String>, CoreError> {
    let mut statement = connection
        .prepare(&format!("PRAGMA table_info({name})"))
        .map_err(sql_error)?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(sql_error)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(sql_error)
}

fn load_playlist(connection: &Connection, playlist_id: &str) -> Result<Playlist, CoreError> {
    let row = connection
        .query_row(
            "SELECT id, name, description, created_at, updated_at FROM playlists WHERE id = ?",
            params![playlist_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            },
        )
        .optional()
        .map_err(sql_error)?
        .ok_or_else(|| CoreError::new("not_found", "Playlist not found"))?;

    let mut track_statement = connection
        .prepare("SELECT item_json FROM playlist_tracks WHERE playlist_id = ? ORDER BY position")
        .map_err(sql_error)?;
    let tracks = track_statement
        .query_map(params![playlist_id], |row| row.get::<_, String>(0))
        .map_err(sql_error)?
        .map(|result| {
            let json = result.map_err(sql_error)?;
            serde_json::from_str::<PlaybackItem>(&json)
                .map_err(|error| CoreError::new("invalid_playlist_item", error.to_string()))
        })
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Playlist {
        id: row.0,
        name: row.1,
        description: row.2,
        tracks,
        created_at: timestamp_to_iso8601(row.3),
        updated_at: timestamp_to_iso8601(row.4),
    })
}

fn save_playlist(connection: &Connection, playlist: &Playlist) -> Result<(), CoreError> {
    let created_at = iso8601_to_timestamp(&playlist.created_at)?;
    let updated_at = iso8601_to_timestamp(&playlist.updated_at)?;
    connection
        .execute(
            "INSERT INTO playlists(id, name, description, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                updated_at = excluded.updated_at",
            params![
                playlist.id,
                playlist.name,
                playlist.description,
                created_at,
                updated_at
            ],
        )
        .map_err(sql_error)?;
    connection
        .execute(
            "DELETE FROM playlist_tracks WHERE playlist_id = ?",
            params![playlist.id],
        )
        .map_err(sql_error)?;
    for (position, item) in playlist.tracks.iter().enumerate() {
        let item_json = serde_json::to_string(item)
            .map_err(|error| CoreError::new("playlist_item_encode_failed", error.to_string()))?;
        connection
            .execute(
                "INSERT INTO playlist_tracks(playlist_id, position, item_json) VALUES (?, ?, ?)",
                params![playlist.id, position as i64, item_json],
            )
            .map_err(sql_error)?;
    }
    Ok(())
}

pub fn upsert_source_index_entries(
    path: impl AsRef<Path>,
    entries: &[SourceIndexEntry],
) -> Result<usize, CoreError> {
    let mut connection = open_initialized(path.as_ref())?;
    let tx = connection.transaction().map_err(sql_error)?;
    ensure_source_index_schema_runtime(&tx)?;
    let now = unix_seconds()?;
    for entry in entries {
        if entry.source_provider.trim().is_empty()
            || entry.source_id.trim().is_empty()
            || entry.source_url.trim().is_empty()
        {
            continue;
        }
        let normalized_text =
            normalize_text(&format!("{} {} {}", entry.artist, entry.title, entry.album));
        tx.execute(
            "INSERT INTO source_index(
                source_provider, source_id, source_url, title, artist, album, duration_seconds,
                normalized_text, confidence_score, rank_reason, artwork_url, source_kind, raw_title,
                canonical_title, canonical_artist, parse_source, last_matched_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(source_provider, source_id) DO UPDATE SET
                source_url = excluded.source_url,
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_seconds = excluded.duration_seconds,
                normalized_text = excluded.normalized_text,
                confidence_score = excluded.confidence_score,
                rank_reason = excluded.rank_reason,
                artwork_url = excluded.artwork_url,
                source_kind = excluded.source_kind,
                raw_title = excluded.raw_title,
                canonical_title = excluded.canonical_title,
                canonical_artist = excluded.canonical_artist,
                parse_source = excluded.parse_source,
                last_matched_at = excluded.last_matched_at",
            params![
                entry.source_provider,
                entry.source_id,
                entry.source_url,
                entry.title,
                entry.artist,
                entry.album,
                entry.duration_seconds,
                normalized_text,
                entry.confidence_score,
                entry.rank_reason,
                entry.artwork_url,
                entry.source_kind,
                entry.raw_title,
                entry.canonical_title,
                entry.canonical_artist,
                entry.parse_source,
                now,
            ],
        )
        .map_err(sql_error)?;
        tx.execute(
            "DELETE FROM source_index_fts WHERE source_provider = ? AND source_id = ?",
            params![entry.source_provider, entry.source_id],
        )
        .map_err(sql_error)?;
        tx.execute(
            "INSERT INTO source_index_fts(source_provider, source_id, normalized_text) VALUES (?, ?, ?)",
            params![entry.source_provider, entry.source_id, normalize_text(&format!("{} {} {}", entry.artist, entry.title, entry.album))],
        )
        .map_err(sql_error)?;
    }
    tx.commit().map_err(sql_error)?;
    Ok(entries.len())
}

pub fn search_source_index_entries(
    path: impl AsRef<Path>,
    query: &str,
    limit: usize,
    scope: Option<&str>,
) -> Result<Vec<SourceIndexEntry>, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    let clean_query = query.trim();
    if clean_query.is_empty() {
        return Ok(Vec::new());
    }
    let mut entries = fts_search_source_index(&connection, clean_query, limit.max(15) * 2)?;
    if entries.is_empty() {
        entries = fuzzy_scan_source_index(&connection, limit.max(20) * 6)?;
    }
    let filtered = entries
        .into_iter()
        .filter(|entry| matches_source_scope(entry, scope.unwrap_or("all")))
        .collect::<Vec<_>>();
    Ok(rank_source_entries(clean_query, filtered)
        .into_iter()
        .filter(|entry| entry.confidence_score >= 72.0)
        .take(limit)
        .collect())
}

pub fn clear_source_index(path: impl AsRef<Path>) -> Result<(), CoreError> {
    let connection = open_initialized(path.as_ref())?;
    connection
        .execute("DELETE FROM source_index", [])
        .map_err(sql_error)?;
    connection
        .execute("DELETE FROM source_index_fts", [])
        .map_err(sql_error)?;
    sync_source_index_version_runtime(&connection, false).map(|_| ())
}

pub fn rebuild_source_index(path: impl AsRef<Path>) -> Result<SourceIndexSchemaStatus, CoreError> {
    let connection = connect(path.as_ref())?;
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS metadata_cache (
            cache_key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );",
        )
        .map_err(sql_error)?;
    ensure_metadata_cache_schema_runtime(&connection)?;
    ensure_source_index_schema_runtime(&connection)
}

fn ensure_metadata_cache_schema_runtime(connection: &Connection) -> Result<(), CoreError> {
    let columns = table_columns(connection, "metadata_cache")?;
    if !columns.contains(&"created_at".to_string()) {
        connection
            .execute(
                "ALTER TABLE metadata_cache ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0",
                [],
            )
            .map_err(sql_error)?;
    }
    Ok(())
}

fn ensure_source_index_schema_runtime(
    connection: &Connection,
) -> Result<SourceIndexSchemaStatus, CoreError> {
    let columns = table_columns(connection, "source_index")?;
    let compatible = columns.is_empty()
        || (columns.contains(&"source_provider".to_string())
            && columns.contains(&"source_id".to_string())
            && columns.contains(&"source_url".to_string())
            && columns.contains(&"normalized_text".to_string()));
    let mut rebuilt = false;
    if !compatible {
        connection
            .execute_batch(
                "DROP TABLE IF EXISTS source_index_fts; DROP TABLE IF EXISTS source_index;",
            )
            .map_err(sql_error)?;
        rebuilt = true;
    }
    connection.execute_batch(
        "CREATE TABLE IF NOT EXISTS source_index (
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
        CREATE INDEX IF NOT EXISTS idx_source_index_last_matched_at ON source_index(last_matched_at DESC);
        CREATE INDEX IF NOT EXISTS idx_source_index_source_kind ON source_index(source_kind);",
    ).map_err(sql_error)?;
    for (name, definition) in [
        ("artwork_url", "artwork_url TEXT NOT NULL DEFAULT ''"),
        ("source_kind", "source_kind TEXT NOT NULL DEFAULT ''"),
        ("raw_title", "raw_title TEXT NOT NULL DEFAULT ''"),
        (
            "canonical_title",
            "canonical_title TEXT NOT NULL DEFAULT ''",
        ),
        (
            "canonical_artist",
            "canonical_artist TEXT NOT NULL DEFAULT ''",
        ),
        ("parse_source", "parse_source TEXT NOT NULL DEFAULT ''"),
    ] {
        let columns = table_columns(connection, "source_index")?;
        if !columns.contains(&name.to_string()) {
            connection
                .execute(
                    &format!("ALTER TABLE source_index ADD COLUMN {definition}"),
                    [],
                )
                .map_err(sql_error)?;
        }
    }
    connection.execute_batch(
        "DROP TABLE IF EXISTS source_index_fts;
         CREATE VIRTUAL TABLE source_index_fts USING fts5(source_provider UNINDEXED, source_id UNINDEXED, normalized_text);
         INSERT INTO source_index_fts(source_provider, source_id, normalized_text)
         SELECT source_provider, source_id, normalized_text FROM source_index;",
    ).map_err(sql_error)?;
    let status = sync_source_index_version_runtime(connection, rebuilt)?;
    if status.rebuilt {
        connection
            .execute("DELETE FROM source_index", [])
            .map_err(sql_error)?;
        connection
            .execute("DELETE FROM source_index_fts", [])
            .map_err(sql_error)?;
    }
    Ok(status)
}

fn sync_source_index_version_runtime(
    connection: &Connection,
    already_rebuilt: bool,
) -> Result<SourceIndexSchemaStatus, CoreError> {
    let payload: Option<String> = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = ?",
            params![SOURCE_INDEX_SCHEMA_KEY],
            |row| row.get(0),
        )
        .optional()
        .map_err(sql_error)?;
    let rebuilt = already_rebuilt || payload.as_deref() != Some("\"4\"");
    let columns = table_columns(connection, "metadata_cache")?;
    let now = unix_seconds()?;
    if columns.contains(&"updated_at".to_string()) {
        connection
            .execute(
                "INSERT INTO metadata_cache(cache_key, payload, created_at, updated_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(cache_key) DO UPDATE SET
            payload = excluded.payload,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at",
                params![
                    SOURCE_INDEX_SCHEMA_KEY,
                    format!("\"{}\"", SOURCE_INDEX_SCHEMA_VERSION),
                    now,
                    now
                ],
            )
            .map_err(sql_error)?;
    } else {
        connection
            .execute(
                "INSERT INTO metadata_cache(cache_key, payload, created_at) VALUES (?, ?, ?)
         ON CONFLICT(cache_key) DO UPDATE SET payload = excluded.payload, created_at = excluded.created_at",
                params![
                    SOURCE_INDEX_SCHEMA_KEY,
                    format!("\"{}\"", SOURCE_INDEX_SCHEMA_VERSION),
                    now
                ],
            )
            .map_err(sql_error)?;
    }
    Ok(SourceIndexSchemaStatus {
        schema_key: SOURCE_INDEX_SCHEMA_KEY.to_string(),
        schema_version: SOURCE_INDEX_SCHEMA_VERSION.to_string(),
        rebuilt,
    })
}

fn fts_search_source_index(
    connection: &Connection,
    query: &str,
    limit: usize,
) -> Result<Vec<SourceIndexEntry>, CoreError> {
    let mut terms = tokens(query)
        .into_iter()
        .filter(|token| !SOFT_WORDS.contains(&token.as_str()))
        .collect::<Vec<_>>();
    if terms.is_empty() {
        return Ok(Vec::new());
    }
    terms.sort();
    let fts_query = terms
        .iter()
        .map(|token| format!("{token}*"))
        .collect::<Vec<_>>()
        .join(" OR ");
    let mut statement = connection.prepare(
        "SELECT si.source_provider, si.source_id, si.source_url, si.title, si.artist, si.album,
                si.duration_seconds, si.confidence_score, si.rank_reason, si.artwork_url,
                si.source_kind, si.raw_title, si.canonical_title, si.canonical_artist, si.parse_source
         FROM source_index_fts fts
         JOIN source_index si ON si.source_provider = fts.source_provider AND si.source_id = fts.source_id
         WHERE source_index_fts MATCH ?
         ORDER BY si.confidence_score DESC, si.last_matched_at DESC
         LIMIT ?",
    ).map_err(sql_error)?;
    let entries = statement
        .query_map(params![fts_query, limit as i64], source_row)
        .map_err(sql_error)?
        .map(|row| row.map_err(sql_error))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

fn fuzzy_scan_source_index(
    connection: &Connection,
    limit: usize,
) -> Result<Vec<SourceIndexEntry>, CoreError> {
    let mut statement = connection
        .prepare(
            "SELECT source_provider, source_id, source_url, title, artist, album, duration_seconds,
                confidence_score, rank_reason, artwork_url, source_kind, raw_title, canonical_title,
                canonical_artist, parse_source
         FROM source_index ORDER BY last_matched_at DESC LIMIT ?",
        )
        .map_err(sql_error)?;
    let entries = statement
        .query_map(params![limit as i64], source_row)
        .map_err(sql_error)?
        .map(|row| row.map_err(sql_error))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

fn source_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SourceIndexEntry> {
    Ok(SourceIndexEntry {
        source_provider: row.get(0)?,
        source_id: row.get(1)?,
        source_url: row.get(2)?,
        title: row.get(3)?,
        artist: row.get(4)?,
        album: row.get(5)?,
        duration_seconds: row.get(6)?,
        confidence_score: row.get(7)?,
        rank_reason: row.get(8)?,
        artwork_url: row.get(9)?,
        source_kind: row.get(10)?,
        raw_title: row.get(11)?,
        canonical_title: row.get(12)?,
        canonical_artist: row.get(13)?,
        parse_source: row.get(14)?,
    })
}

const CUE_WORDS: &[&str] = &[
    "acoustic",
    "cover",
    "covers",
    "instrumental",
    "karaoke",
    "live",
    "orchestra",
    "piano",
    "remix",
    "symphony",
    "tribute",
];
const OFFICIAL_WORDS: &[&str] = &["official", "audio", "video", "lyrics", "topic"];
const SOFT_WORDS: &[&str] = &[
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

fn rank_source_entries(query: &str, entries: Vec<SourceIndexEntry>) -> Vec<SourceIndexEntry> {
    let query_tokens = tokens(query);
    let query_core = without_words(&query_tokens, SOFT_WORDS);
    let query_cues = only_words(&query_tokens, CUE_WORDS);
    let mut ranked = Vec::new();
    for mut entry in entries {
        let title_tokens = tokens(&entry.title);
        let artist_tokens = tokens(&entry.artist);
        let album_tokens = tokens(&entry.album);
        let combined = union(&union(&title_tokens, &artist_tokens), &album_tokens);
        let cue_overlap = only_words(&combined, CUE_WORDS);
        let title_similarity =
            token_similarity(&query_core, &without_words(&title_tokens, SOFT_WORDS));
        let combined_similarity =
            token_similarity(&query_tokens, &union(&artist_tokens, &title_tokens));
        let best_similarity = title_similarity.max(combined_similarity);
        if best_similarity < 50.0 {
            continue;
        }
        let mut reasons: Vec<&str> = Vec::new();
        let mut score = 30.0 + best_similarity * 0.55;
        if entry.parse_source == "structured" {
            score += 40.0;
            reasons.push("structured");
        } else if entry.parse_source == "parsed_title" {
            score -= 20.0;
        }
        if entry.source_kind == "song" {
            score += 25.0;
            reasons.push("song");
        } else if entry.source_kind == "video" {
            score -= 4.0;
        }
        if !query_core.is_empty() && query_core.iter().all(|t| title_tokens.contains(t)) {
            score += 35.0;
            reasons.push("exact-title");
        }
        if !artist_tokens.is_empty() && query_tokens.iter().any(|t| artist_tokens.contains(t)) {
            score += 70.0;
            reasons.push("artist");
        }
        if !query_core.is_empty()
            && query_core
                .iter()
                .filter(|t| title_tokens.contains(*t))
                .count() as f64
                / query_core.len() as f64
                >= 0.7
        {
            score += 20.0;
            reasons.push("fuzzy");
        }
        if let Some(duration) = entry.duration_seconds {
            if (120.0..=420.0).contains(&duration) {
                score += 12.0;
            } else if !(45.0..=900.0).contains(&duration) {
                score -= 35.0;
            }
        }
        if title_tokens
            .iter()
            .any(|t| OFFICIAL_WORDS.contains(&t.as_str()))
        {
            score += 10.0;
            reasons.push("official");
        }
        let unexpected_cues: Vec<_> = cue_overlap
            .iter()
            .filter(|cue| !query_cues.contains(*cue))
            .collect();
        if !unexpected_cues.is_empty() {
            score -= 55.0 + unexpected_cues.len() as f64 * 12.0;
            reasons.push("filtered-version");
        }
        if !query_cues.is_empty() && !cue_overlap.is_empty() {
            score += 45.0;
            reasons.push("requested-version");
        }
        if reasons.is_empty() && combined_similarity >= 70.0 {
            reasons.push("source-match");
        }
        if reasons.is_empty() {
            continue;
        }
        entry.confidence_score = (score.max(0.0) * 100.0).round() / 100.0;
        entry.rank_reason = dedupe_reasons(&reasons).join(" ");
        ranked.push(entry);
    }
    ranked.sort_by(|a, b| {
        b.confidence_score
            .partial_cmp(&a.confidence_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.title.to_lowercase().cmp(&b.title.to_lowercase()))
    });
    ranked
}

fn matches_source_scope(entry: &SourceIndexEntry, scope: &str) -> bool {
    match scope {
        "songs" => entry.source_kind.is_empty() || entry.source_kind == "song",
        "videos" => entry.source_kind == "video",
        "all" | "" => true,
        _ => false,
    }
}

fn normalize_text(value: &str) -> String {
    let mut values = tokens(value);
    values.sort();
    values.join(" ")
}

fn tokens(value: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() {
            current.push(ch.to_ascii_lowercase());
        } else if current.len() > 1 {
            out.push(std::mem::take(&mut current));
        } else {
            current.clear();
        }
    }
    if current.len() > 1 {
        out.push(current);
    }
    out.sort();
    out.dedup();
    out
}

fn token_similarity(left: &[String], right: &[String]) -> f64 {
    if left.is_empty() || right.is_empty() {
        return 0.0;
    }
    let overlap = left.iter().filter(|token| right.contains(*token)).count() as f64;
    if overlap == 0.0 {
        return 0.0;
    }
    let precision = overlap / right.len() as f64;
    let recall = overlap / left.len() as f64;
    200.0 * precision * recall / (precision + recall)
}

fn without_words(tokens: &[String], words: &[&str]) -> Vec<String> {
    tokens
        .iter()
        .filter(|token| !words.contains(&token.as_str()))
        .cloned()
        .collect()
}

fn only_words(tokens: &[String], words: &[&str]) -> Vec<String> {
    tokens
        .iter()
        .filter(|token| words.contains(&token.as_str()))
        .cloned()
        .collect()
}

fn union(left: &[String], right: &[String]) -> Vec<String> {
    let mut result = left.to_vec();
    result.extend(right.iter().cloned());
    result.sort();
    result.dedup();
    result
}

fn dedupe_reasons(reasons: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    for reason in reasons {
        if !out.iter().any(|value: &String| value == reason) {
            out.push((*reason).to_string());
        }
    }
    out
}

fn resolve_db_path(path: Option<&str>) -> Result<PathBuf, CoreError> {
    if let Some(path) = path.filter(|value| !value.trim().is_empty()) {
        return Ok(PathBuf::from(path));
    }
    Ok(default_database_path())
}

fn unix_seconds() -> Result<i64, CoreError> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::new("clock_error", error.to_string()))?
        .as_secs() as i64)
}

fn new_id(prefix: &str) -> Result<String, CoreError> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::new("clock_error", error.to_string()))?
        .as_nanos();
    let counter = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    Ok(format!("{prefix}-{nanos}-{counter}"))
}

fn now_iso8601() -> Result<String, CoreError> {
    Ok(timestamp_to_iso8601(unix_seconds()?))
}

fn timestamp_to_iso8601(timestamp: i64) -> String {
    format!("{timestamp}")
}

fn iso8601_to_timestamp(value: &str) -> Result<i64, CoreError> {
    value
        .parse::<i64>()
        .map_err(|error| CoreError::new("invalid_timestamp", error.to_string()))
}

fn sql_error(error: rusqlite::Error) -> CoreError {
    CoreError::new("database_error", error.to_string())
}
