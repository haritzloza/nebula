#!/usr/bin/env bash
# Estado del daemon Jarvis para Waybar.
# Devuelve JSON: { "text", "tooltip", "class", "alt" }
#
# Lee del socket de estado UNIX una sola línea (snapshot inicial) y la parsea.
# Si el daemon no está, muestra "off".

set -euo pipefail

SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/jarvis.sock"

ICON_OFF=""        # nf-fa-microphone_slash
ICON_IDLE=""       # nf-md-robot_outline
ICON_LISTEN=""     # nf-fa-microphone
ICON_THINK=""      # nf-fa-cog
ICON_SPEAK=""      # nf-md-message_text_outline
ICON_MUTED=""      # nf-fa-microphone_slash

emit() {
    local text="$1" class="$2" tooltip="$3"
    local tip
    tip=$(printf '%s' "$tooltip" | sed 's/"/\\"/g' | tr '\n' ' ')
    printf '{"text":"%b","tooltip":"%s","class":"%s","alt":"%s"}\n' "$text" "$tip" "$class" "$class"
}

if [[ ! -S "$SOCK" ]]; then
    emit "$ICON_OFF" "off" "Jarvis no está corriendo · jarvisctl start"
    exit 0
fi

# Lectura no bloqueante: pedimos snapshot al socket, leemos 1s máximo.
LINE=$(timeout 1 python -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(0.8)
try:
    s.connect(sys.argv[1])
    data = s.recv(4096)
    sys.stdout.write(data.decode("utf-8", "ignore").split("\n",1)[0])
except Exception:
    pass
' "$SOCK" 2>/dev/null || true)

if [[ -z "$LINE" ]]; then
    emit "$ICON_OFF" "off" "Jarvis no responde"
    exit 0
fi

STATE=$(printf '%s' "$LINE" | python -c 'import sys, json; print(json.loads(sys.stdin.read()).get("state","idle"))' 2>/dev/null || echo "idle")
TRANSCRIPT=$(printf '%s' "$LINE" | python -c 'import sys, json; print(json.loads(sys.stdin.read()).get("transcript",""))' 2>/dev/null || echo "")

case "$STATE" in
    listening) emit "$ICON_LISTEN" "listening" "Escuchando…" ;;
    thinking)  emit "$ICON_THINK"  "thinking"  "Pensando: ${TRANSCRIPT}" ;;
    speaking)  emit "$ICON_SPEAK"  "speaking"  "Hablando…" ;;
    muted)     emit "$ICON_MUTED"  "muted"     "Silenciado · SUPER+ALT+J para reactivar" ;;
    *)         emit "$ICON_IDLE"   "idle"      "Idle · di 'Hey Jarvis'" ;;
esac
