use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection};
use serde_json::Value;

use crate::error::CoreError;

static HISTORY_ID_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct CoreDb {
    connection: Connection,
}

impl CoreDb {
    pub fn open(path: Option<&str>) -> Result<Self, CoreError> {
        let path = resolve_db_path(path)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|error| CoreError::new("db_open_failed", error.to_string()))?;
        }
        let connection = Connection::open(path)
            .map_err(|error| CoreError::new("db_open_failed", error.to_string()))?;
        connection
            .execute_batch(
                "PRAGMA foreign_keys = ON;
                 CREATE TABLE IF NOT EXISTS history (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    played_at INTEGER NOT NULL
                 );",
            )
            .map_err(|error| CoreError::new("db_init_failed", error.to_string()))?;
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
                params![new_history_id()?, item_json, unix_seconds()?],
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

fn resolve_db_path(path: Option<&str>) -> Result<PathBuf, CoreError> {
    if let Some(path) = path.filter(|value| !value.trim().is_empty()) {
        return Ok(PathBuf::from(path));
    }
    if let Ok(path) = std::env::var("STREAMBOX_DB_PATH") {
        if !path.trim().is_empty() {
            return Ok(PathBuf::from(path));
        }
    }
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map_err(|_| {
            CoreError::new(
                "db_path_missing",
                "db_path was not provided and no home directory was found",
            )
        })?;
    Ok(PathBuf::from(home).join(".streambox").join("streambox.db"))
}

fn unix_seconds() -> Result<i64, CoreError> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::new("clock_error", error.to_string()))?
        .as_secs() as i64)
}

fn new_history_id() -> Result<String, CoreError> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| CoreError::new("clock_error", error.to_string()))?
        .as_nanos();
    let counter = HISTORY_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    Ok(format!("history-{nanos}-{counter}"))
}
