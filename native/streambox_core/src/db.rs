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

pub fn upsert_source_index_entries(
    path: impl AsRef<Path>,
    entries: &[SourceIndexEntry],
) -> Result<usize, CoreError> {
    let mut connection = open_initialized(path.as_ref())?;
    ensure_source_index_schema(&connection)?;
    let transaction = connection.transaction().map_err(sql_error)?;
    for entry in entries {
        let id = source_index_id(entry);
        let payload = serde_json::to_string(entry)
            .map_err(|error| CoreError::new("source_index_encode_failed", error.to_string()))?;
        transaction
            .execute(
                "INSERT OR REPLACE INTO source_index(
                    id, source_provider, source_id, source_url, source_kind, title, artist, album,
                    duration_seconds, confidence_score, rank_reason, artwork_url, raw_title,
                    canonical_title, canonical_artist, parse_source, payload
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params![
                    id,
                    entry.source_provider,
                    entry.source_id,
                    entry.source_url,
                    entry.source_kind,
                    entry.title,
                    entry.artist,
                    entry.album,
                    entry.duration_seconds,
                    entry.confidence_score,
                    entry.rank_reason,
                    entry.artwork_url,
                    entry.raw_title,
                    entry.canonical_title,
                    entry.canonical_artist,
                    entry.parse_source,
                    payload,
                ],
            )
            .map_err(sql_error)?;
        transaction
            .execute("DELETE FROM source_index_fts WHERE id = ?", params![id])
            .map_err(sql_error)?;
        transaction
            .execute(
                "INSERT INTO source_index_fts(
                    id, title, artist, album, raw_title, canonical_title, canonical_artist
                 ) VALUES (?, ?, ?, ?, ?, ?, ?)",
                params![
                    id,
                    entry.title,
                    entry.artist,
                    entry.album,
                    entry.raw_title,
                    entry.canonical_title,
                    entry.canonical_artist,
                ],
            )
            .map_err(sql_error)?;
    }
    transaction.commit().map_err(sql_error)?;
    Ok(entries.len())
}

pub fn search_source_index_entries(
    path: impl AsRef<Path>,
    query: &str,
    limit: usize,
    scope: Option<&str>,
) -> Result<Vec<SourceIndexEntry>, CoreError> {
    let connection = open_initialized(path.as_ref())?;
    ensure_source_index_schema(&connection)?;
    let mut statement = connection
        .prepare("SELECT payload FROM source_index")
        .map_err(sql_error)?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(sql_error)?;
    let mut scored = Vec::new();
    for row in rows {
        let payload = row.map_err(sql_error)?;
        let mut entry: SourceIndexEntry = serde_json::from_str(&payload)
            .map_err(|error| CoreError::new("source_index_decode_failed", error.to_string()))?;
        if !scope_matches(scope, &entry.source_kind) {
            continue;
        }
        let (score, reason) = rank_source_index_entry(query, &entry);
        if score <= 0.0 {
            continue;
        }
        entry.confidence_score = score;
        entry.rank_reason = reason;
        scored.push(entry);
    }
    scored.sort_by(|left, right| {
        right
            .confidence_score
            .partial_cmp(&left.confidence_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.title.cmp(&right.title))
    });
    scored.truncate(limit);
    Ok(scored)
}

pub fn clear_source_index(path: impl AsRef<Path>) -> Result<(), CoreError> {
    let connection = open_initialized(path.as_ref())?;
    ensure_source_index_schema(&connection)?;
    connection
        .execute("DELETE FROM source_index", [])
        .map_err(sql_error)?;
    connection
        .execute("DELETE FROM source_index_fts", [])
        .map_err(sql_error)?;
    Ok(())
}

pub fn rebuild_source_index(path: impl AsRef<Path>) -> Result<SourceIndexSchemaStatus, CoreError> {
    let connection = connect(path.as_ref())?;
    let rebuilt = source_index_needs_rebuild(&connection)?;
    if rebuilt {
        connection
            .execute_batch(
                "DROP TABLE IF EXISTS source_index_fts;
                 DROP TABLE IF EXISTS source_index;",
            )
            .map_err(sql_error)?;
    }
    ensure_metadata_cache_schema(&connection)?;
    ensure_source_index_schema(&connection)?;
    write_source_index_schema_version(&connection)?;
    Ok(SourceIndexSchemaStatus {
        schema_key: SOURCE_INDEX_SCHEMA_KEY.to_string(),
        schema_version: SOURCE_INDEX_SCHEMA_VERSION.to_string(),
        rebuilt,
    })
}

fn source_index_id(entry: &SourceIndexEntry) -> String {
    format!("{}:{}", entry.source_provider, entry.source_id)
}

fn scope_matches(scope: Option<&str>, source_kind: &str) -> bool {
    match scope {
        Some("songs") => source_kind == "song",
        Some("videos") => source_kind == "video",
        _ => true,
    }
}

