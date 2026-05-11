#!/usr/bin/env bash
# Notifica particiones locales >85% llenas
set -euo pipefail

THRESHOLD=85

df -h --output=target,pcent,source -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | \
    awk 'NR>1 {gsub("%","",$2); if ($2+0 >= '"$THRESHOLD"') print $1"|"$2"|"$3}' | \
while IFS='|' read -r mount pct dev; do
    notify-send -u normal -i drive-harddisk "Disco lleno" \
        "${mount} (${dev}) al ${pct}%" \
        -h "string:x-canonical-private-synchronous:disk-${mount//\//-}"
done
