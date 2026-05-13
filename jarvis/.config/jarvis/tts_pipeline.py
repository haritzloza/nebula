"""Cadena de TTS compartida: Piper → (sox DSP) → pw-cat.

Usada por jarvis-daemon, jarvisctl say y _dev_tts.py para que cualquier
ajuste en config.toml afecte a todos por igual.

Diseño:
    - Si sox no está disponible o el bloque [tts.dsp] tiene enabled=false,
      la cadena cae a Piper → pw-cat raw (mismo audio que antes del DSP).
    - Si sox falla en runtime, se loguea y se sigue con audio raw (no rompe).
"""
from __future__ import annotations

import asyncio
import logging
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("jarvis.tts")


@dataclass
class DSPParams:
    """Subset de tts.dsp del config.toml. Valores por defecto = sin DSP."""

    enabled: bool = False
    pitch_cents: int = 0
    tempo: float = 1.0
    eq_low_hz: float = 200.0
    eq_low_gain_db: float = 0.0
    eq_high_hz: float = 7500.0
    eq_high_gain_db: float = 0.0
    compand_attack_decay: str = "0.3,1"
    compand_transfer: str = "6:-70,-60,-20"
    compand_gain_db: float = 0.0
    reverb_mix: int = 0
    reverb_room_scale: int = 50

    @classmethod
    def from_config(cls, tts_section: dict[str, Any]) -> DSPParams:
        dsp = (tts_section or {}).get("dsp") or {}
        if not dsp:
            return cls()
        return cls(
            enabled=bool(dsp.get("enabled", False)),
            pitch_cents=int(dsp.get("pitch_cents", 0)),
            tempo=float(dsp.get("tempo", 1.0)),
            eq_low_hz=float(dsp.get("eq_low_hz", 200.0)),
            eq_low_gain_db=float(dsp.get("eq_low_gain_db", 0.0)),
            eq_high_hz=float(dsp.get("eq_high_hz", 7500.0)),
            eq_high_gain_db=float(dsp.get("eq_high_gain_db", 0.0)),
            compand_attack_decay=str(dsp.get("compand_attack_decay", "0.3,1")),
            compand_transfer=str(dsp.get("compand_transfer", "6:-70,-60,-20")),
            compand_gain_db=float(dsp.get("compand_gain_db", 0.0)),
            reverb_mix=int(dsp.get("reverb_mix", 0)),
            reverb_room_scale=int(dsp.get("reverb_room_scale", 50)),
        )


def build_sox_args(p: DSPParams, sample_rate: int) -> list[str]:
    """Construye los argumentos sox para procesar audio raw s16 mono.

    Pipeline: pitch → tempo → equalizer×2 → compand → reverb.
    Cada efecto solo se añade si su parámetro lo hace efectivo (evita ruido
    sutil por efectos a 0).
    """
    args: list[str] = [
        "sox",
        "-t", "raw", "-r", str(sample_rate), "-e", "signed", "-b", "16", "-c", "1", "-",
        "-t", "raw", "-r", str(sample_rate), "-e", "signed", "-b", "16", "-c", "1", "-",
    ]
    if p.pitch_cents != 0:
        args += ["pitch", str(p.pitch_cents)]
    if abs(p.tempo - 1.0) > 0.001:
        args += ["tempo", f"{p.tempo:.3f}"]
    if abs(p.eq_low_gain_db) > 0.05:
        args += ["equalizer", f"{p.eq_low_hz:.0f}", "1.0q", f"{p.eq_low_gain_db:.2f}"]
    if abs(p.eq_high_gain_db) > 0.05:
        args += ["equalizer", f"{p.eq_high_hz:.0f}", "1.0q", f"{p.eq_high_gain_db:.2f}"]
    if abs(p.compand_gain_db) > 0.05:
        # sox compand attack,decay transfer-fn [gain [initial-volume [delay]]]
        args += [
            "compand",
            p.compand_attack_decay,
            p.compand_transfer,
            f"{p.compand_gain_db:.2f}",
        ]
    if p.reverb_mix > 0:
        # reverb [-w] [reverberance HF-damp room-scale stereo-depth pre-delay wet-gain]
        args += [
            "reverb",
            str(p.reverb_mix),
            "50",
            str(p.reverb_room_scale),
            "50",
            "0",
            "0",
        ]
    return args