fn rank_source_index_entry(query: &str, entry: &SourceIndexEntry) -> (f64, String) {
    let tokens = query_tokens(query);
    if tokens.is_empty() {
        return (0.0, "empty_query".to_string());
    }
    let title = normalize(&entry.title);
    let canonical_title = normalize(&entry.canonical_title);
    let raw_title = normalize(&entry.raw_title);
    let artist = normalize(&entry.artist);
    let canonical_artist = normalize(&entry.canonical_artist);
    let album = normalize(&entry.album);
    let haystack = [
        title.as_str(),
        canonical_title.as_str(),
        raw_title.as_str(),
        artist.as_str(),
        canonical_artist.as_str(),
        album.as_str(),
    ]
    .join(" ");
    let matched = tokens
        .iter()
        .filter(|token| haystack.contains(token.as_str()))
        .count();
    if matched == 0 {
        return (0.0, "no_match".to_string());
    }
    let mut score = (matched as f64 / tokens.len() as f64) * 70.0;
    let mut reasons = Vec::new();
    if !title.is_empty() && tokens.iter().any(|token| title.contains(token.as_str())) {
        score += 10.0;
        reasons.push("title");
    }
    if !canonical_title.is_empty()
        && tokens
            .iter()
            .any(|token| canonical_title.contains(token.as_str()))
    {
        score += 10.0;
        reasons.push("canonical_title");
    }
    if !artist.is_empty() && tokens.iter().any(|token| artist.contains(token.as_str())) {
        score += 20.0;
        reasons.push("artist");
    }
    if !canonical_artist.is_empty()
        && tokens
            .iter()
            .any(|token| canonical_artist.contains(token.as_str()))
    {
        score += 20.0;
        reasons.push("canonical_artist");
    }
    if entry.source_kind == "song" {
        score += 2.0;
    }
    (score.min(100.0), reasons.join(","))
}

fn query_tokens(query: &str) -> Vec<String> {
    normalize(query)
        .split_whitespace()
        .filter(|token| token.len() > 2 && *token != "the")
        .map(ToOwned::to_owned)
        .collect()
}

fn normalize(value: &str) -> String {
    value
        .to_ascii_lowercase()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character
            } else {
                ' '
            }
        })
        .collect::<String>()
}

fn ensure_source_index_schema(connection: &Connection) -> Result<(), CoreError> {
    if source_index_needs_rebuild(connection)? {
        connection
            .execute_batch(
                "DROP TABLE IF EXISTS source_index_fts;
                 DROP TABLE IF EXISTS source_index;",
            )
            .map_err(sql_error)?;
    }
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS source_index (
                id TEXT PRIMARY KEY,
                source_provider TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                source_kind TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                artist TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                duration_seconds REAL,
                confidence_score REAL NOT NULL DEFAULT 0,
                rank_reason TEXT NOT NULL DEFAULT '',
                artwork_url TEXT NOT NULL DEFAULT '',
                raw_title TEXT NOT NULL DEFAULT '',
                canonical_title TEXT NOT NULL DEFAULT '',
                canonical_artist TEXT NOT NULL DEFAULT '',
                parse_source TEXT NOT NULL DEFAULT '',
                payload TEXT NOT NULL
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS source_index_fts
            USING fts5(id UNINDEXED, title, artist, album, raw_title, canonical_title, canonical_artist);
            "#,
        )
        .map_err(sql_error)
}

fn source_index_needs_rebuild(connection: &Connection) -> Result<bool, CoreError> {
    let exists: Option<String> = connection
        .query_row(
            "SELECT name FROM sqlite_master WHERE name = 'source_index'",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(sql_error)?;
    if exists.is_none() {
        return Ok(false);
    }
    let has_source_provider = connection
        .prepare("PRAGMA table_info(source_index)")
        .map_err(sql_error)?
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)?
        .iter()
        .any(|column| column == "source_provider");
    Ok(!has_source_provider)
}

fn ensure_metadata_cache_schema(connection: &Connection) -> Result<(), CoreError> {
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS metadata_cache(
                cache_key TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0
            );",
        )
        .map_err(sql_error)
}

fn write_source_index_schema_version(connection: &Connection) -> Result<(), CoreError> {
    ensure_metadata_cache_schema(connection)?;
    connection
        .execute(
            "INSERT OR REPLACE INTO metadata_cache(cache_key, payload, updated_at)
             VALUES (?, ?, strftime('%s', 'now'))",
            params![
                SOURCE_INDEX_SCHEMA_KEY,
                format!("\"{SOURCE_INDEX_SCHEMA_VERSION}\"")
            ],
        )
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
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT 0
            );
            "#,
        )
        .map_err(sql_error)
}

fn migrate_to_v4(transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    transaction
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS source_index (
                id TEXT PRIMARY KEY,
                source_provider TEXT NOT NULL,
                source_id TEXT NOT NULL,
                source_url TEXT NOT NULL,
                source_kind TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                artist TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                duration_seconds REAL,
                confidence_score REAL NOT NULL DEFAULT 0,
                rank_reason TEXT NOT NULL DEFAULT '',
                artwork_url TEXT NOT NULL DEFAULT '',
                raw_title TEXT NOT NULL DEFAULT '',
                canonical_title TEXT NOT NULL DEFAULT '',
                canonical_artist TEXT NOT NULL DEFAULT '',
                parse_source TEXT NOT NULL DEFAULT '',
                payload TEXT NOT NULL
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS source_index_fts
            USING fts5(id UNINDEXED, title, artist, album, raw_title, canonical_title, canonical_artist);

            CREATE INDEX IF NOT EXISTS idx_history_played_at
            ON history(played_at DESC);

            INSERT OR REPLACE INTO metadata_cache(cache_key, payload, created_at, updated_at)
            VALUES ('source-index:schema-version:v4', '"4"', strftime('%s', 'now'), strftime('%s', 'now'));
            "#,
        )
        .map_err(sql_error)
}

fn migrate_to_v5(_transaction: &rusqlite::Transaction<'_>) -> Result<(), CoreError> {
    Ok(())
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
