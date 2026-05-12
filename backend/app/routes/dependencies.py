from typing import Annotated

from fastapi import Depends, Request

from app.core.db import Database
from app.services.musicbrainz import MusicBrainzClient
from app.services.source_index import SourceIndex
from app.sources.registry import SourceRegistry


def get_db(request: Request) -> Database:
    return request.app.state.db


def get_musicbrainz(request: Request) -> MusicBrainzClient:
    return request.app.state.musicbrainz


def get_sources(request: Request) -> SourceRegistry:
    return request.app.state.sources


def get_source_index(request: Request) -> SourceIndex:
    return request.app.state.source_index


DbDep = Annotated[Database, Depends(get_db)]
MusicBrainzDep = Annotated[MusicBrainzClient, Depends(get_musicbrainz)]
SourcesDep = Annotated[SourceRegistry, Depends(get_sources)]
SourceIndexDep = Annotated[SourceIndex, Depends(get_source_index)]
