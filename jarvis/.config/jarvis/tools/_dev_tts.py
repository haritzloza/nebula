#!/usr/bin/env python
"""Reproduce una frase con Piper TTS (es_ES-davefx-medium).

Uso:
    python _dev_tts.py "Hola, soy Jarvis."

Espera el modelo en ~/.local/share/piper/voices/es_ES-davefx-medium.onnx
(descárgalo con el script de instalación de Jarvis o manualmente desde
https://github.com/rhasspy/piper/releases).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

VOICE_DIR = Path.home() / ".local/share/piper/voices"
VOICE_FILE = VOICE_DIR / "es_ES-davefx-medium.onnx"


def main() -> int:
    if len(sys.argv) < 2:
        print("uso: _dev_tts.py 'texto a sintetizar'", file=sys.stderr)
        return 2

    text = " ".join(sys.argv[1:])

    if not shutil.which("piper"):
        print("Error: piper no instalado (paru -S piper-tts-bin)", file=sys.stderr)
        return 1
    if not VOICE_FILE.exists():
        print(f"Error: voz no encontrada en {VOICE_FILE}", file=sys.stderr)
        print("Descárgala con: jarvisctl fetch-voice", file=sys.stderr)
        return 1
    if not shutil.which("pw-cat"):
        print("Error: pw-cat no instalado (pipewire)", file=sys.stderr)
        return 1

    # piper stdout (wav) -> pw-cat stdin
    piper = subprocess.Popen(
        ["piper", "--model", str(VOICE_FILE), "--output-raw"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    player = subprocess.Popen(
        ["pw-cat", "-p", "--format=s16", "--rate=22050", "--channels=1", "-"],
        stdin=piper.stdout,
    )
    assert piper.stdin is not None
    piper.stdin.write(text.encode("utf-8"))
    piper.stdin.close()
    player.wait()
    piper.wait()
    return piper.returncode or player.returncode


if __name__ == "__main__":
    sys.exit(main())
