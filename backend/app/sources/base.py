from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas import AdapterCapability, ResolveRequest, SourceCandidate


class SourceAdapter(ABC):
    @abstractmethod
    async def capability(self) -> AdapterCapability:
        raise NotImplementedError

    @abstractmethod
    async def resolve(self, request: ResolveRequest) -> list[SourceCandidate]:
        raise NotImplementedError

