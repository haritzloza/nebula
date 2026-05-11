#!/usr/bin/env bash
# wallpaper-cycle.sh — cicla wallpapers y regenera paleta Material You (si matugen está)
#
# - Si está swww-daemon → transición animada
# - Si está matugen → regenera colores de Waybar/Rofi/Kitty/Hyprland/Swaync
# - Fallback: hyprpaper estático
#
# Atajo: SUPER+W

set -euo pipefail

WP_DIR="${WALLPAPERS_DIR:-$HOME/Pictures/wallpapers}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper.idx"
mkdir -p "$(dirname "$STATE")"

have() { command -v "$1" >/dev/null 2>&1; }

[[ -d "$WP_DIR" ]] || { notify-send "wallpaper-cycle" "No existe $WP_DIR"; exit 1; }

mapfile -t WALLS < <(find -L "$WP_DIR" -maxdepth 3 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)
[[ ${#WALLS[@]} -gt 0 ]] || { notify-send "wallpaper-cycle" "Sin wallpapers en $WP_DIR"; exit 1; }

# Modo: argumento opcional 'next', 'prev', 'random', o path absoluto
MODE="${1:-next}"

case "$MODE" in
    /*) WP="$MODE" ;;
    random)
        WP="${WALLS[$RANDOM % ${#WALLS[@]}]}"
        ;;
    prev)
        IDX=$(cat "$STATE" 2>/dev/null || echo 0)
        IDX=$(( IDX - 1 ))
        (( IDX < 0 )) && IDX=$(( ${#WALLS[@]} - 1 ))
        echo "$IDX" > "$STATE"
        WP="${WALLS[$IDX]}"
        ;;
    next|*)
        IDX=$(cat "$STATE" 2>/dev/null || echo -1)
        IDX=$(( (IDX + 1) % ${#WALLS[@]} ))
        echo "$IDX" > "$STATE"
        WP="${WALLS[$IDX]}"
        ;;
esac

# Aplicar wallpaper
if have swww && pgrep -x swww-daemon >/dev/null; then
    swww img "$WP" \
        --transition-type any \
        --transition-fps 60 \
        --transition-duration 1.5
elif have swww; then
    swww-daemon &
    sleep 0.5
    swww img "$WP"
elif have hyprctl && pgrep -x hyprpaper >/dev/null; then
    hyprctl hyprpaper preload   "$WP" >/dev/null
    hyprctl hyprpaper wallpaper ",$WP" >/dev/null
    hyprctl hyprpaper unload    unused >/dev/null
fi

# Regenerar paleta Material You
if have matugen; then
    matugen image "$WP" --mode dark 2>/dev/null || true
fi

notify-send -i "$WP" "Wallpaper" "$(basename "$WP")"
