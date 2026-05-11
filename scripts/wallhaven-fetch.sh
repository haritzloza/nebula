#!/usr/bin/env bash
# wallhaven-fetch.sh — descarga reproducible de wallpapers vía API Wallhaven
#
# Uso:
#   ./wallhaven-fetch.sh [--tag "anime catppuccin"] [--n 30] [--out ~/Pictures/wallpapers/wallhaven]
#
# Variables opcionales:
#   WALLHAVEN_API_KEY  — desbloquea SFW filtros NSFW si tienes cuenta

set -euo pipefail

TAG="${TAG:-catppuccin+anime}"
COUNT="${COUNT:-30}"
OUT="${OUT:-$HOME/Pictures/wallpapers/wallhaven}"
RES="${RES:-2560x1440}"
SORT="${SORT:-favorites}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)  TAG="$2"; shift 2 ;;
        --n)    COUNT="$2"; shift 2 ;;
        --out)  OUT="$2"; shift 2 ;;
        --res)  RES="$2"; shift 2 ;;
        --sort) SORT="$2"; shift 2 ;;
        *)      echo "Arg desconocido: $1"; exit 1 ;;
    esac
done

command -v curl >/dev/null || { echo "curl requerido"; exit 1; }
command -v jq   >/dev/null || { echo "jq requerido";   exit 1; }

mkdir -p "$OUT"

KEY_PARAM=""
[[ -n "${WALLHAVEN_API_KEY:-}" ]] && KEY_PARAM="&apikey=${WALLHAVEN_API_KEY}"

# Construye query: tag URL-encoded, sólo sfw, categoría anime+general, resolución mínima
ENCODED_TAG=$(printf '%s' "$TAG" | sed 's/ /+/g; s/+/%20/g')
URL="https://wallhaven.cc/api/v1/search?q=${ENCODED_TAG}&categories=110&purity=100&atleast=${RES}&sorting=${SORT}${KEY_PARAM}"

echo "→ Consultando $URL"
JSON=$(curl -fsSL "$URL")

URLS=$(echo "$JSON" | jq -r '.data[].path' | head -n "$COUNT")
TOTAL=$(echo "$URLS" | wc -l)
echo "→ Descargando $TOTAL imágenes a $OUT"

i=0
while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    i=$((i+1))
    f="$OUT/$(basename "$u")"
    if [[ -f "$f" ]]; then
        printf '  [%d/%d] %s (ya existe)\n' "$i" "$TOTAL" "$(basename "$u")"
        continue
    fi
    printf '  [%d/%d] %s\n' "$i" "$TOTAL" "$(basename "$u")"
    curl -fsSL -o "$f" "$u"
done <<< "$URLS"

echo "✔ Hecho. $OUT"
