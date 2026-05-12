use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreHealth {
    pub native_core_available: bool,
    pub api_version: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HealthJson {
    pub available: bool,
    pub version: &'static str,
    pub api_version: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PlatformInfo {
    pub target_os: &'static str,
    pub target_arch: &'static str,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EchoPayload {
    pub echo: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlaybackItem {
    pub id: String,
    pub track: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<Value>,
    pub added_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Favorite {
    pub id: String,
    pub item: Value,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FavoriteAddRequest {
    pub database_path: Option<String>,
    pub item: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct FavoriteListRequest {
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FavoriteRemoveRequest {
    pub database_path: Option<String>,
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HistoryAddRequest {
    pub db_path: Option<String>,
    pub item: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryListRequest {
    pub db_path: Option<String>,
    pub limit: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryClearRequest {
    pub db_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub tracks: Vec<PlaybackItem>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlaylistCreate {
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub tracks: Vec<PlaybackItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlaylistUpdate {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tracks: Option<Vec<PlaybackItem>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlaylistDelete {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct PlaylistList {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceIndexEntry {
    pub source_provider: String,
    pub source_id: String,
    pub source_url: String,
    pub title: String,
    #[serde(default)]
    pub artist: String,
    #[serde(default)]
    pub album: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<f64>,
    #[serde(default)]
    pub confidence_score: f64,
    #[serde(default)]
    pub rank_reason: String,
    #[serde(default)]
    pub artwork_url: String,
    #[serde(default)]
    pub source_kind: String,
    #[serde(default)]
    pub raw_title: String,
    #[serde(default)]
    pub canonical_title: String,
    #[serde(default)]
    pub canonical_artist: String,
    #[serde(default)]
    pub parse_source: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceIndexSearchRequest {
    #[serde(default, alias = "db_path")]
    pub database_path: Option<String>,
    pub query: String,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub scope: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SourceIndexUpsertRequest {
    #[serde(default, alias = "db_path")]
    pub database_path: Option<String>,
    #[serde(default)]
    pub entries: Vec<SourceIndexEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct SourceIndexClearRequest {
    #[serde(default, alias = "db_path")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct SourceIndexRebuildRequest {
    #[serde(default, alias = "db_path")]
    pub database_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SourceIndexSchemaStatus {
    pub schema_key: String,
    pub schema_version: String,
    pub rebuilt: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DbHealth {
    pub path: String,
    pub schema_version: i64,
    pub user_version: i64,
    pub foreign_keys_enabled: bool,
}
