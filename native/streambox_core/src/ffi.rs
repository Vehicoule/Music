use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::db::db_health;
use crate::error::CoreError;
use crate::models::{
    EchoPayload, FavoriteAddRequest, FavoriteListRequest, FavoriteRemoveRequest, HistoryAddRequest,
    HistoryClearRequest, HistoryListRequest,
};
use crate::{favorites, health_json, history, platform_info, playlists, version};

#[derive(Debug, Deserialize)]
struct DbHealthRequest {
    path: String,
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
    match read_json_as::<DbHealthRequest>(input_json) {
        Ok(request) => match db_health(request.path) {
            Ok(health) => ok_json(health),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_list_json(input_json: *const c_char) -> *mut c_char {
    match read_json_as::<FavoriteListRequest>(input_json) {
        Ok(request) => match favorites::list_favorites(request.database_path) {
            Ok(items) => ok_json(items),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_add_json(input_json: *const c_char) -> *mut c_char {
    match read_json_as::<FavoriteAddRequest>(input_json) {
        Ok(request) => match favorites::add_favorite(request.database_path, request.item) {
            Ok(item) => ok_json(item),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_remove_json(input_json: *const c_char) -> *mut c_char {
    match read_json_as::<FavoriteRemoveRequest>(input_json) {
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
    match read_json_as::<HistoryListRequest>(input_json) {
        Ok(request) => match history::list_history(request.db_path.as_deref(), request.limit) {
            Ok(items) => ok_json(items),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_history_add_json(input_json: *const c_char) -> *mut c_char {
    match read_json_as::<HistoryAddRequest>(input_json) {
        Ok(request) => match history::add_history(request.db_path.as_deref(), request.item) {
            Ok(item) => ok_json(item),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_history_clear_json(input_json: *const c_char) -> *mut c_char {
    match read_json_as::<HistoryClearRequest>(input_json) {
        Ok(request) => match history::clear_history(request.db_path.as_deref()) {
            Ok(()) => ok_json(json!({})),
            Err(error) => error_json(error),
        },
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

fn read_json<T: serde::de::DeserializeOwned>(input_json: *const c_char) -> Result<T, CoreError> {
    let value = read_json_value(input_json)?;
    serde_json::from_value(value).map_err(|error| CoreError::new("invalid_json", error.to_string()))
}

fn read_json_as<T: for<'de> Deserialize<'de>>(input_json: *const c_char) -> Result<T, CoreError> {
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
