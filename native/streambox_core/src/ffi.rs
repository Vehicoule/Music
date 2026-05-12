use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde::Serialize;

use crate::error::ErrorResponse;
use crate::models::{EchoRequest, EchoResponse, HealthJson, PlatformInfoJson};
use crate::{echo, platform_info, version};

#[no_mangle]
pub extern "C" fn streambox_version() -> *mut c_char {
    owned_c_string(version())
}

#[no_mangle]
pub extern "C" fn streambox_health_json() -> *mut c_char {
    json_response(&HealthJson::default())
}

#[no_mangle]
pub extern "C" fn streambox_platform_info_json() -> *mut c_char {
    let info = platform_info();
    json_response(&PlatformInfoJson::from(&info))
}

#[no_mangle]
pub unsafe extern "C" fn streambox_echo_json(input_json: *const c_char) -> *mut c_char {
    if input_json.is_null() {
        return json_response(&ErrorResponse::new(
            "null_input",
            "input_json pointer was null",
        ));
    }

    let input = match CStr::from_ptr(input_json).to_str() {
        Ok(value) => value,
        Err(error) => {
            return json_response(&ErrorResponse::new(
                "invalid_utf8",
                format!("input_json was not valid UTF-8: {error}"),
            ));
        }
    };

    match serde_json::from_str::<EchoRequest>(input) {
        Ok(request) => json_response(&EchoResponse::new(echo(request.payload))),
        Err(error) => json_response(&ErrorResponse::new(
            "invalid_json",
            format!("input_json was not valid JSON: {error}"),
        )),
    }
}

#[no_mangle]
pub unsafe extern "C" fn streambox_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

fn json_response(value: &impl Serialize) -> *mut c_char {
    match serde_json::to_vec(value) {
        Ok(value) => owned_c_string(value),
        Err(_) => owned_c_string(
            r#"{"ok":false,"error":{"code":"serialization_error","message":"failed to serialize JSON response"}}"#,
        ),
    }
}

fn owned_c_string(value: impl Into<Vec<u8>>) -> *mut c_char {
    match CString::new(value) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
