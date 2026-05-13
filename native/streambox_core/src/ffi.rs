use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::db::{
    clear_source_index, db_health, default_database_path, rebuild_source_index,
    search_source_index_entries, upsert_source_index_entries,
};
use crate::error::CoreError;
use crate::models::{
    EchoPayload, FavoriteAddRequest, FavoriteListRequest, FavoriteRemoveRequest, HistoryAddRequest,
    HistoryClearRequest, HistoryListRequest, MusicBrainzSearchRequest, SourceIndexClearRequest,
    SourceIndexRebuildRequest, SourceIndexSearchRequest, SourceIndexUpsertRequest,
};
use crate::services::musicbrainz::MusicBrainzClient;
use crate::services::ytdlp;
use crate::{favorites, health_json, history, platform_info, playlists, version};

#[derive(Debug, Deserialize)]
struct DbHealthRequest {
    path: String,
}

#[derive(Debug, Deserialize)]
struct YtDlpSearchRequest {
    query: String,
    #[serde(default = "default_search_limit")]
    limit: usize,
}
fn default_search_limit() -> usize {
    15
}

#[derive(Debug, Deserialize)]
struct YtDlpResolveRequest {
    url: String,
}

#[no_mangle]
pub extern "C" fn streambox_version() -> *mut c_char {
    owned_c_string(version())
}

#[no_mangle]
pub extern "C" fn streambox_health_json() -> *mut c_char {
    to_owned_json_string(&health_json())
}

#[no_mangle]
pub extern "C" fn streambox_platform_info_json() -> *mut c_char {
    to_owned_json_string(&platform_info())
}

