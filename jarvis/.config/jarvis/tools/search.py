"""Tool de búsqueda web vía SearXNG local.

SearXNG corre en docker (servicio user `jarvis-searxng.service`).
Si no está activo, esta tool lo arranca antes de consultar.
"""
from __future__ import annotations

import asyncio
import subprocess

import httpx
from pydantic import BaseModel, Field, conint

from . import ToolError, register

SEARXNG_URL = "http://127.0.0.1:8888"
SERVICE_NAME = "jarvis-searxng.service"


class WebSearchArgs(BaseModel):
    """Busca en la web mediante SearXNG local (privado, agregando múltiples motores)."""

    q: str = Field(..., min_length=2, max_length=200, description="Consulta a buscar")
    top_k: conint(ge=1, le=10) = 5  # type: ignore[valid-type]


async def _ensure_service() -> None:
    proc = await asyncio.create_subprocess_exec(
        "systemctl", "--user", "is-active", "--quiet", SERVICE_NAME
    )
    await proc.wait()
    if proc.returncode == 0:
        return
    start = await asyncio.create_subprocess_exec(
        "systemctl", "--user", "start", SERVICE_NAME,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    _, err = await start.communicate()
    if start.returncode != 0:
        raise ToolError(f"no pude arrancar SearXNG: {err.decode().strip()[:200]}")
    # Pequeña espera a que esté listo
    for _ in range(20):
        try:
            async with httpx.AsyncClient(timeout=1.0) as client:
                r = await client.get(SEARXNG_URL)
                if r.status_code < 500:
                    return
        except httpx.HTTPError:
            pass
        await asyncio.sleep(0.5)
    raise ToolError("SearXNG arrancó pero no responde")


@register("web_search", WebSearchArgs, "Busca en internet mediante SearXNG local. Devuelve título + URL + snippet.")
async def web_search(args: WebSearchArgs) -> list[dict[str, str]]:
    await _ensure_service()
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(
            f"{SEARXNG_URL}/search",
            params={"q": args.q, "format": "json", "safesearch": 1, "language": "es"},
        )
    if resp.status_code != 200:
        raise ToolError(f"SearXNG devolvió {resp.status_code}")
    data = resp.json()
    out: list[dict[str, str]] = []
    for item in (data.get("results") or [])[: args.top_k]:
        out.append(
            {
                "title": item.get("title", "")[:200],
                "url": item.get("url", ""),
                "snippet": (item.get("content") or "")[:300],
            }
        )
    return out
