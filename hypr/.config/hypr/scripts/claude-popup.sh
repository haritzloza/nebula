#!/usr/bin/env bash
# claude-popup.sh — pieza central del widget Claude
#
# Flujo:
#   1) rofi -dmenu pide el prompt (con historia persistente)
#   2) claude -p "$PROMPT" en background -> spinner via notify-send (id reutilizable)
#   3) Respuesta: notify-send (corta) + wl-copy (siempre) + opción scratchpad (larga)
#
# Tecla: SUPER+C (ver hypr/conf/keybinds.conf)

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-popup"
HIST="$STATE_DIR/history"
LOG="$STATE_DIR/popup.log"
LAST="$STATE_DIR/last-response.md"
LOCK="$STATE_DIR/lock"
mkdir -p "$STATE_DIR"

ROFI_THEME="$HOME/.config/rofi/themes/claude-prompt.rasi"
SCRATCH_LIMIT=400        # > N chars -> abrir scratchpad con glow
MODEL="${CLAUDE_MODEL:-}"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have claude; then
    notify-send -u critical "Claude" "claude CLI no instalado (paru -S claude-code)"
    exit 1
fi

# Selector: rofi si está, fuzzel si no, ulwgg como fallback
pick_prompt() {
    local rofi_args=(-dmenu -p "Claude" -l 0 -i)
    [[ -f "$ROFI_THEME" ]] && rofi_args+=(-theme "$ROFI_THEME")
    if have rofi; then
        cat "$HIST" 2>/dev/null | rofi "${rofi_args[@]}"
    elif have fuzzel; then
        fuzzel --dmenu --prompt "Claude > "
    else
        zenity --entry --title=Claude --text="Prompt:"
    fi
}

# Lock para evitar dobles invocaciones simultáneas
if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
    notify-send "Claude" "Ya hay una consulta en curso (PID $(cat "$LOCK"))"
    exit 0
fi

PROMPT="$(pick_prompt || true)"
[[ -z "${PROMPT// }" ]] && exit 0

# Histórico (sin duplicados, ultimos 100)
{ echo "$PROMPT"; [[ -f "$HIST" ]] && cat "$HIST"; } | awk '!seen[$0]++' | head -n 100 > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"

echo "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# Notif inicial (id reutilizable para reemplazar)
START_NOTIF=$(notify-send -p -t 0 -i system-search "Claude" "Pensando…  $PROMPT")

# Llamada al CLI
CLAUDE_ARGS=(-p "$PROMPT" --output-format text)
[[ -n "$MODEL" ]] && CLAUDE_ARGS+=(--model "$MODEL")

START_TS=$(date +%s)
if ! RESPONSE="$(claude "${CLAUDE_ARGS[@]}" 2>>"$LOG")"; then
    notify-send -r "$START_NOTIF" -u critical -i dialog-error "Claude" "Falló — ver $LOG"
    exit 1
fi
ELAPSED=$(( $(date +%s) - START_TS ))

# Log
{
    printf '\n=== %s (%ds) ===\n' "$(date -Is)" "$ELAPSED"
    printf 'Q: %s\nA: %s\n' "$PROMPT" "$RESPONSE"
} >> "$LOG"

# Guarda última respuesta para reabrir con SUPER+SHIFT+C si quisieras
printf '# %s\n\n%s\n' "$PROMPT" "$RESPONSE" > "$LAST"

# Portapapeles
if have wl-copy; then
    printf '%s' "$RESPONSE" | wl-copy
fi

LEN=${#RESPONSE}
SUMMARY="${RESPONSE:0:280}"
[[ $LEN -gt 280 ]] && SUMMARY+="…"

if (( LEN > SCRATCH_LIMIT )) && have kitty && have glow; then
    notify-send -r "$START_NOTIF" -i dialog-information "Claude (${ELAPSED}s, ${LEN}c)" "Respuesta larga — abriendo scratchpad. Copiada al portapapeles."
    kitty --class kitty-claude-result -e bash -c "glow -p '$LAST'; read -n1 -s -r -p 'Pulsa una tecla para cerrar…'"
else
    notify-send -r "$START_NOTIF" -t 15000 -i dialog-information "Claude (${ELAPSED}s)" "$SUMMARY"
fi