def have_sox() -> bool:
    return shutil.which("sox") is not None


async def speak_async(
    text: str,
    voice_path: Path,
    sample_rate: int,
    dsp: Optional[DSPParams] = None,
) -> int:
    """Reproduce `text` por TTS de forma asíncrona. Devuelve returncode final.

    Si `voice_path` no existe → fallback a notify-send (no hay TTS).
    Si `dsp.enabled` y sox disponible → pipeline con DSP.
    Si sox falla en runtime → log + retry sin DSP.
    """
    if not text.strip():
        return 0

    if not voice_path.exists():
        LOG.warning("voz piper no encontrada en %s; fallback notify-send", voice_path)
        proc = await asyncio.create_subprocess_exec(
            "notify-send", "Jarvis", text,
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
        return proc.returncode or 0

    use_dsp = bool(dsp and dsp.enabled and have_sox())
    try:
        return await _run_pipeline(text, voice_path, sample_rate, dsp if use_dsp else None)
    except Exception as e:  # noqa: BLE001
        if use_dsp:
            LOG.warning("DSP falló (%s); reintentando sin sox", e)
            return await _run_pipeline(text, voice_path, sample_rate, None)
        raise


async def _run_pipeline(
    text: str, voice_path: Path, sample_rate: int, dsp: Optional[DSPParams]
) -> int:
    """Lanza piper [-> sox] -> pw-cat encadenados por pipes."""
    piper = await asyncio.create_subprocess_exec(
        "piper", "--model", str(voice_path), "--output-raw",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )

    if dsp is not None:
        sox = await asyncio.create_subprocess_exec(
            *build_sox_args(dsp, sample_rate),
            stdin=piper.stdout,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        player_stdin = sox.stdout
        procs = [piper, sox]
    else:
        player_stdin = piper.stdout
        procs = [piper]

    player = await asyncio.create_subprocess_exec(
        "pw-cat", "-p", "--format=s16", f"--rate={sample_rate}", "--channels=1", "-",
        stdin=player_stdin,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    procs.append(player)

    assert piper.stdin is not None
    piper.stdin.write(text.encode("utf-8"))
    await piper.stdin.drain()
    piper.stdin.close()

    rcs = await asyncio.gather(*(p.wait() for p in procs))
    return next((rc for rc in rcs if rc != 0), 0)


def speak_blocking(
    text: str,
    voice_path: Path,
    sample_rate: int,
    dsp: Optional[DSPParams] = None,
) -> int:
    """Versión bloqueante para CLI (jarvisctl say, _dev_tts.py)."""
    if not text.strip():
        return 0
    if not voice_path.exists():
        subprocess.run(["notify-send", "Jarvis", text], check=False)
        return 0

    use_dsp = bool(dsp and dsp.enabled and have_sox())

    piper = subprocess.Popen(
        ["piper", "--model", str(voice_path), "--output-raw"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    if use_dsp:
        sox = subprocess.Popen(
            build_sox_args(dsp, sample_rate),  # type: ignore[arg-type]
            stdin=piper.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        # Cerrar el handle del padre al stdout de piper para que SIGPIPE funcione
        if piper.stdout is not None:
            piper.stdout.close()
        player_stdin = sox.stdout
        procs = [piper, sox]
    else:
        player_stdin = piper.stdout
        procs = [piper]

    player = subprocess.Popen(
        ["pw-cat", "-p", "--format=s16", f"--rate={sample_rate}", "--channels=1", "-"],
        stdin=player_stdin,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if player_stdin is not None:
        player_stdin.close()
    procs.append(player)

    assert piper.stdin is not None
    piper.stdin.write(text.encode("utf-8"))
    piper.stdin.close()

    rcs = [p.wait() for p in procs]
    return next((rc for rc in rcs if rc != 0), 0)
