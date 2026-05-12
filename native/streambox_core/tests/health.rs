use std::ffi::{CStr, CString};

use rusqlite::Connection;
use serde_json::Value;
use streambox_core::db::{db_health, SCHEMA_VERSION};
use streambox_core::ffi::{
    streambox_db_health_json, streambox_echo_json, streambox_health_json,
    streambox_platform_info_json, streambox_string_free,
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
    let input = CString::new(format!(r#"{{"path":"{}"}}"#, db_path.display())).unwrap();

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

unsafe fn take_owned_json(pointer: *mut std::os::raw::c_char) -> Value {
    assert!(!pointer.is_null());
    let json = CStr::from_ptr(pointer).to_string_lossy().into_owned();
    streambox_string_free(pointer);
    serde_json::from_str(&json).unwrap()
}
