use std::ffi::CString;
use std::os::raw::c_char;

pub const CORE_VERSION: &str = "streambox-core 0.1.0";
pub const CORE_API_VERSION: &str = "0.1.0";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreHealth {
    pub native_core_available: bool,
    pub api_version: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlatformInfo {
    pub target_os: &'static str,
    pub target_arch: &'static str,
}

pub fn version() -> &'static str {
    CORE_VERSION
}

pub fn health() -> CoreHealth {
    CoreHealth {
        native_core_available: true,
        api_version: CORE_API_VERSION,
    }
}

pub fn platform_info() -> PlatformInfo {
    PlatformInfo {
        target_os: std::env::consts::OS,
        target_arch: std::env::consts::ARCH,
    }
}

#[no_mangle]
pub extern "C" fn streambox_version() -> *mut c_char {
    owned_c_string(version())
}

#[no_mangle]
pub extern "C" fn streambox_health_json() -> *mut c_char {
    let value = format!(
        "{{\"available\":true,\"version\":\"{}\",\"api_version\":\"{}\"}}",
        CORE_VERSION, CORE_API_VERSION
    );
    owned_c_string(value)
}

#[no_mangle]
pub extern "C" fn streambox_platform_info_json() -> *mut c_char {
    let info = platform_info();
    let value = format!(
        "{{\"target_os\":\"{}\",\"target_arch\":\"{}\"}}",
        info.target_os, info.target_arch
    );
    owned_c_string(value)
}

#[no_mangle]
pub unsafe extern "C" fn streambox_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

fn owned_c_string(value: impl Into<Vec<u8>>) -> *mut c_char {
    match CString::new(value) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
