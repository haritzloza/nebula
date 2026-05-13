"""Memoria persistente con SQLite + sqlite-vec + embeddings de Ollama.

Tabla:
    memories(id, ts, text, tags, embedding BLOB)

Búsqueda: cosine similarity vía sqlite-vec.
"""
from __future__ import annotations

import asyncio
import json
import os
import sqlite3
import struct
import time
from pathlib import Path

import httpx
from pydantic import BaseModel, Field, conint

from . import ToolError, register

DB_PATH = Path(os.path.expandvars(os.path.expanduser(
    os.environ.get("JARVIS_MEMORY_DB", "~/.local/share/jarvis/memory.db")
)))
EMBED_MODEL = os.environ.get("JARVIS_EMBED_MODEL", "nomic-embed-text")
OLLAMA_URL = os.environ.get("OLLAMA_HOST_URL", "http://127.0.0.1:11434")
EMBED_DIM = 768  # nomic-embed-text
MIN_SCORE = 0.55

_db_lock = asyncio.Lock()


def _connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.enable_load_extension(True)
        import sqlite_vec  # type: ignore[import-not-found]

        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
    except (AttributeError, ImportError):
        # Si sqlite-vec no está, caemos a búsqueda brute-force
        pass
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS memories(
            id INTEGER PRIMARY KEY,
            ts INTEGER NOT NULL,
            text TEXT NOT NULL,
            tags TEXT,
            embedding BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS memories_ts ON memories(ts);
        """
    )
    return conn


def _vec_to_blob(vec: list[float]) -> bytes:
    return struct.pack(f"{len(vec)}f", *vec)


def _blob_to_vec(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack(f"{n}f", blob))


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


async def _embed(text: str) -> list[float]:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{OLLAMA_URL}/api/embeddings",
            json={"model": EMBED_MODEL, "prompt": text},
        )
    if resp.status_code != 200:
        raise ToolError(f"embeddings fallaron: HTTP {resp.status_code}")
    data = resp.json()
    vec = data.get("embedding")
    if not isinstance(vec, list) or not vec:
        raise ToolError("respuesta de embeddings inválida")
    return vec


class MemoryStoreArgs(BaseModel):
    """Guarda un hecho o nota en la memoria persistente de Jarvis."""

    text: str = Field(..., min_length=2, max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=8)


@register("memory_store", MemoryStoreArgs, "Guarda algo en la memoria persistente (entre sesiones).")
async def memory_store(args: MemoryStoreArgs) -> dict[str, int | str]:
    vec = await _embed(args.text)
    async with _db_lock:
        conn = _connect()
        try:
            cur = conn.execute(
                "INSERT INTO memories(ts, text, tags, embedding) VALUES (?,?,?,?)",
                (int(time.time()), args.text, json.dumps(args.tags), _vec_to_blob(vec)),
            )
            conn.commit()
            mem_id = cur.lastrowid
        finally:
            conn.close()
    return {"id": mem_id, "stored": args.text[:100]}


class MemoryRecallArgs(BaseModel):
    """Busca en la memoria persistente con similitud semántica."""

    query: str = Field(..., min_length=2, max_length=300)
    top_k: conint(ge=1, le=10) = 5  # type: ignore[valid-type]


@register("memory_recall", MemoryRecallArgs, "Recupera recuerdos relevantes por similitud semántica.")
async def memory_recall(args: MemoryRecallArgs) -> list[dict[str, str | float]]:
    qvec = await _embed(args.query)
    async with _db_lock:
        conn = _connect()
        try:
            rows = conn.execute("SELECT id, ts, text, tags, embedding FROM memories").fetchall()
        finally:
            conn.close()
    scored: list[tuple[float, dict[str, str | float]]] = []
    for row in rows:
        rid, ts, text, tags, blob = row
        score = _cosine(qvec, _blob_to_vec(blob))
        if score >= MIN_SCORE:
            scored.append(
                (
                    score,
                    {
                        "id": rid,
                        "ts": ts,
                        "text": text,
                        "tags": json.loads(tags) if tags else [],
                        "score": round(score, 3),
                    },
                )
            )
    scored.sort(key=lambda x: -x[0])
    return [item for _, item in scored[: args.top_k]]
