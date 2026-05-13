#!/usr/bin/env python
"""Reproduce una frase con la cadena TTS de Jarvis (Piper + DSP opcional).

Uso:
    python _dev_tts.py "Hola, soy Jarvis."
    python _dev_tts.py --raw "Hola, sin DSP"

Lee la config en ~/.config/jarvis/config.toml para aplicar los mismos
efectos que el daemon (sección [tts.dsp]). Útil para iterar valores
sin reiniciar el servicio: edita config.toml y vuelve a llamar.

Espera el modelo en ~/.local/share/piper/voices/es_ES-davefx-medium.onnx
(descárgalo con `jarvisctl fetch-voice`).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    import tomllib  # type: ignore[import-not-found]
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore[no-redef]

# Importar tts_pipeline del directorio padre
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tts_pipeline import DSPParams, speak_blocking  # noqa: E402

DEFAULT_VOICE = Path.home() / ".local/share/piper/voices/es_ES-davefx-medium.onnx"


def main() -> int:
    args = sys.argv[1:]
    use_dsp = True
    if args and args[0] == "--raw":
        use_dsp = False
        args = args[1:]
    if not args:
        print("uso: _dev_tts.py [--raw] 'texto a sintetizar'", file=sys.stderr)
        return 2

    text = " ".join(args)

    # Cargar DSP del config si existe
    cfg_path = Path(
        os.environ.get("JARVIS_CONFIG", Path.home() / ".config/jarvis/config.toml")
    )
    dsp: DSPParams
    voice = DEFAULT_VOICE
    sample_rate = 22050
    if cfg_path.exists():
        with cfg_path.open("rb") as f:
            cfg = tomllib.load(f)
        tts = cfg.get("tts") or {}
        sample_rate = int(tts.get("sample_rate", 22050))
        v = tts.get("voice")
        if v:
            voice = Path(os.path.expandvars(os.path.expanduser(v)))
        dsp = DSPParams.from_config(tts)
    else:
        dsp = DSPParams()

    if not use_dsp:
        dsp = DSPParams(enabled=False)

    return speak_blocking(text, voice, sample_rate, dsp)


if __name__ == "__main__":
    sys.exit(main())
