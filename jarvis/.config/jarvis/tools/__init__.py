"""Registry de tools para Jarvis con validación pydantic.

Cualquier tool no listado aquí se rechaza con `tool not allowed`.
Las funciones reciben modelos pydantic validados y devuelven dicts/strings serializables.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Awaitable, Callable, TYPE_CHECKING

from pydantic import BaseModel


class ToolError(RuntimeError):
    """Error controlado durante la ejecución de una tool (se reporta al modelo)."""


@dataclass
class ToolEntry:
    schema: type[BaseModel]
    run: Callable[[BaseModel], Awaitable[Any]]
    description: str


REGISTRY: dict[str, ToolEntry] = {}


def register(name: str, schema: type[BaseModel], description: str):
    """Decorador para registrar una tool en el registry global."""

    def decorator(fn: Callable[[BaseModel], Awaitable[Any]]) -> Callable[[BaseModel], Awaitable[Any]]:
        REGISTRY[name] = ToolEntry(schema=schema, run=fn, description=description)
        return fn

    return decorator


# Import side-effect: registrar todas las tools al cargar este paquete.
# El daemon importa este __init__ y obtiene el registry poblado.
from . import system as _system  # noqa: E402,F401
from . import search as _search  # noqa: E402,F401
from . import memory as _memory  # noqa: E402,F401


def build_tool_schemas(config: Any) -> list[dict[str, Any]]:
    """Devuelve los schemas JSON de tools en formato Ollama /api/chat."""
    schemas: list[dict[str, Any]] = []
    for name, entry in REGISTRY.items():
        json_schema = entry.schema.model_json_schema()
        # Ollama espera el formato OpenAI-compatible
        schemas.append(
            {
                "type": "function",
                "function": {
                    "name": name,
                    "description": entry.description,
                    "parameters": json_schema,
                },
            }
        )
    return schemas


if TYPE_CHECKING:  # pragma: no cover
    pass
