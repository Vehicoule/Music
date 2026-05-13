pub mod db;
pub mod error;
pub mod favorites;
pub mod ffi;
pub mod history;
pub mod models;
pub mod playlists;
pub mod ranking;
pub mod services;

pub use models::{CoreHealth, HealthJson, PlatformInfo};

pub const CORE_VERSION: &str = "streambox-core 0.1.0";
pub const CORE_API_VERSION: &str = "0.3.0";

pub fn version() -> &'static str {
    CORE_VERSION
}

pub fn health() -> CoreHealth {
    CoreHealth {
        native_core_available: true,
        api_version: CORE_API_VERSION,
    }
}

pub fn health_json() -> HealthJson {
    HealthJson {
        available: true,
        version: CORE_VERSION,
        api_version: CORE_API_VERSION,
    }
}

pub fn platform_info() -> PlatformInfo {
    PlatformInfo {
        target_os: std::env::consts::OS,
        target_arch: std::env::consts::ARCH,
    }
}
