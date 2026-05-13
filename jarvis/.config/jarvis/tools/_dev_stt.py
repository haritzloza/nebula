#!/usr/bin/env python
"""Captura 5 s del micrófono y los transcribe con faster-whisper.

Uso: python _dev_stt.py [duración_segundos]
"""
from __future__ import annotations

import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16_000
DURATION = float(sys.argv[1]) if len(sys.argv) > 1 else 5.0


def record(seconds: float) -> Path:
    print(f"Grabando {seconds:.1f}s a {SAMPLE_RATE} Hz...")
    audio = sd.rec(int(seconds * SAMPLE_RATE), samplerate=SAMPLE_RATE, channels=1, dtype="int16")
    sd.wait()
    print("Grabación lista.")
    tmp = Path(tempfile.mkstemp(suffix=".wav")[1])
    with wave.open(str(tmp), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(audio.tobytes())
    return tmp


def transcribe(path: Path) -> None:
    from faster_whisper import WhisperModel

    print("Cargando faster-whisper medium (CPU INT8, primera vez tarda)...")
    model = WhisperModel("medium", device="cpu", compute_type="int8")
    segments, info = model.transcribe(str(path), language="es", vad_filter=True)
    print(f"Idioma detectado: {info.language} ({info.language_probability:.0%})")
    for seg in segments:
        print(f"[{seg.start:6.2f} -> {seg.end:6.2f}] {seg.text.strip()}")


def main() -> int:
    try:
        wav = record(DURATION)
        transcribe(wav)
        wav.unlink(missing_ok=True)
        return 0
    except KeyboardInterrupt:
        print("\nCancelado.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
