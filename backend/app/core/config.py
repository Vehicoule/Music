from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    app_name: str = "Streambox"
    database_path: Path = Path("./data/streambox.sqlite3")
    musicbrainz_base_url: str = "https://musicbrainz.org/ws/2"
    cover_art_base_url: str = "https://coverartarchive.org"
    listenbrainz_base_url: str = "https://api.listenbrainz.org"
    musicbrainz_user_agent: str = Field(
        default="Streambox/0.1.0 ( local-dev@example.invalid )",
        description="Required by MusicBrainz so maintainers can contact the app owner.",
    )
    metadata_cache_ttl_seconds: int = 60 * 60 * 24 * 7
    popularity_cache_ttl_seconds: int = 60 * 60 * 24 * 7
    source_match_cache_ttl_seconds: int = 60 * 30
    ytmusic_cache_ttl_seconds: int = 60 * 60
    metadata_artwork_lookup_limit: int = 5
    musicbrainz_min_interval_seconds: float = 1.05
    listenbrainz_timeout_seconds: float = 5.0

    ytdlp_binary: str = "yt-dlp"
    ytdlp_python: str | None = None
    ytdlp_timeout_seconds: float = 15.0
    ytdlp_discovery_timeout_seconds: float = 5.0
    enable_ytmusic: bool = True
    enable_ytdlp: bool = True
    enable_direct_url: bool = True
    enable_internet_radio: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
