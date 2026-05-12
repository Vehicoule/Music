use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::Serialize;
use serde_json::{json, Value};

use crate::error::CoreError;
use crate::favorites;
use crate::models::{DatabaseRequest, EchoPayload, FavoriteCreate, FavoriteDelete};
use crate::{health_json, platform_info, version};

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
pub unsafe extern "C" fn streambox_favorites_list_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<DatabaseRequest<serde_json::Map<String, Value>>>(input_json)
        .and_then(|request| favorites::list_favorites(request.database_path))
    {
        Ok(favorites) => ok_json(favorites),
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_add_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<DatabaseRequest<FavoriteCreate>>(input_json)
        .and_then(|request| favorites::add_favorite(request.database_path, request.payload.item))
    {
        Ok(favorite) => ok_json(favorite),
        Err(error) => error_json(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_favorites_remove_json(input_json: *const c_char) -> *mut c_char {
    match read_json::<DatabaseRequest<FavoriteDelete>>(input_json)
        .and_then(|request| favorites::remove_favorite(request.database_path, &request.payload.id))
    {
        Ok(()) => ok_json(Value::Null),
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
    let value = read_json_string(input_json)?;
    serde_json::from_str(&value).map_err(|error| CoreError::new("invalid_json", error.to_string()))
}

fn read_json_value(input_json: *const c_char) -> Result<Value, CoreError> {
    read_json(input_json)
}

fn read_json_string(input_json: *const c_char) -> Result<String, CoreError> {
    if input_json.is_null() {
        return Err(CoreError::new(
            "null_input",
            "expected a non-null JSON string pointer",
        ));
    }
    let input = unsafe { CStr::from_ptr(input_json) }
        .to_str()
        .map_err(|error| CoreError::new("invalid_utf8", error.to_string()))?;
    Ok(input.to_string())
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
