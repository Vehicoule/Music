use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

use crate::error::CoreError;
use crate::models::{PlaybackItem, Playlist, PlaylistCreate, PlaylistUpdate};

pub fn default_database_path() -> PathBuf {
    std::env::var_os("DATABASE_PATH")
        .or_else(|| std::env::var_os("STREAMBOX_DATABASE_PATH"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("./data/streambox.sqlite3"))
}

pub fn init_database(path: impl AsRef<Path>) -> Result<(), CoreError> {
    let connection = connect(path.as_ref())?;
    init_schema(&connection)
}

pub fn list_playlists(path: impl AsRef<Path>) -> Result<Vec<Playlist>, CoreError> {
    let connection = connect(path.as_ref())?;
    init_schema(&connection)?;
    let mut statement = connection
        .prepare("SELECT id FROM playlists ORDER BY updated_at DESC")
        .map_err(sql_error)?;
    let ids = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)?;
    ids.into_iter()
        .map(|id| load_playlist(&connection, &id))
        .collect()
}

pub fn create_playlist(
    path: impl AsRef<Path>,
    payload: PlaylistCreate,
) -> Result<Playlist, CoreError> {
    let connection = connect(path.as_ref())?;
    init_schema(&connection)?;
    let now = now_timestamp();
    let playlist = Playlist {
        id: Uuid::new_v4().to_string(),
        name: payload.name,
        description: payload.description,
        tracks: payload.tracks,
        created_at: timestamp_to_iso8601(now),
        updated_at: timestamp_to_iso8601(now),
    };
    save_playlist(&connection, &playlist)?;
    Ok(playlist)
}

pub fn update_playlist(
    path: impl AsRef<Path>,
    payload: PlaylistUpdate,
) -> Result<Playlist, CoreError> {
    let connection = connect(path.as_ref())?;
    init_schema(&connection)?;
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
    playlist.updated_at = timestamp_to_iso8601(now_timestamp());
    save_playlist(&connection, &playlist)?;
    Ok(playlist)
}

pub fn delete_playlist(path: impl AsRef<Path>, playlist_id: &str) -> Result<(), CoreError> {
    let connection = connect(path.as_ref())?;
    init_schema(&connection)?;
    let changed = connection
        .execute("DELETE FROM playlists WHERE id = ?", params![playlist_id])
        .map_err(sql_error)?;
    if changed == 0 {
        Err(CoreError::new("not_found", "Playlist not found"))
    } else {
        Ok(())
    }
}

fn connect(path: &Path) -> Result<Connection, CoreError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| CoreError::new("database_open_failed", error.to_string()))?;
    }
    let connection = Connection::open(path).map_err(sql_error)?;
    connection
        .execute_batch("PRAGMA foreign_keys = ON;")
        .map_err(sql_error)?;
    Ok(connection)
}

fn init_schema(connection: &Connection) -> Result<(), CoreError> {
    connection
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
            r#"
            INSERT INTO playlists(id, name, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                updated_at = excluded.updated_at
            "#,
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
            .map_err(|error| CoreError::new("serialization_failed", error.to_string()))?;
        connection
            .execute(
                "INSERT INTO playlist_tracks(playlist_id, position, item_json) VALUES (?, ?, ?)",
                params![playlist.id, position as i64, item_json],
            )
            .map_err(sql_error)?;
    }
    Ok(())
}

fn now_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn timestamp_to_iso8601(timestamp: i64) -> String {
    let datetime = chrono::DateTime::from_timestamp(timestamp, 0)
        .unwrap_or(chrono::DateTime::<chrono::Utc>::UNIX_EPOCH);
    datetime.to_rfc3339()
}

fn iso8601_to_timestamp(value: &str) -> Result<i64, CoreError> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|datetime| datetime.timestamp())
        .map_err(|error| CoreError::new("invalid_timestamp", error.to_string()))
}

fn sql_error(error: rusqlite::Error) -> CoreError {
    CoreError::new("database_error", error.to_string())
}
