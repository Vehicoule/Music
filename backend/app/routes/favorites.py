from __future__ import annotations

import json
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter

from app.routes.dependencies import DbDep
from app.schemas import Favorite, FavoriteCreate, HistoryCreate, PlaybackItem

router = APIRouter(prefix="/api", tags=["library"])


@router.get("/favorites", response_model=list[Favorite])
async def list_favorites(db: DbDep) -> list[Favorite]:
    with db.connect() as connection:
        rows = connection.execute("SELECT * FROM favorites ORDER BY created_at DESC").fetchall()
    return [
        Favorite(
            id=row["id"],
            item=PlaybackItem.model_validate(json.loads(row["item_json"])),
            created_at=datetime.fromtimestamp(row["created_at"], timezone.utc),
        )
        for row in rows
    ]


@router.post("/favorites", response_model=Favorite, status_code=201)
async def create_favorite(payload: FavoriteCreate, db: DbDep) -> Favorite:
    favorite = Favorite(id=str(uuid4()), item=payload.item)
    with db.connect() as connection:
        connection.execute(
            "INSERT INTO favorites(id, item_json, created_at) VALUES (?, ?, ?)",
            (favorite.id, favorite.item.model_dump_json(), int(favorite.created_at.timestamp())),
        )
    return favorite


@router.delete("/favorites/{favorite_id}", status_code=204)
async def delete_favorite(favorite_id: str, db: DbDep) -> None:
    with db.connect() as connection:
        connection.execute("DELETE FROM favorites WHERE id = ?", (favorite_id,))


@router.get("/history", response_model=list[PlaybackItem])
async def list_history(db: DbDep) -> list[PlaybackItem]:
    with db.connect() as connection:
        rows = connection.execute(
            "SELECT * FROM history ORDER BY played_at DESC LIMIT 100"
        ).fetchall()
    return [PlaybackItem.model_validate(json.loads(row["item_json"])) for row in rows]


@router.post("/history", response_model=PlaybackItem, status_code=201)
async def add_history(payload: HistoryCreate, db: DbDep) -> PlaybackItem:
    with db.connect() as connection:
        connection.execute(
            "INSERT INTO history(id, item_json, played_at) VALUES (?, ?, ?)",
            (
                str(uuid4()),
                payload.item.model_dump_json(),
                int(datetime.now(timezone.utc).timestamp()),
            ),
        )
    return payload.item
