use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use serde_json::Value;
use uuid::Uuid;

use crate::error::CoreError;
use crate::models::Favorite;

const DEFAULT_DATABASE_PATH: &str = "data/streambox.sqlite3";

pub struct StreamboxDb {
    path: PathBuf,
}

impl StreamboxDb {
    pub fn new(path: Option<impl Into<PathBuf>>) -> Self {
        Self {
            path: path.map(Into::into).unwrap_or_else(default_database_path),
        }
    }

    pub fn init(&self) -> Result<(), CoreError> {
        let connection = self.connect()?;
        connection
            .execute_batch(
                r#"
                CREATE TABLE IF NOT EXISTS favorites (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                "#,
            )
            .map_err(to_db_error)?;
        Ok(())
    }

    pub fn list_favorites(&self) -> Result<Vec<Favorite>, CoreError> {
        self.init()?;
        let connection = self.connect()?;
        let mut statement = connection
            .prepare("SELECT id, item_json, created_at FROM favorites ORDER BY created_at DESC")
            .map_err(to_db_error)?;
        let rows = statement
            .query_map([], |row| {
                let item_json: String = row.get("item_json")?;
                let created_at: i64 = row.get("created_at")?;
                Ok((row.get::<_, String>("id")?, item_json, created_at))
            })
            .map_err(to_db_error)?;

        let mut favorites = Vec::new();
        for row in rows {
            let (id, item_json, created_at) = row.map_err(to_db_error)?;
            let item = serde_json::from_str(&item_json)
                .map_err(|error| CoreError::new("invalid_favorite_json", error.to_string()))?;
            favorites.push(Favorite {
                id,
                item,
                created_at: unix_seconds_to_utc_string(created_at),
            });
        }
        Ok(favorites)
    }

    pub fn add_favorite(&self, item: Value) -> Result<Favorite, CoreError> {
        self.init()?;
        let favorite = Favorite {
            id: Uuid::new_v4().to_string(),
            item,
            created_at: unix_seconds_to_utc_string(now_unix_seconds()),
        };
        let item_json = serde_json::to_string(&favorite.item)
            .map_err(|error| CoreError::new("serialization_failed", error.to_string()))?;
        let created_at = utc_string_to_unix_seconds(&favorite.created_at)?;
        let connection = self.connect()?;
        connection
            .execute(
                "INSERT INTO favorites(id, item_json, created_at) VALUES (?, ?, ?)",
                params![&favorite.id, &item_json, created_at],
            )
            .map_err(to_db_error)?;
        Ok(favorite)
    }

    pub fn remove_favorite(&self, id: &str) -> Result<(), CoreError> {
        self.init()?;
        let connection = self.connect()?;
        connection
            .execute("DELETE FROM favorites WHERE id = ?", params![id])
            .map_err(to_db_error)?;
        Ok(())
    }

    fn connect(&self) -> Result<Connection, CoreError> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|error| CoreError::new("database_open_failed", error.to_string()))?;
        }
        let connection = Connection::open(&self.path).map_err(to_db_error)?;
        connection
            .execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(to_db_error)?;
        Ok(connection)
    }
}

fn default_database_path() -> PathBuf {
    Path::new(DEFAULT_DATABASE_PATH).to_path_buf()
}

fn now_unix_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

fn unix_seconds_to_utc_string(seconds: i64) -> String {
    // Match FastAPI/Pydantic's JSON shape closely enough for Dart consumers while
    // preserving SQLite's integer timestamp storage.
    format!("{}Z", chrono_like_utc(seconds))
}

fn chrono_like_utc(seconds: i64) -> String {
    // Use SQLite itself for UTC timestamp formatting to avoid pulling in a full
    // time dependency solely for JSON compatibility.
    let connection = Connection::open_in_memory().expect("in-memory sqlite opens");
    connection
        .query_row(
            "SELECT strftime('%Y-%m-%dT%H:%M:%S', ?, 'unixepoch')",
            params![seconds],
            |row| row.get::<_, String>(0),
        )
        .unwrap_or_else(|_| "1970-01-01T00:00:00".to_string())
}

fn utc_string_to_unix_seconds(value: &str) -> Result<i64, CoreError> {
    let connection = Connection::open_in_memory().map_err(to_db_error)?;
    connection
        .query_row(
            "SELECT unixepoch(?)",
            params![value.trim_end_matches('Z')],
            |row| row.get::<_, i64>(0),
        )
        .map_err(to_db_error)
}

fn to_db_error(error: rusqlite::Error) -> CoreError {
    CoreError::new("database_error", error.to_string())
}