#[no_mangle]
pub unsafe extern "C" fn streambox_echo_json(input_json: *const c_char) -> *mut c_char {
    match read_json_value(input_json) {
        Ok(value) => ok_json(EchoPayload { echo: value }),
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_db_health_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<DbHealthRequest>(input_json) {
        Ok(request) => match db_health(request.path) {
            Ok(health) => ok_json(health),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_list_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<FavoriteListRequest>(input_json) {
        Ok(request) => match favorites::list_favorites(request.database_path) {
            Ok(items) => ok_json(items),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_add_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<FavoriteAddRequest>(input_json) {
        Ok(request) => match favorites::add_favorite(request.database_path, request.item) {
            Ok(item) => ok_json(item),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_remove_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<FavoriteRemoveRequest>(input_json) {
        Ok(request) => match favorites::remove_favorite(request.database_path, &request.id) {
            Ok(()) => ok_json(json!({})),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_playlists_list_json(input_json: *const c_char) -> *mut c_char {
    match read_json(input_json) {
        Ok(payload) => match playlists::list(payload) {
            Ok(playlists) => ok_json(playlists),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_playlists_create_json(input_json: *const c_char) -> *mut c_char {
    match read_json(input_json) {
        Ok(payload) => match playlists::create(payload) {
            Ok(playlist) => ok_json(playlist),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_playlists_update_json(input_json: *const c_char) -> *mut c_char {
    match read_json(input_json) {
        Ok(payload) => match playlists::update(payload) {
            Ok(playlist) => ok_json(playlist),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_playlists_delete_json(input_json: *const c_char) -> *mut c_char {
    match read_json(input_json) {
        Ok(payload) => match playlists::delete(payload) {
            Ok(()) => ok_json(json!({})),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_history_list_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<HistoryListRequest>(input_json) {
        Ok(request) => match history::list_history(request.db_path.as_deref(), request.limit) {
            Ok(items) => ok_json(items),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_history_add_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<HistoryAddRequest>(input_json) {
        Ok(request) => match history::add_history(request.db_path.as_deref(), request.item) {
            Ok(item) => ok_json(item),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_history_clear_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<HistoryClearRequest>(input_json) {
        Ok(request) => match history::clear_history(request.db_path.as_deref()) {
            Ok(()) => ok_json(json!({})),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_source_index_search_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<SourceIndexSearchRequest>(input_json) {
        Ok(request) => {
            let path = request
                .database_path
                .map(std::path::PathBuf::from)
                .unwrap_or_else(default_database_path);
            match search_source_index_entries(
                path,
                &request.query,
                request.limit.unwrap_or(15),
                request.scope.as_deref(),
            ) {
                Ok(entries) => ok_json(entries),
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_source_index_upsert_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<SourceIndexUpsertRequest>(input_json) {
        Ok(request) => {
            let path = request
                .database_path
                .map(std::path::PathBuf::from)
                .unwrap_or_else(default_database_path);
            match upsert_source_index_entries(path, &request.entries) {
                Ok(count) => ok_json(json!({ "upserted": count })),
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_source_index_clear_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<SourceIndexClearRequest>(input_json) {
        Ok(request) => {
            let path = request
                .database_path
                .map(std::path::PathBuf::from)
                .unwrap_or_else(default_database_path);
            match clear_source_index(path) {
                Ok(()) => ok_json(json!({})),
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_source_index_rebuild_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<SourceIndexRebuildRequest>(input_json) {
        Ok(request) => {
            let path = request
                .database_path
                .map(std::path::PathBuf::from)
                .unwrap_or_else(default_database_path);
            match rebuild_source_index(path) {
                Ok(status) => ok_json(status),
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_musicbrainz_search_json(
    input_json: *const c_char,
) -> *mut c_char {
    match read_json::<MusicBrainzSearchRequest>(input_json) {
        Ok(request) => {
            let limit = if request.limit == 0 {
                15
            } else {
                request.limit
            };
            match MusicBrainzClient::new() {
                Ok(mut client) => match client.search_tracks(&request.query, limit) {
                    Ok(tracks) => ok_json(tracks),
                    Err(error) => error_json(error),
                },
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_ytdlp_search_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<YtDlpSearchRequest>(input_json) {
        Ok(request) => {
            let limit = if request.limit == 0 {
                15
            } else {
                request.limit
            };
            match ytdlp::search(&request.query, limit) {
                Ok(tracks) => ok_json(tracks),
                Err(error) => error_json(error),
            }
        }
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_ytdlp_resolve_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<YtDlpResolveRequest>(input_json) {
        Ok(request) => match ytdlp::resolve_url(&request.url) {
            Ok(track) => ok_json(track),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_ytdlp_available_json(input_json: *const c_char) -> *mut c_char {
    // input_json is ignored; yt-dlp availability is a global check
    let _ = input_json;
    let available = ytdlp::is_available();
    ok_json(json!({ "available": available }))
}

#[no_mangle]
pub unsafe extern "C" fn streambox_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

fn read_json<T: serde::de::DeserializeOwned>(input_json: *const c_char) -> Result<T, CoreError> {
    let value = read_json_value(input_json)?;
    serde_json::from_value(value)
        .map_err(|error| CoreError::new("invalid_request", error.to_string()))
}

fn read_json_value(input_json: *const c_char) -> Result<Value, CoreError> {
    if input_json.is_null() {
        return Err(CoreError::new(
            "null_input",
            "expected a non-null JSON string pointer",
        ));
    }
    let input = unsafe { CStr::from_ptr(input_json) }
        .to_str()
        .map_err(|error| CoreError::new("invalid_utf8", error.to_string()))?;
    serde_json::from_str(input).map_err(|error| CoreError::new("invalid_json", error.to_string()))
}

fn ok_json<T: Serialize>(data: T) -> *mut c_char {
    to_owned_json_string(&json!({
        "ok": true,
        "data": data,
    }))
}

fn error_json(error: CoreError) -> *mut c_char {
    to_owned_json_string(&json!({
        "ok": false,
        "error": error,
    }))
}

fn to_owned_json_string<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(value) => owned_c_string(value),
        Err(error) => error_json(CoreError::new("serialization_failed", error.to_string())),
    }
}

fn owned_c_string(value: impl Into<Vec<u8>>) -> *mut c_char {
    match CString::new(value) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
