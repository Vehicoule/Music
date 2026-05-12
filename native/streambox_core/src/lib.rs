pub mod error;
pub mod ffi;
pub mod models;

use serde_json::Value;

pub use models::{CoreHealth, PlatformInfo};

pub const CORE_VERSION: &str = "streambox-core 0.1.0";
pub const CORE_API_VERSION: &str = "0.1.0";

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

pub fn echo(input: Value) -> Value {
    input
}
