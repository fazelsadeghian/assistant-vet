from abc import ABC, abstractmethod
from typing import Any, Dict

class AIProvider(ABC):
    name: str

    @abstractmethod
    async def available(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    async def reason(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    async def review(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        raise NotImplementedError
