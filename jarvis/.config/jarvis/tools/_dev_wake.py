#!/usr/bin/env python
"""Imprime una línea cada vez que detecta el wake word 'hey_jarvis'.

Útil para validar el micro y el threshold antes de integrar todo.
Ctrl-C para salir.
"""
from __future__ import annotations

import queue
import sys
import time

import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16_000
FRAME_SIZE = 1280  # 80 ms a 16 kHz (lo que espera openWakeWord)
THRESHOLD = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5


def main() -> int:
    from openwakeword.model import Model

    print("Cargando modelos openWakeWord (primera vez descarga ONNX)...")
    oww = Model(
        wakeword_models=["hey_jarvis_v0.1"],
        inference_framework="onnx",
    )
    print(f"Threshold: {THRESHOLD}. Di 'hey Jarvis'. Ctrl-C para salir.")

    q: queue.Queue[np.ndarray] = queue.Queue()

    def callback(indata, frames, _t, status):  # type: ignore[no-untyped-def]
        if status:
            print(status, file=sys.stderr)
        q.put(indata.copy())

    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="int16",
        blocksize=FRAME_SIZE,
        callback=callback,
    ):
        while True:
            frame = q.get()
            scores = oww.predict(frame[:, 0])
            for name, score in scores.items():
                if score >= THRESHOLD:
                    ts = time.strftime("%H:%M:%S")
                    print(f"[{ts}] {name}={score:.2f}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nAdiós.")
        sys.exit(0)
