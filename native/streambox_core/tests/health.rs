use std::ffi::{CStr, CString};

use rusqlite::Connection;
use serde_json::{json, Value};
use streambox_core::db::{db_health, SCHEMA_VERSION};
use streambox_core::ffi::{
    streambox_db_health_json, streambox_echo_json, streambox_favorites_add_json,
    streambox_favorites_list_json, streambox_favorites_remove_json, streambox_health_json,
    streambox_history_add_json, streambox_history_list_json, streambox_platform_info_json,
    streambox_playlists_create_json, streambox_playlists_delete_json,
    streambox_source_index_search_json, streambox_string_free,
};
use streambox_core::{health, platform_info, version};

#[test]
fn exposes_phase_one_core_identity() {
    assert_eq!(version(), "streambox-core 0.1.0");
    assert!(health().native_core_available);
    assert_eq!(health().api_version, "0.1.0");
    assert!(!platform_info().target_os.is_empty());
}

#[test]
fn serializes_health_and_platform_as_json() {
    let health_json = unsafe { take_owned_json(streambox_health_json()) };
    assert_eq!(health_json["available"], true);
    assert_eq!(health_json["version"], "streambox-core 0.1.0");
    assert_eq!(health_json["api_version"], "0.1.0");

    let platform_json = unsafe { take_owned_json(streambox_platform_info_json()) };
    assert!(platform_json["target_os"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    assert!(platform_json["target_arch"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
}

#[test]
fn echoes_json_through_ffi_protocol() {
    let input = CString::new(r#"{"message":"bonjour","count":2}"#).unwrap();

    let output = unsafe { take_owned_json(streambox_echo_json(input.as_ptr())) };

    assert_eq!(output["ok"], true);
    assert_eq!(output["data"]["echo"]["message"], "bonjour");
    assert_eq!(output["data"]["echo"]["count"], 2);
}

#[test]
fn favorites_ffi_adds_lists_duplicates_and_removes_by_id() {
    let db_path = std::env::temp_dir().join(format!(
        "streambox-core-favorites-{}.sqlite3",
        std::process::id()
    ));
    let _ = std::fs::remove_file(&db_path);
    let db_path = db_path.to_string_lossy();
    let item = json!({
        "id": "item-1",
        "track": {"id": "track-1", "title": "Test Song", "artists": []},
        "source": null,
    });

    let first_input =
        CString::new(json!({"database_path": db_path, "item": item}).to_string()).unwrap();
    let first = unsafe { take_owned_json(streambox_favorites_add_json(first_input.as_ptr())) };
    assert_eq!(first["ok"], true);
    assert_eq!(first["data"]["item"]["track"]["title"], "Test Song");

    let duplicate_input =
        CString::new(json!({"database_path": db_path, "item": item}).to_string()).unwrap();
    let duplicate =
        unsafe { take_owned_json(streambox_favorites_add_json(duplicate_input.as_ptr())) };
    assert_eq!(duplicate["ok"], true);
    assert_ne!(first["data"]["id"], duplicate["data"]["id"]);

    let list_input = CString::new(json!({"database_path": db_path}).to_string()).unwrap();
    let list = unsafe { take_owned_json(streambox_favorites_list_json(list_input.as_ptr())) };
    assert_eq!(list["ok"], true);
    assert_eq!(list["data"].as_array().unwrap().len(), 2);

    let remove_input = CString::new(
        json!({"database_path": db_path, "id": first["data"]["id"].as_str().unwrap()}).to_string(),
    )
    .unwrap();
    let remove = unsafe { take_owned_json(streambox_favorites_remove_json(remove_input.as_ptr())) };
    assert_eq!(remove["ok"], true);

    let list_input = CString::new(json!({"database_path": db_path}).to_string()).unwrap();
    let list = unsafe { take_owned_json(streambox_favorites_list_json(list_input.as_ptr())) };
    assert_eq!(list["data"].as_array().unwrap().len(), 1);
    assert_eq!(list["data"][0]["id"], duplicate["data"]["id"]);

    let _ = std::fs::remove_file(db_path.as_ref());
}

#[test]
fn echo_reports_invalid_json_as_protocol_error() {
    let input = CString::new("not json").unwrap();

    let output = unsafe { take_owned_json(streambox_echo_json(input.as_ptr())) };

    assert_eq!(output["ok"], false);
    assert_eq!(output["error"]["code"], "invalid_json");
}

#[test]
fn initializes_sqlite_schema_at_temporary_path() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("streambox.sqlite3");

    let health = db_health(&db_path).unwrap();

    assert_eq!(health.schema_version, SCHEMA_VERSION);
    assert_eq!(health.user_version, SCHEMA_VERSION);
    assert!(health.foreign_keys_enabled);
    assert_eq!(health.path, db_path.to_string_lossy());

    let connection = Connection::open(&db_path).unwrap();
    let tables: Vec<String> = connection
        .prepare(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual table') ORDER BY name",
        )
        .unwrap()
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();

    for expected_table in [
        "favorites",
        "history",
        "metadata_cache",
        "playlist_tracks",
        "playlists",
        "source_index",
        "source_index_fts",
    ] {
        assert!(
            tables.iter().any(|table| table == expected_table),
            "missing table {expected_table}; found {tables:?}"
        );
    }

    let user_version: i64 = connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .unwrap();
    assert_eq!(user_version, SCHEMA_VERSION);

    let source_index_version: String = connection
        .query_row(
            "SELECT payload FROM metadata_cache WHERE cache_key = 'source-index:schema-version:v4'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(source_index_version, "\"4\"");
}

#[test]
fn db_health_ffi_uses_existing_json_error_protocol() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("ffi.sqlite3");
    let input = CString::new(json!({ "path": db_path }).to_string()).unwrap();

    let output = unsafe { take_owned_json(streambox_db_health_json(input.as_ptr())) };

    assert_eq!(output["ok"], true);
    assert_eq!(output["data"]["schema_version"], SCHEMA_VERSION);
    assert_eq!(output["data"]["user_version"], SCHEMA_VERSION);
    assert_eq!(output["data"]["foreign_keys_enabled"], true);

    let invalid_input = CString::new(r#"{"not_path":"missing"}"#).unwrap();
    let error_output = unsafe { take_owned_json(streambox_db_health_json(invalid_input.as_ptr())) };

    assert_eq!(error_output["ok"], false);
    assert_eq!(error_output["error"]["code"], "invalid_request");
}

#[test]
fn removing_nonexistent_favorite_returns_not_found_error() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();

    let remove_input =
        CString::new(json!({"database_path": db_path, "id": "non-existent-id"}).to_string())
            .unwrap();
    let output = unsafe { take_owned_json(streambox_favorites_remove_json(remove_input.as_ptr())) };

    assert_eq!(output["ok"], false);
    assert_eq!(output["error"]["code"], "not_found");
}

#[test]
fn removing_nonexistent_playlist_returns_not_found_error() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();

    let delete_input =
        CString::new(json!({"database_path": db_path, "id": "non-existent-id"}).to_string())
            .unwrap();
    let output = unsafe { take_owned_json(streambox_playlists_delete_json(delete_input.as_ptr())) };

    assert_eq!(output["ok"], false);
    assert_eq!(output["error"]["code"], "not_found");
}

#[test]
fn empty_source_index_query_returns_empty_results() {
    let input = CString::new(json!({"query": "", "limit": 10}).to_string()).unwrap();
    let output = unsafe { take_owned_json(streambox_source_index_search_json(input.as_ptr())) };

    assert_eq!(output["ok"], true);
    assert_eq!(output["data"].as_array().unwrap().len(), 0);
}

#[test]
fn timestamp_roundtrip_through_history() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();
    let timestamp = "2026-05-13T12:00:00Z";

    let add_input = CString::new(
        json!({
            "db_path": db_path,
            "item": {
                "id": "roundtrip-1",
                "track": {"id": "track-rt", "title": "Roundtrip", "artists": []},
                "source": null,
                "added_at": timestamp,
            }
        })
        .to_string(),
    )
    .unwrap();
    let added = unsafe { take_owned_json(streambox_history_add_json(add_input.as_ptr())) };
    assert_eq!(added["ok"], true);
    assert_eq!(added["data"]["added_at"], timestamp);

    let list_input = CString::new(json!({"db_path": db_path, "limit": 10}).to_string()).unwrap();
    let listed = unsafe { take_owned_json(streambox_history_list_json(list_input.as_ptr())) };
    assert_eq!(listed["ok"], true);
    assert_eq!(listed["data"][0]["added_at"], timestamp);
}

#[test]
fn db_health_on_nonexistent_directory_returns_error_gracefully() {
    let nonexistent = if cfg!(windows) {
        "Z:\\nonexistent\\path\\db.sqlite3"
    } else {
        "/nonexistent/path/db.sqlite3"
    };

    let input = CString::new(json!({"path": nonexistent}).to_string()).unwrap();
    let output = unsafe { take_owned_json(streambox_db_health_json(input.as_ptr())) };

    assert_eq!(output["ok"], false);
    assert!(output["error"]["code"].as_str().is_some());
}

#[test]
fn creating_playlist_with_empty_name_succeeds() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();

    let create_input = CString::new(
        json!({
            "database_path": db_path,
            "name": "",
            "tracks": []
        })
        .to_string(),
    )
    .unwrap();
    let output = unsafe { take_owned_json(streambox_playlists_create_json(create_input.as_ptr())) };

    assert_eq!(output["ok"], true);
    assert_eq!(output["data"]["name"], "");
    assert_rfc3339_utc(output["data"]["created_at"].as_str().unwrap());
}

#[test]
fn listing_history_with_limit_zero_returns_empty_list() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("streambox.sqlite3")
        .to_string_lossy()
        .into_owned();

    let list_input = CString::new(json!({"db_path": db_path, "limit": 0}).to_string()).unwrap();
    let output = unsafe { take_owned_json(streambox_history_list_json(list_input.as_ptr())) };

    assert_eq!(output["ok"], true);
    assert_eq!(output["data"].as_array().unwrap().len(), 0);
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
