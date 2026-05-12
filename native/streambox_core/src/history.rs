//! History storage behavior shared by the Rust core and FFI boundary.
//!
//! Current FastAPI-compatible behavior:
//! - Entries are append-only; adding the same playback item multiple times creates multiple rows.
//! - Listing orders entries by `played_at` descending, so the most recently played row is first.
//! - Listing returns at most 100 rows unless a smaller limit is supplied by the caller.
//! - Retention is read-side by default: old rows may remain in SQLite until explicit pruning is run.
//! - Stored playback items preserve the existing JSON timestamp format exactly by writing the
//!   caller-provided `item` JSON verbatim, including its `added_at` field.
//!
//! The database `played_at` column stores Unix seconds to match the Python backend schema.

use serde_json::Value;

use crate::db::CoreDb;
use crate::error::CoreError;

pub const DEFAULT_HISTORY_LIMIT: usize = 100;

pub fn list_history(db_path: Option<&str>, limit: Option<usize>) -> Result<Vec<Value>, CoreError> {
    CoreDb::open(db_path)?.list_history(limit.unwrap_or(DEFAULT_HISTORY_LIMIT))
}

pub fn add_history(db_path: Option<&str>, item: Value) -> Result<Value, CoreError> {
    CoreDb::open(db_path)?.add_history(item)
}

pub fn clear_history(db_path: Option<&str>) -> Result<(), CoreError> {
    CoreDb::open(db_path)?.clear_history()
}

pub fn prune_history(db_path: Option<&str>, keep: usize) -> Result<usize, CoreError> {
    CoreDb::open(db_path)?.prune_history(keep)
}
