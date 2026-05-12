use std::ffi::{CStr, CString};

use serde_json::{json, Value};
use streambox_core::ffi::{
    streambox_history_add_json, streambox_history_clear_json, streambox_history_list_json,
    streambox_string_free,
};
use streambox_core::history;
use tempfile::NamedTempFile;

#[test]
fn history_lists_newest_first_and_preserves_timestamps() {
    let db = NamedTempFile::new().unwrap();
    let db_path = db.path().to_string_lossy().into_owned();
    let older = sample_item("older", "2026-05-12T10:00:00.000Z");
    let newer = sample_item("newer", "2026-05-12T10:00:01.123Z");

    history::add_history(Some(&db_path), older).unwrap();
    std::thread::sleep(std::time::Duration::from_secs(1));
    history::add_history(Some(&db_path), newer).unwrap();

    let items = history::list_history(Some(&db_path), None).unwrap();
    assert_eq!(items[0]["id"], "newer");
    assert_eq!(items[0]["added_at"], "2026-05-12T10:00:01.123Z");
    assert_eq!(items[1]["id"], "older");
    assert_eq!(items[1]["added_at"], "2026-05-12T10:00:00.000Z");
}

#[test]
fn history_allows_duplicate_playback_items() {
    let db = NamedTempFile::new().unwrap();
    let db_path = db.path().to_string_lossy().into_owned();
    let item = sample_item("duplicate", "2026-05-12T10:00:00.000Z");

    history::add_history(Some(&db_path), item.clone()).unwrap();
    history::add_history(Some(&db_path), item).unwrap();

    let items = history::list_history(Some(&db_path), None).unwrap();
    assert_eq!(items.len(), 2);
    assert!(items.iter().all(|item| item["id"] == "duplicate"));
}

#[test]
fn clear_history_removes_all_entries() {
    let db = NamedTempFile::new().unwrap();
    let db_path = db.path().to_string_lossy().into_owned();
    history::add_history(
        Some(&db_path),
        sample_item("one", "2026-05-12T10:00:00.000Z"),
    )
    .unwrap();

    history::clear_history(Some(&db_path)).unwrap();

    assert!(history::list_history(Some(&db_path), None)
        .unwrap()
        .is_empty());
}

#[test]
fn history_ffi_exposes_add_list_and_clear_json_protocol() {
    let db = NamedTempFile::new().unwrap();
    let db_path = db.path().to_string_lossy();
    let add = CString::new(
        json!({
            "db_path": db_path,
            "item": sample_item("ffi", "2026-05-12T10:00:00.000Z")
        })
        .to_string(),
    )
    .unwrap();

    let add_output = unsafe { take_owned_json(streambox_history_add_json(add.as_ptr())) };
    assert_eq!(add_output["ok"], true);
    assert_eq!(add_output["data"]["id"], "ffi");

    let list = CString::new(json!({"db_path": db_path}).to_string()).unwrap();
    let list_output = unsafe { take_owned_json(streambox_history_list_json(list.as_ptr())) };
    assert_eq!(list_output["ok"], true);
    assert_eq!(list_output["data"].as_array().unwrap().len(), 1);

    let clear = CString::new(json!({"db_path": db_path}).to_string()).unwrap();
    let clear_output = unsafe { take_owned_json(streambox_history_clear_json(clear.as_ptr())) };
    assert_eq!(clear_output["ok"], true);
    let list_output = unsafe { take_owned_json(streambox_history_list_json(list.as_ptr())) };
    assert!(list_output["data"].as_array().unwrap().is_empty());
}

fn sample_item(id: &str, added_at: &str) -> Value {
    json!({
        "id": id,
        "track": {
            "id": id,
            "title": format!("Track {id}"),
            "artists": [{"id": "artist-1", "name": "Artist"}],
            "source": "musicbrainz"
        },
        "source": null,
        "added_at": added_at
    })
}

unsafe fn take_owned_json(pointer: *mut std::os::raw::c_char) -> Value {
    assert!(!pointer.is_null());
    let json = CStr::from_ptr(pointer).to_string_lossy().into_owned();
    streambox_string_free(pointer);
    serde_json::from_str(&json).unwrap()
}
