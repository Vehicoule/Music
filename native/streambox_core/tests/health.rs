use std::ffi::{CStr, CString};

use serde_json::Value;
use streambox_core::ffi::{
    streambox_echo_json, streambox_health_json, streambox_platform_info_json, streambox_string_free,
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

unsafe fn take_owned_json(pointer: *mut std::os::raw::c_char) -> Value {
    assert!(!pointer.is_null());
    let json = CStr::from_ptr(pointer).to_string_lossy().into_owned();
    streambox_string_free(pointer);
    serde_json::from_str(&json).unwrap()
}
