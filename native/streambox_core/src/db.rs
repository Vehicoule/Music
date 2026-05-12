use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{Connection, OptionalExtension};
use serde::Serialize;

use crate::error::CoreError;

pub const SCHEMA_VERSION: i64 = 1;
const SOURCE_INDEX_SCHEMA_CACHE_KEY: &str = "source-index:schema-version:v4";
const SOURCE_INDEX_SCHEMA_CACHE_PAYLOAD: &str = "\"4\"";

#[derive(Debug)]
pub struct Db {
    path: PathBuf,
    connection: Connection,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DbHealth {
    pub path: String,
    pub schema_version: i64,
    pub user_version: i64,
    pub foreign_keys_enabled: bool,
}

impl Db {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, CoreError> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                CoreError::new(
                    "db_open_failed",
                    format!("failed to create database directory: {error}"),
                )
            })?;
        }

        let connection = Connection::open(&path).map_err(db_error("db_open_failed"))?;
        connection
            .pragma_update(None, "foreign_keys", "ON")
            .map_err(db_error("db_pragma_failed"))?;

        let db = Self { path, connection };
        db.init_schema()?;
        Ok(db)
    }

    pub fn health(&self) -> Result<DbHealth, CoreError> {
        let user_version = self.user_version()?;
        let foreign_keys_enabled = self
            .connection
            .pragma_query_value(None, "foreign_keys", |row| row.get::<_, i64>(0))
            .map(|value| value == 1)
            .map_err(db_error("db_pragma_failed"))?;

        Ok(DbHealth {
            path: self.path.to_string_lossy().into_owned(),
            schema_version: SCHEMA_VERSION,
            user_version,
            foreign_keys_enabled,
        })
    }

    fn init_schema(&self) -> Result<(), CoreError> {
        let current_version = self.user_version()?;
        if current_version > SCHEMA_VERSION {
            return Err(CoreError::new(
                "unsupported_schema_version",
                format!(
                    "database user_version {current_version} is newer than supported version {SCHEMA_VERSION}"
                ),
            ));
        }

        self.connection
            .execute_batch(
                "
                CREATE TABLE IF NOT EXISTS metadata_cache (
                    cache_key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );

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

                CREATE TABLE IF NOT EXISTS favorites (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS history (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    played_at INTEGER NOT NULL
                );

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
                ",
            )
            .map_err(db_error("db_schema_failed"))?;

        self.ensure_source_index_columns()?;
        self.sync_source_index_version()?;
        self.rebuild_source_index_fts()?;
        self.set_user_version(SCHEMA_VERSION)?;
        Ok(())
    }

    fn user_version(&self) -> Result<i64, CoreError> {
        self.connection
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(db_error("db_pragma_failed"))
    }

    fn set_user_version(&self, version: i64) -> Result<(), CoreError> {
        self.connection
            .pragma_update(None, "user_version", version)
            .map_err(db_error("db_pragma_failed"))
    }

    fn ensure_source_index_columns(&self) -> Result<(), CoreError> {
        let mut statement = self
            .connection
            .prepare("PRAGMA table_info(source_index)")
            .map_err(db_error("db_schema_failed"))?;
        let columns = statement
            .query_map([], |row| row.get::<_, String>(1))
            .map_err(db_error("db_schema_failed"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error("db_schema_failed"))?;

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
            if !columns.iter().any(|column| column == name) {
                self.connection
                    .execute(
                        &format!("ALTER TABLE source_index ADD COLUMN {definition}"),
                        [],
                    )
                    .map_err(db_error("db_schema_failed"))?;
            }
        }
        Ok(())
    }

    fn sync_source_index_version(&self) -> Result<(), CoreError> {
        let payload = self
            .connection
            .query_row(
                "SELECT payload FROM metadata_cache WHERE cache_key = ?1",
                [SOURCE_INDEX_SCHEMA_CACHE_KEY],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(db_error("db_schema_failed"))?;

        if payload.as_deref() != Some(SOURCE_INDEX_SCHEMA_CACHE_PAYLOAD) {
            self.connection
                .execute("DELETE FROM source_index", [])
                .map_err(db_error("db_schema_failed"))?;
        }

        self.connection
            .execute(
                "
                INSERT INTO metadata_cache(cache_key, payload, created_at)
                VALUES (?1, ?2, strftime('%s', 'now'))
                ON CONFLICT(cache_key) DO UPDATE SET
                    payload = excluded.payload,
                    created_at = excluded.created_at
                ",
                [
                    SOURCE_INDEX_SCHEMA_CACHE_KEY,
                    SOURCE_INDEX_SCHEMA_CACHE_PAYLOAD,
                ],
            )
            .map_err(db_error("db_schema_failed"))?;
        Ok(())
    }

    fn rebuild_source_index_fts(&self) -> Result<(), CoreError> {
        self.connection
            .execute_batch(
                "
                DROP TABLE IF EXISTS source_index_fts;

                CREATE VIRTUAL TABLE IF NOT EXISTS source_index_fts
                USING fts5(source_provider UNINDEXED, source_id UNINDEXED, normalized_text);

                INSERT INTO source_index_fts(source_provider, source_id, normalized_text)
                SELECT source_provider, source_id, normalized_text FROM source_index;
                ",
            )
            .map_err(db_error("db_schema_failed"))?;
        Ok(())
    }
}

pub fn db_health(path: impl AsRef<Path>) -> Result<DbHealth, CoreError> {
    Db::open(path)?.health()
}

fn db_error(code: &'static str) -> impl FnOnce(rusqlite::Error) -> CoreError {
    move |error| CoreError::new(code, error.to_string())
}
