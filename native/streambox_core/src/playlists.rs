use std::path::PathBuf;

use crate::db;
use crate::error::CoreError;
use crate::models::{Playlist, PlaylistCreate, PlaylistDelete, PlaylistList, PlaylistUpdate};

pub fn list(payload: PlaylistList) -> Result<Vec<Playlist>, CoreError> {
    db::list_playlists(database_path(payload.database_path))
}

pub fn create(payload: PlaylistCreate) -> Result<Playlist, CoreError> {
    let path = database_path(payload.database_path.clone());
    db::create_playlist(path, payload)
}

pub fn update(payload: PlaylistUpdate) -> Result<Playlist, CoreError> {
    let path = database_path(payload.database_path.clone());
    db::update_playlist(path, payload)
}

pub fn delete(payload: PlaylistDelete) -> Result<(), CoreError> {
    db::delete_playlist(database_path(payload.database_path), &payload.id)
}

fn database_path(path: Option<String>) -> PathBuf {
    path.map(PathBuf::from)
        .unwrap_or_else(db::default_database_path)
}
