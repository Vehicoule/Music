use std::ffi::{CStr, CString};

use serde_json::{json, Value};
use streambox_core::ffi::{
    streambox_favorites_add_json, streambox_favorites_list_json, streambox_favorites_remove_json,
    streambox_history_add_json, streambox_history_list_json, streambox_playlists_create_json,
    streambox_playlists_delete_json, streambox_playlists_list_json,
    streambox_playlists_update_json, streambox_string_free,
};

#[test]
fn playlist_ffi_json_matches_fastapi_fixture_shapes() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("streambox.sqlite3");
    let create_fixture = fixture("playlists/create.json");
    let list_fixture = fixture("playlists/list.json");
    let mut create_request = create_fixture["request"].clone();
    create_request["database_path"] = json!(db_path);

    let created = call_json(streambox_playlists_create_json, create_request);
    assert_eq!(created["ok"], true);
    assert_same_shape(&created["data"], &create_fixture["response"]);
    assert_field_names(&created["data"], &create_fixture["response"]);
    assert_eq!(created["data"]["name"], create_fixture["response"]["name"]);
    assert_eq!(
        created["data"]["tracks"][0]["track"]["canonical_artist"],
        "Fixture Artist"
    );

    let listed = call_json(
        streambox_playlists_list_json,
        json!({"database_path": db_path}),
    );
    assert_eq!(listed["ok"], true);
    assert_same_shape(&listed["data"], &list_fixture["response"]);
    assert_field_names(&listed["data"], &list_fixture["response"]);

    let updated = call_json(
        streambox_playlists_update_json,
        json!({
            "database_path": db_path,
            "id": created["data"]["id"],
            "name": "Updated road trip",
            "description": "Still FastAPI-shaped",
            "tracks": create_fixture["request"]["tracks"],
        }),
    );
    assert_eq!(updated["ok"], true);
    assert_same_shape(&updated["data"], &create_fixture["response"]);
    assert_field_names(&updated["data"], &create_fixture["response"]);
    assert_eq!(updated["data"]["name"], "Updated road trip");

    let deleted = call_json(
        streambox_playlists_delete_json,
        json!({"database_path": db_path, "id": created["data"]["id"]}),
    );
    assert_eq!(deleted, json!({"ok": true, "data": {}}));
}

#[test]
fn favorites_ffi_json_matches_fastapi_fixture_shapes() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("streambox.sqlite3");
    let add_fixture = fixture("favorites/add.json");
    let list_fixture = fixture("favorites/list.json");

    let added = call_json(
        streambox_favorites_add_json,
        json!({
            "database_path": db_path,
            "item": add_fixture["request"]["item"],
        }),
    );
    assert_eq!(added["ok"], true);
    assert_same_shape(&added["data"], &add_fixture["response"]);
    assert_field_names(&added["data"], &add_fixture["response"]);
    assert_rfc3339_utc(added["data"]["created_at"].as_str().unwrap());
    assert_eq!(
        added["data"]["item"]["track"]["canonical_title"],
        "Fixture Song"
    );

    let listed = call_json(
        streambox_favorites_list_json,
        json!({"database_path": db_path}),
    );
    assert_eq!(listed["ok"], true);
    assert_same_shape(&listed["data"], &list_fixture["response"]);
    assert_field_names(&listed["data"], &list_fixture["response"]);
    assert_rfc3339_utc(listed["data"][0]["created_at"].as_str().unwrap());

    let removed = call_json(
        streambox_favorites_remove_json,
        json!({"database_path": db_path, "id": added["data"]["id"]}),
    );
    assert_eq!(removed, json!({"ok": true, "data": {}}));
}

#[test]
fn history_ffi_json_matches_fastapi_fixture_shapes() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("streambox.sqlite3");
    let add_fixture = fixture("history/add.json");
    let list_fixture = fixture("history/list.json");

    let added = call_json(
        streambox_history_add_json,
        json!({
            "db_path": db_path,
            "item": add_fixture["request"]["item"],
        }),
    );
    assert_eq!(added["ok"], true);
    assert_same_shape(&added["data"], &add_fixture["response"]);
    assert_field_names(&added["data"], &add_fixture["response"]);
    assert_eq!(added["data"]["track"]["source_provider"], "ytmusic");

    let listed = call_json(streambox_history_list_json, json!({"db_path": db_path}));
    assert_eq!(listed["ok"], true);
    assert_same_shape(&listed["data"], &list_fixture["response"]);
    assert_field_names(&listed["data"], &list_fixture["response"]);
}

fn assert_field_names(actual: &Value, expected: &Value) {
    match (actual, expected) {
        (Value::Object(actual), Value::Object(expected)) => {
            let mut actual_keys = actual.keys().map(String::as_str).collect::<Vec<_>>();
            let mut expected_keys = expected.keys().map(String::as_str).collect::<Vec<_>>();
            actual_keys.sort_unstable();
            expected_keys.sort_unstable();
            assert_eq!(actual_keys, expected_keys);
            for key in expected.keys() {
                assert_field_names(&actual[key], &expected[key]);
            }
        }
        (Value::Array(actual), Value::Array(expected)) => {
            if let (Some(actual), Some(expected)) = (actual.first(), expected.first()) {
                assert_field_names(actual, expected);
            }
        }
        _ => {}
    }
}

fn assert_rfc3339_utc(value: &str) {
    assert!(
        value.ends_with('Z') && value.contains('T'),
        "expected UTC RFC3339 timestamp, got {value}"
    );
}

fn fixture(relative_path: &str) -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../docs/api-contract-fixtures")
        .join(relative_path);
    let contents = std::fs::read_to_string(path).unwrap();
    serde_json::from_str(&contents).unwrap()
}

fn call_json(
    function: unsafe extern "C" fn(*const std::os::raw::c_char) -> *mut std::os::raw::c_char,
    input: Value,
) -> Value {
    let input = CString::new(input.to_string()).unwrap();
    unsafe { take_owned_json(function(input.as_ptr())) }
}

fn assert_same_shape(actual: &Value, expected: &Value) {
    match (actual, expected) {
        (Value::Object(actual), Value::Object(expected)) => {
            let mut actual_keys = actual.keys().collect::<Vec<_>>();
            let mut expected_keys = expected.keys().collect::<Vec<_>>();
            actual_keys.sort();
            expected_keys.sort();
            assert_eq!(actual_keys, expected_keys);
            for key in expected.keys() {
                assert_same_shape(&actual[key], &expected[key]);
            }
        }
        (Value::Array(actual), Value::Array(expected)) => {
            assert_eq!(actual.is_empty(), expected.is_empty());
            if let (Some(actual), Some(expected)) = (actual.first(), expected.first()) {
                assert_same_shape(actual, expected);
            }
        }
        (Value::String(_), Value::String(_))
        | (Value::Number(_), Value::Number(_))
        | (Value::Bool(_), Value::Bool(_))
        | (Value::Null, Value::Null) => {}
        _ => panic!("shape mismatch: actual={actual:?} expected={expected:?}"),
    }
}

unsafe fn take_owned_json(pointer: *mut std::os::raw::c_char) -> Value {
    assert!(!pointer.is_null());
    let json = CStr::from_ptr(pointer).to_string_lossy().into_owned();
    streambox_string_free(pointer);
    serde_json::from_str(&json).unwrap()
}
