use std::ffi::{CStr, CString};

use serde_json::{json, Value};
use streambox_core::db;
use streambox_core::ffi::{
    streambox_playlists_create_json, streambox_playlists_delete_json,
    streambox_playlists_list_json, streambox_playlists_update_json, streambox_string_free,
};
use streambox_core::models::{PlaybackItem, PlaylistCreate, PlaylistUpdate};

#[test]
fn stores_updates_lists_and_deletes_playlists_in_sqlite() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir.path().join("streambox.sqlite3");
    db::init_database(&database_path).unwrap();

    let item = sample_item("track-1", "Track One");
    let created = db::create_playlist(
        &database_path,
        PlaylistCreate {
            name: "Favorites".to_string(),
            description: "Saved tracks".to_string(),
            tracks: vec![item.clone()],
            database_path: None,
        },
    )
    .unwrap();

    assert_eq!(created.name, "Favorites");
    assert_eq!(created.description, "Saved tracks");
    assert_eq!(created.tracks, vec![item]);
    assert_rfc3339_utc(&created.created_at);
    assert_rfc3339_utc(&created.updated_at);

    let updated_item = sample_item("track-2", "Track Two");
    let updated = db::update_playlist(
        &database_path,
        PlaylistUpdate {
            id: created.id.clone(),
            name: Some("Roadtrip".to_string()),
            description: None,
            tracks: Some(vec![updated_item.clone()]),
            database_path: None,
        },
    )
    .unwrap();

    assert_eq!(updated.name, "Roadtrip");
    assert_eq!(updated.description, "Saved tracks");
    assert_eq!(updated.tracks, vec![updated_item]);
    assert_rfc3339_utc(&updated.created_at);
    assert_rfc3339_utc(&updated.updated_at);

    let playlists = db::list_playlists(&database_path).unwrap();
    assert_eq!(playlists.len(), 1);
    assert_eq!(playlists[0].id, created.id);
    assert_rfc3339_utc(&playlists[0].created_at);
    assert_rfc3339_utc(&playlists[0].updated_at);

    db::delete_playlist(&database_path, &created.id).unwrap();
    assert!(db::list_playlists(&database_path).unwrap().is_empty());
}

#[test]
fn exposes_playlist_crud_through_ffi_json_protocol() {
    let temp_dir = tempfile::tempdir().unwrap();
    let database_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();

    let create_input = CString::new(
        json!({
            "database_path": database_path,
            "name": "Favorites",
            "tracks": [sample_item("track-1", "Track One")]
        })
        .to_string(),
    )
    .unwrap();
    let created =
        unsafe { take_owned_json(streambox_playlists_create_json(create_input.as_ptr())) };
    assert_eq!(created["ok"], true);
    let playlist_id = created["data"]["id"].as_str().unwrap().to_string();
    assert_eq!(created["data"]["tracks"][0]["track"]["title"], "Track One");

    let list_input = CString::new(json!({"database_path": database_path}).to_string()).unwrap();
    let listed = unsafe { take_owned_json(streambox_playlists_list_json(list_input.as_ptr())) };
    assert_eq!(listed["ok"], true);
    assert_eq!(listed["data"].as_array().unwrap().len(), 1);

    let update_input = CString::new(
        json!({
            "database_path": database_path,
            "id": playlist_id,
            "name": "Roadtrip",
            "tracks": [sample_item("track-2", "Track Two")]
        })
        .to_string(),
    )
    .unwrap();
    let updated =
        unsafe { take_owned_json(streambox_playlists_update_json(update_input.as_ptr())) };
    assert_eq!(updated["ok"], true);
    assert_eq!(updated["data"]["name"], "Roadtrip");
    assert_eq!(updated["data"]["tracks"][0]["track"]["id"], "track-2");

    let delete_input = CString::new(
        json!({
            "database_path": database_path,
            "id": playlist_id
        })
        .to_string(),
    )
    .unwrap();
    let deleted =
        unsafe { take_owned_json(streambox_playlists_delete_json(delete_input.as_ptr())) };
    assert_eq!(deleted["ok"], true);

    let list_input = CString::new(json!({"database_path": database_path}).to_string()).unwrap();
    let listed = unsafe { take_owned_json(streambox_playlists_list_json(list_input.as_ptr())) };
    assert!(listed["data"].as_array().unwrap().is_empty());
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

fn assert_rfc3339_utc(value: &str) {
    assert!(
        value.ends_with('Z') && value.contains('T'),
        "expected UTC RFC3339 timestamp, got {value}"
    );
}

unsafe fn take_owned_json(pointer: *mut std::os::raw::c_char) -> Value {
    assert!(!pointer.is_null());
    let json = CStr::from_ptr(pointer).to_string_lossy().into_owned();
    streambox_string_free(pointer);
    serde_json::from_str(&json).unwrap()
}
