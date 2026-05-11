#!/usr/bin/env bash
# Notifica si la batería baja del 20% (warning) o 10% (critical)
set -euo pipefail

BAT=$(upower -e 2>/dev/null | grep -m1 'BAT' || true)
[[ -z "$BAT" ]] && exit 0   # sin batería (desktop)

INFO=$(upower -i "$BAT")
PERCENT=$(echo "$INFO" | grep -E '^\s*percentage' | awk '{print $2}' | tr -d '%')
STATE=$(echo "$INFO"  | grep -E '^\s*state'      | awk '{print $2}')

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/monitor-battery.state"
LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "100")
echo "$PERCENT" > "$STATE_FILE"

# Solo notificar cruces (no spammear cada tick)
notify() { notify-send -u "$1" -i "$2" "$3" "$4" -h "string:x-canonical-private-synchronous:battery"; }

if [[ "$STATE" == "discharging" ]]; then
    if (( PERCENT <= 10 && LAST > 10 )); then
        notify critical battery-empty "Batería crítica" "${PERCENT}% restante — conecta el cargador"
    elif (( PERCENT <= 20 && LAST > 20 )); then
        notify normal battery-low "Batería baja" "${PERCENT}% restante"
    fi
fi
