use std::path::PathBuf;

use serde_json::Value;

use crate::db::StreamboxDb;
use crate::error::CoreError;
use crate::models::Favorite;

pub fn list_favorites(database_path: Option<String>) -> Result<Vec<Favorite>, CoreError> {
    db(database_path).list_favorites()
}

pub fn add_favorite(database_path: Option<String>, item: Value) -> Result<Favorite, CoreError> {
    db(database_path).add_favorite(item)
}

pub fn remove_favorite(database_path: Option<String>, id: &str) -> Result<(), CoreError> {
    db(database_path).remove_favorite(id)
}

fn db(database_path: Option<String>) -> StreamboxDb {
    StreamboxDb::new(database_path.map(PathBuf::from))
}
