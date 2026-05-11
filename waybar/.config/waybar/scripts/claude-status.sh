#!/usr/bin/env bash
# Estado del módulo Claude en Waybar.
# Devuelve JSON: { "text", "tooltip", "class", "alt" }
# - "working" si hay un proceso `claude` activo (heurística por nombre de proceso)
# - "idle" si no
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-popup"
LAST="$STATE_DIR/last-response.md"

ICON_IDLE=""     # nf-md-robot_outline (Nerd Font)
ICON_WORK=""     # nf-fa-hourglass

if pgrep -x claude >/dev/null 2>&1; then
    TEXT="$ICON_WORK"
    CLASS="working"
    TOOLTIP="Claude está trabajando…"
else
    TEXT="$ICON_IDLE"
    CLASS="idle"
    if [[ -f "$LAST" ]]; then
        LAST_LINE="$(head -n1 "$LAST" | sed 's/^# //')"
        TOOLTIP="Idle — última: ${LAST_LINE}\nSUPER+C para preguntar"
    else
        TOOLTIP="Ask Claude (SUPER+C)"
    fi
fi

# Escape básico de JSON
TOOLTIP_ESC=$(printf '%s' "$TOOLTIP" | sed 's/"/\\"/g' | tr '\n' ' ')
printf '{"text":"%b","tooltip":"%s","class":"%s","alt":"%s"}\n' "$TEXT" "$TOOLTIP_ESC" "$CLASS" "$CLASS"
