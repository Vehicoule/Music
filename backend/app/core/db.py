from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def init(self) -> None:
        with self.connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS metadata_cache (
                    cache_key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS playlists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS playlist_tracks (
                    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    item_json TEXT NOT NULL,
                    PRIMARY KEY (playlist_id, position)
                );

                CREATE TABLE IF NOT EXISTS favorites (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS history (
                    id TEXT PRIMARY KEY,
                    item_json TEXT NOT NULL,
                    played_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS source_index (
                    source_provider TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    source_url TEXT NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL DEFAULT '',
                    album TEXT NOT NULL DEFAULT '',
                    duration_seconds REAL,
                    normalized_text TEXT NOT NULL,
                    confidence_score REAL NOT NULL DEFAULT 0,
                    rank_reason TEXT NOT NULL DEFAULT '',
                    artwork_url TEXT NOT NULL DEFAULT '',
                    source_kind TEXT NOT NULL DEFAULT '',
                    raw_title TEXT NOT NULL DEFAULT '',
                    canonical_title TEXT NOT NULL DEFAULT '',
                    canonical_artist TEXT NOT NULL DEFAULT '',
                    parse_source TEXT NOT NULL DEFAULT '',
                    last_matched_at INTEGER NOT NULL,
                    PRIMARY KEY (source_provider, source_id)
                );
                """
            )
            self._ensure_source_index_schema(db)
            self._sync_source_index_version(db)
            db.executescript(
                """
                CREATE INDEX IF NOT EXISTS idx_favorites_created_at
                ON favorites(created_at DESC);

                CREATE INDEX IF NOT EXISTS idx_history_played_at
                ON history(played_at DESC);

                CREATE INDEX IF NOT EXISTS idx_playlists_updated_at
                ON playlists(updated_at DESC);

                CREATE INDEX IF NOT EXISTS idx_source_index_last_matched_at
                ON source_index(last_matched_at DESC);

                CREATE INDEX IF NOT EXISTS idx_source_index_source_kind
                ON source_index(source_kind);
                """
            )
            db.executescript(
                """
                DROP TABLE IF EXISTS source_index_fts;

                CREATE VIRTUAL TABLE IF NOT EXISTS source_index_fts
                USING fts5(source_provider UNINDEXED, source_id UNINDEXED, normalized_text);

                INSERT INTO source_index_fts(source_provider, source_id, normalized_text)
                SELECT source_provider, source_id, normalized_text FROM source_index;
                """
            )

    def _ensure_source_index_schema(self, db: sqlite3.Connection) -> None:
        columns = {row["name"] for row in db.execute("PRAGMA table_info(source_index)").fetchall()}
        additions = {
            "artwork_url": "artwork_url TEXT NOT NULL DEFAULT ''",
            "source_kind": "source_kind TEXT NOT NULL DEFAULT ''",
            "raw_title": "raw_title TEXT NOT NULL DEFAULT ''",
            "canonical_title": "canonical_title TEXT NOT NULL DEFAULT ''",
            "canonical_artist": "canonical_artist TEXT NOT NULL DEFAULT ''",
            "parse_source": "parse_source TEXT NOT NULL DEFAULT ''",
        }
        for name, definition in additions.items():
            if name not in columns:
                db.execute(f"ALTER TABLE source_index ADD COLUMN {definition}")

    def _sync_source_index_version(self, db: sqlite3.Connection) -> None:
        row = db.execute(
            "SELECT payload FROM metadata_cache WHERE cache_key = ?",
            ("source-index:schema-version:v4",),
        ).fetchone()
        if not row or row["payload"] != '"4"':
            db.execute("DELETE FROM source_index")
        db.execute(
            """
            INSERT INTO metadata_cache(cache_key, payload, created_at)
            VALUES ('source-index:schema-version:v4', '"4"', strftime('%s', 'now'))
            ON CONFLICT(cache_key) DO UPDATE SET
                payload = excluded.payload,
                created_at = excluded.created_at
            """
        )

    def get_cache(self, cache_key: str, ttl_seconds: int) -> Any | None:
        with self.connect() as db:
            row = db.execute(
                "SELECT payload, created_at FROM metadata_cache WHERE cache_key = ?",
                (cache_key,),
            ).fetchone()
        if not row:
            return None
        if int(time.time()) - row["created_at"] > ttl_seconds:
            return None
        return json.loads(row["payload"])

    def set_cache(self, cache_key: str, payload: Any) -> None:
        with self.connect() as db:
            db.execute(
                """
                INSERT INTO metadata_cache(cache_key, payload, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(cache_key) DO UPDATE SET
                    payload = excluded.payload,
                    created_at = excluded.created_at
                """,
                (cache_key, json.dumps(payload), int(time.time())),
            )
