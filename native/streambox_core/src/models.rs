use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{CORE_API_VERSION, CORE_VERSION};

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

#[derive(Debug, Clone, Serialize)]
pub struct HealthJson<'a> {
    pub available: bool,
    pub version: &'a str,
    pub api_version: &'a str,
}

impl Default for HealthJson<'_> {
    fn default() -> Self {
        Self {
            available: true,
            version: CORE_VERSION,
            api_version: CORE_API_VERSION,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct PlatformInfoJson<'a> {
    pub target_os: &'a str,
    pub target_arch: &'a str,
}

impl<'a> From<&'a PlatformInfo> for PlatformInfoJson<'a> {
    fn from(info: &'a PlatformInfo) -> Self {
        Self {
            target_os: info.target_os,
            target_arch: info.target_arch,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct EchoRequest {
    #[serde(flatten)]
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct EchoResponse {
    pub ok: bool,
    pub api_version: &'static str,
    pub echo: Value,
}

impl EchoResponse {
    pub fn new(echo: Value) -> Self {
        Self {
            ok: true,
            api_version: CORE_API_VERSION,
            echo,
        }
    }
}
