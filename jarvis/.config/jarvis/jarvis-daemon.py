#!/usr/bin/env python
"""Jarvis — orquestador asíncrono: wake → STT → Ollama (tools) → TTS.

Arquitectura:
  - Hilo de audio (sounddevice) alimenta una asyncio.Queue.
  - Tarea wake_listener corre openWakeWord sobre frames de 80 ms.
  - Tras detección, captura utterance con VAD y la transcribe (faster-whisper).
  - chat_loop hace /api/chat con tools, ejecuta tool-calls (registry pydantic).
  - Cada chunk de respuesta se sintetiza con piper y se reproduce vía pw-cat.
  - Estado publicado en socket UNIX (lineas JSON) para la UI Quickshell/Waybar.

Sin abstracciones extra: ~400 LoC, dependencias mínimas, sigue la pinta del repo.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
import numpy as np
import sounddevice as sd

try:
    import tomllib  # type: ignore[import-not-found]
except ModuleNotFoundError:  # py < 3.11
    import tomli as tomllib  # type: ignore[no-redef]

# Imports locales (se cargan perezosamente para que --help no requiera deps pesadas)
sys.path.insert(0, str(Path(__file__).parent))
from tools import REGISTRY, ToolError, build_tool_schemas  # noqa: E402
from tts_pipeline import DSPParams, speak_async  # noqa: E402

LOG = logging.getLogger("jarvis")


# ──────────────────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────────────────
def _expand(p: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(p)))


@dataclass
class Config:
    raw: dict[str, Any]

    @classmethod
    def load(cls, path: Path) -> Config:
        with path.open("rb") as f:
            return cls(tomllib.load(f))

    def __getitem__(self, key: str) -> Any:
        return self.raw[key]


# ──────────────────────────────────────────────────────────────────────────
# Estado publicado a la UI
# ──────────────────────────────────────────────────────────────────────────
@dataclass
class State:
    state: str = "idle"  # idle, listening, thinking, speaking, muted, error
    rms: float = 0.0
    transcript: str = ""
    response: str = ""
    muted: bool = False
    error: str = ""

    def snapshot(self) -> dict[str, Any]:
        return {
            "state": "muted" if self.muted else self.state,
            "rms": round(self.rms, 4),
            "transcript": self.transcript,
            "response": self.response,
            "error": self.error,
            "ts": time.time(),
        }


# ──────────────────────────────────────────────────────────────────────────
# Bus de estado (socket UNIX line-delimited JSON)
# ──────────────────────────────────────────────────────────────────────────
class StateBus:
    def __init__(self, socket_path: Path, ui_config: dict[str, Any] | None = None) -> None:
        self.socket_path = socket_path
        self.clients: set[asyncio.StreamWriter] = set()
        self.state = State()
        self._lock = asyncio.Lock()
        # Config UI que se envía al conectar un cliente Quickshell (theme, etc.)
        self.ui_config = ui_config or {}

    async def serve(self) -> None:
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        if self.socket_path.exists():
            self.socket_path.unlink()
        server = await asyncio.start_unix_server(self._on_client, path=str(self.socket_path))
        LOG.info("state bus listening on %s", self.socket_path)
        async with server:
            await server.serve_forever()

    async def _on_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.clients.add(writer)
        try:
            # Snapshot inicial: estado + config para que la UI sepa el tema
            initial = {**self.state.snapshot(), "config": self.ui_config}
            await self._send(writer, initial)
            # Mantener vivo hasta EOF; no leemos nada del cliente
            while not reader.at_eof():
                await reader.read(1024)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            self.clients.discard(writer)
            with contextlib_suppress(Exception):
                writer.close()
                await writer.wait_closed()

    async def update(self, **fields: Any) -> None:
        async with self._lock:
            for k, v in fields.items():
                setattr(self.state, k, v)
            payload = self.state.snapshot()
        await self._broadcast(payload)

    async def _broadcast(self, payload: dict[str, Any]) -> None:
        if not self.clients:
            return
        line = (json.dumps(payload) + "\n").encode("utf-8")
        dead: list[asyncio.StreamWriter] = []
        for w in self.clients:
            try:
                w.write(line)
                await w.drain()
            except Exception:  # noqa: BLE001
                dead.append(w)
        for w in dead:
            self.clients.discard(w)

    @staticmethod
    async def _send(writer: asyncio.StreamWriter, payload: dict[str, Any]) -> None:
        writer.write((json.dumps(payload) + "\n").encode("utf-8"))
        await writer.drain()


class contextlib_suppress:  # micro-impl para no importar contextlib
    def __init__(self, *exc: type[BaseException]) -> None:
        self.exc = exc

    def __enter__(self) -> None:
        return None

    def __exit__(self, et, ev, tb) -> bool:  # type: ignore[no-untyped-def]
        return et is not None and issubclass(et, self.exc)


# ──────────────────────────────────────────────────────────────────────────
# Captura de audio: thread → asyncio.Queue
# ──────────────────────────────────────────────────────────────────────────
class AudioCapture:
    def __init__(self, sample_rate: int, frame_size: int) -> None:
        self.sample_rate = sample_rate
        self.frame_size = frame_size
        self.queue: asyncio.Queue[np.ndarray] = asyncio.Queue(maxsize=50)
        self._loop: asyncio.AbstractEventLoop | None = None
        self.muted = False

    def _callback(self, indata, _frames, _t, _status) -> None:  # type: ignore[no-untyped-def]
        if self.muted or self._loop is None:
            return
        try:
            self._loop.call_soon_threadsafe(self.queue.put_nowait, indata.copy())
        except asyncio.QueueFull:
            pass  # drop frame if backed up

    async def run(self) -> None:
        self._loop = asyncio.get_running_loop()
        with sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype="int16",
            blocksize=self.frame_size,
            callback=self._callback,
        ):
            LOG.info("mic open @ %d Hz, frame=%d", self.sample_rate, self.frame_size)
            while True:
                await asyncio.sleep(3600)


# ──────────────────────────────────────────────────────────────────────────
# Wake word
# ──────────────────────────────────────────────────────────────────────────
class WakeListener:
    def __init__(self, model_name: str, threshold: float) -> None:
        from openwakeword.model import Model

        LOG.info("loading openWakeWord (%s)", model_name)
        self.oww = Model(wakeword_models=[model_name], inference_framework="onnx")
        self.model_name = model_name
        self.threshold = threshold

    async def wait_for_wake(self, audio: AudioCapture, bus: StateBus) -> None:
        await bus.update(state="idle", transcript="", response="")
        while True:
            frame = await audio.queue.get()
            scores = self.oww.predict(frame[:, 0])
            score = max(scores.values())
            # bus rms para mostrar nivel general aunque sea bajo
            rms = float(np.sqrt(np.mean((frame.astype(np.float32) / 32768) ** 2)))
            if score >= self.threshold:
                LOG.info("wake! %s=%.2f", max(scores, key=scores.get), score)  # type: ignore[arg-type]
                await bus.update(state="listening", rms=rms)
                return
            # Sólo publicar rms cada ~10 frames para no saturar el socket
            if int(time.time() * 10) % 5 == 0:
                await bus.update(rms=rms)


# ──────────────────────────────────────────────────────────────────────────
# VAD simple por energía
# ──────────────────────────────────────────────────────────────────────────
async def capture_utterance(
    audio: AudioCapture,
    bus: StateBus,
    sample_rate: int,
    silence_thresh: float,
    silence_dur_s: float,
    max_dur_s: float,
) -> np.ndarray:
    frames: list[np.ndarray] = []
    silence_frames_needed = int(silence_dur_s * sample_rate / audio.frame_size)
    max_frames = int(max_dur_s * sample_rate / audio.frame_size)
    silent_run = 0
    started = False
    deadline = time.time() + max_dur_s + 2

    while len(frames) < max_frames and time.time() < deadline:
        frame = await audio.queue.get()
        f32 = frame.astype(np.float32) / 32768
        rms = float(np.sqrt(np.mean(f32**2)))
        frames.append(frame)
        await bus.update(rms=rms)
        if rms > silence_thresh:
            started = True
            silent_run = 0
        elif started:
            silent_run += 1
            if silent_run >= silence_frames_needed:
                break
        else:
            # Aún no ha empezado; descartar prefijo silencioso
            if len(frames) > silence_frames_needed:
                frames = frames[-silence_frames_needed:]
    if not frames:
        return np.zeros(0, dtype="int16")
    return np.concatenate(frames).flatten()


# ──────────────────────────────────────────────────────────────────────────
# STT
# ──────────────────────────────────────────────────────────────────────────
class Whisper:
    def __init__(self, model: str, device: str, compute_type: str, language: str, vad_filter: bool) -> None:
        from faster_whisper import WhisperModel

        LOG.info("loading faster-whisper %s on %s", model, device)
        self.model = WhisperModel(model, device=device, compute_type=compute_type)
        self.language = language
        self.vad_filter = vad_filter

    async def transcribe(self, pcm_int16: np.ndarray, sample_rate: int) -> str:
        if pcm_int16.size == 0:
            return ""
        audio = pcm_int16.astype(np.float32) / 32768.0
        loop = asyncio.get_running_loop()

        def _run() -> str:
            segments, _info = self.model.transcribe(
                audio,
                language=self.language,
                vad_filter=self.vad_filter,
                beam_size=1,
            )
            return " ".join(seg.text.strip() for seg in segments).strip()

        return await loop.run_in_executor(None, _run)


# ──────────────────────────────────────────────────────────────────────────
# LLM con tool-calling
# ──────────────────────────────────────────────────────────────────────────
@dataclass
class ConversationTurn:
    role: str
    content: str = ""
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    tool_call_id: str = ""
    name: str = ""

    def to_message(self) -> dict[str, Any]:
        msg: dict[str, Any] = {"role": self.role}
        if self.content:
            msg["content"] = self.content
        if self.tool_calls:
            msg["tool_calls"] = self.tool_calls
        if self.tool_call_id:
            msg["tool_call_id"] = self.tool_call_id
        if self.name:
            msg["name"] = self.name
        return msg


class LLMClient:
    def __init__(self, endpoint: str, model: str, temperature: float, keep_alive: str) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.model = model
        self.temperature = temperature
        self.keep_alive = keep_alive
        self.client = httpx.AsyncClient(timeout=120.0)

    async def chat(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> dict[str, Any]:
        resp = await self.client.post(
            f"{self.endpoint}/api/chat",
            json={
                "model": self.model,
                "messages": messages,
                "tools": tools,
                "stream": False,
                "keep_alive": self.keep_alive,
                "options": {"temperature": self.temperature},
            },
        )
        resp.raise_for_status()
        return resp.json()

    async def aclose(self) -> None:
        await self.client.aclose()


async def run_tool_loop(
    llm: LLMClient,
    system_prompt: str,
    user_text: str,
    history: list[ConversationTurn],
    tool_schemas: list[dict[str, Any]],
    audit_log: Path,
) -> str:
    history.append(ConversationTurn(role="user", content=user_text))

    messages: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]
    messages.extend(t.to_message() for t in history)

    max_iters = 6  # safety
    for _ in range(max_iters):
        result = await llm.chat(messages, tool_schemas)
        msg = result.get("message") or {}
        content = msg.get("content", "") or ""
        tool_calls = msg.get("tool_calls") or []

        if tool_calls:
            history.append(
                ConversationTurn(role="assistant", content=content, tool_calls=tool_calls)
            )
            messages.append({"role": "assistant", "content": content, "tool_calls": tool_calls})
            for call in tool_calls:
                fn = (call.get("function") or {}).get("name", "")
                args = (call.get("function") or {}).get("arguments") or {}
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        args = {}
                tool_result = await _invoke_tool(fn, args, audit_log)
                history.append(
                    ConversationTurn(role="tool", content=tool_result, name=fn)
                )
                messages.append({"role": "tool", "content": tool_result, "name": fn})
            continue  # otra ronda para que el modelo redacte la respuesta final

        # Sin tool calls: respuesta definitiva
        history.append(ConversationTurn(role="assistant", content=content))
        return content.strip()

    return "Lo siento, me he liado entre herramientas. ¿Lo repetimos?"


async def _invoke_tool(name: str, args: dict[str, Any], audit_log: Path) -> str:
    entry = REGISTRY.get(name)
    ts = datetime.now().isoformat(timespec="seconds")
    if entry is None:
        result = json.dumps({"error": f"tool '{name}' not allowed"})
        _audit(audit_log, ts, name, args, result)
        return result
    try:
        validated = entry.schema(**args)
        out = await entry.run(validated)
        result = json.dumps({"ok": True, "result": out}, ensure_ascii=False, default=str)
    except ToolError as e:
        result = json.dumps({"error": str(e)})
    except Exception as e:  # noqa: BLE001
        result = json.dumps({"error": f"{type(e).__name__}: {e}"})
    _audit(audit_log, ts, name, args, result)
    return result


def _audit(path: Path, ts: str, name: str, args: dict[str, Any], result: str) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(f"{ts} {name} args={json.dumps(args, ensure_ascii=False)} -> {result}\n")
    except OSError:
        pass


# ──────────────────────────────────────────────────────────────────────────
# TTS  (la cadena real vive en tts_pipeline.py para que jarvisctl say y los
# scripts _dev_*.py usen exactamente el mismo procesado)
# ──────────────────────────────────────────────────────────────────────────
async def speak(text: str, voice_path: Path, sample_rate: int, dsp: DSPParams) -> None:
    await speak_async(text, voice_path, sample_rate, dsp)


# ──────────────────────────────────────────────────────────────────────────
# Control socket (jarvisctl ↔ daemon): comandos como mute, ptt, ask
# ──────────────────────────────────────────────────────────────────────────
class ControlChannel:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.commands: asyncio.Queue[dict[str, Any]] = asyncio.Queue()

    async def serve(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.exists():
            self.path.unlink()
        server = await asyncio.start_unix_server(self._on_client, path=str(self.path))
        LOG.info("control channel on %s", self.path)
        async with server:
            await server.serve_forever()

    async def _on_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            data = await reader.readline()
            cmd = json.loads(data.decode("utf-8")) if data else {}
            await self.commands.put(cmd)
            writer.write(b'{"ok":true}\n')
            await writer.drain()
        except Exception as e:  # noqa: BLE001
            writer.write(json.dumps({"ok": False, "error": str(e)}).encode() + b"\n")
        finally:
            writer.close()
            await writer.wait_closed()


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────
async def amain(config_path: Path) -> int:
    cfg = Config.load(config_path)

    state_dir = _expand(cfg["paths"]["state_dir"])
    state_dir.mkdir(parents=True, exist_ok=True)
    audit_log = _expand(cfg["paths"]["audit_log"])

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[
            logging.StreamHandler(sys.stderr),
            logging.FileHandler(_expand(cfg["paths"]["session_log"])),
        ],
    )

    socket_path = _expand(cfg["ui"]["socket"])
    control_path = socket_path.with_name("jarvis-ctl.sock")
    ui_cfg = {
        "theme": cfg["ui"].get("theme", "minimal"),
        "always_visible": bool(cfg["ui"].get("always_visible", False)),
    }
    bus = StateBus(socket_path, ui_config=ui_cfg)
    ctl = ControlChannel(control_path)

    audio = AudioCapture(cfg["capture"]["sample_rate"], cfg["capture"]["frame_size"])
    wake = WakeListener(cfg["wake"]["model"], cfg["wake"]["threshold"])
    stt = Whisper(
        cfg["stt"]["model"],
        cfg["stt"]["device"],
        cfg["stt"]["compute_type"],
        cfg["stt"]["language"],
        cfg["stt"]["vad_filter"],
    )
    llm = LLMClient(
        cfg["llm"]["endpoint"], cfg["llm"]["model"], cfg["llm"]["temperature"], cfg["llm"]["keep_alive"]
    )
    voice = _expand(cfg["tts"]["voice"])
    dsp = DSPParams.from_config(cfg["tts"])

    prompt_path = Path(__file__).parent / "prompts" / "system.md"
    system_template = prompt_path.read_text(encoding="utf-8")

    tool_schemas = build_tool_schemas(cfg)
    history: list[ConversationTurn] = []

    # Bus & control en background
    bus_task = asyncio.create_task(bus.serve())
    ctl_task = asyncio.create_task(ctl.serve())
    audio_task = asyncio.create_task(audio.run())

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    LOG.info("jarvis daemon ready")

    async def process_user_input(text: str) -> None:
        await bus.update(state="thinking", transcript=text)
        now = datetime.now()
        system_prompt = system_template.format(
            now=now.strftime("%H:%M"), weekday=now.strftime("%A")
        )
        response = await run_tool_loop(
            llm, system_prompt, text, history, tool_schemas, audit_log
        )
        await bus.update(state="speaking", response=response)
        if cfg["wake"]["mute_on_speak"]:
            audio.muted = True
        try:
            await speak(response, voice, cfg["tts"]["sample_rate"], dsp)
        finally:
            audio.muted = False
        # acota historia (últimos 12 turnos)
        if len(history) > 24:
            del history[:-24]

    async def main_loop() -> None:
        while not stop.is_set():
            # Comprueba comandos de control sin bloquear el wake-listener largo rato
            try:
                cmd = ctl.commands.get_nowait()
            except asyncio.QueueEmpty:
                cmd = None
            if cmd:
                action = cmd.get("action")
                if action == "toggle_listen":
                    audio.muted = not audio.muted
                    await bus.update(muted=audio.muted)
                elif action == "ptt":
                    await bus.update(state="listening")
                    utt = await capture_utterance(
                        audio,
                        bus,
                        cfg["capture"]["sample_rate"],
                        cfg["capture"]["silence_threshold"],
                        cfg["capture"]["silence_duration_s"],
                        cfg["capture"]["max_utterance_s"],
                    )
                    text = await stt.transcribe(utt, cfg["capture"]["sample_rate"])
                    if text:
                        await process_user_input(text)
                    await bus.update(state="idle")
                    continue
                elif action == "ask":
                    text = cmd.get("text", "").strip()
                    if text:
                        await process_user_input(text)
                    await bus.update(state="idle")
                    continue

            if audio.muted:
                await asyncio.sleep(0.2)
                continue

            await wake.wait_for_wake(audio, bus)
            utt = await capture_utterance(
                audio,
                bus,
                cfg["capture"]["sample_rate"],
                cfg["capture"]["silence_threshold"],
                cfg["capture"]["silence_duration_s"],
                cfg["capture"]["max_utterance_s"],
            )
            text = await stt.transcribe(utt, cfg["capture"]["sample_rate"])
            if text:
                LOG.info("user: %s", text)
                await process_user_input(text)
            await bus.update(state="idle", transcript="", response="")

    main_task = asyncio.create_task(main_loop())

    await stop.wait()
    LOG.info("stopping")
    for t in (main_task, bus_task, ctl_task, audio_task):
        t.cancel()
    await llm.aclose()
    return 0


def main() -> int:
    cfg = os.environ.get("JARVIS_CONFIG") or str(Path(__file__).parent / "config.toml")
    return asyncio.run(amain(Path(cfg)))


if __name__ == "__main__":
    sys.exit(main())
