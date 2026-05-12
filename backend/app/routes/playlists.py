from __future__ import annotations

import json
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, HTTPException

from app.routes.dependencies import DbDep
from app.schemas import Playlist, PlaylistCreate, PlaylistUpdate, PlaybackItem

router = APIRouter(prefix="/api/playlists", tags=["playlists"])


@router.get("", response_model=list[Playlist])
async def list_playlists(db: DbDep) -> list[Playlist]:
    with db.connect() as connection:
        rows = connection.execute("SELECT * FROM playlists ORDER BY updated_at DESC").fetchall()
    return [_load_playlist(db, row["id"]) for row in rows]


@router.post("", response_model=Playlist, status_code=201)
async def create_playlist(payload: PlaylistCreate, db: DbDep) -> Playlist:
    now = datetime.now(timezone.utc)
    playlist = Playlist(
        id=str(uuid4()),
        name=payload.name,
        description=payload.description,
        tracks=payload.tracks,
        created_at=now,
        updated_at=now,
    )
    _save_playlist(db, playlist)
    return playlist


@router.put("/{playlist_id}", response_model=Playlist)
async def update_playlist(playlist_id: str, payload: PlaylistUpdate, db: DbDep) -> Playlist:
    current = _load_playlist(db, playlist_id)
    if payload.name is not None:
        current.name = payload.name
    if payload.description is not None:
        current.description = payload.description
    if payload.tracks is not None:
        current.tracks = payload.tracks
    current.updated_at = datetime.now(timezone.utc)
    _save_playlist(db, current)
    return current


def _load_playlist(db: DbDep, playlist_id: str) -> Playlist:
    with db.connect() as connection:
        row = connection.execute("SELECT * FROM playlists WHERE id = ?", (playlist_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Playlist not found")
        track_rows = connection.execute(
            "SELECT item_json FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
            (playlist_id,),
        ).fetchall()
    return Playlist(
        id=row["id"],
        name=row["name"],
        description=row["description"],
        tracks=[PlaybackItem.model_validate(json.loads(item["item_json"])) for item in track_rows],
        created_at=datetime.fromtimestamp(row["created_at"], timezone.utc),
        updated_at=datetime.fromtimestamp(row["updated_at"], timezone.utc),
    )


def _save_playlist(db: DbDep, playlist: Playlist) -> None:
    with db.connect() as connection:
        connection.execute(
            """
            INSERT INTO playlists(id, name, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                updated_at = excluded.updated_at
            """,
            (
                playlist.id,
                playlist.name,
                playlist.description,
                int(playlist.created_at.timestamp()),
                int(playlist.updated_at.timestamp()),
            ),
        )
        connection.execute("DELETE FROM playlist_tracks WHERE playlist_id = ?", (playlist.id,))
        connection.executemany(
            "INSERT INTO playlist_tracks(playlist_id, position, item_json) VALUES (?, ?, ?)",
            [
                (playlist.id, position, item.model_dump_json())
                for position, item in enumerate(playlist.tracks)
            ],
        )

