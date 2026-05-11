#!/usr/bin/env bash
# Notifica si temperatura CPU/GPU supera umbrales
set -euo pipefail

WARN=80   # °C
CRIT=90

# CPU vía sensors (lm_sensors)
if command -v sensors >/dev/null; then
    CPU_TEMP=$(sensors 2>/dev/null | awk '/^Tctl:|^Tdie:|^Package id 0:/ {gsub("[+°C]",""); print $2; exit}')
    CPU_TEMP=${CPU_TEMP%.*}
    [[ -n "${CPU_TEMP:-}" && "$CPU_TEMP" =~ ^[0-9]+$ ]] || CPU_TEMP=0

    if (( CPU_TEMP >= CRIT )); then
        notify-send -u critical -i cpu "CPU caliente" "${CPU_TEMP}°C — ¡reduce carga!" \
            -h "string:x-canonical-private-synchronous:temp-cpu"
    elif (( CPU_TEMP >= WARN )); then
        notify-send -u normal -i cpu "CPU temp alta" "${CPU_TEMP}°C" \
            -h "string:x-canonical-private-synchronous:temp-cpu"
    fi
fi

# GPU NVIDIA si está
if command -v nvidia-smi >/dev/null; then
    GPU=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0)
    if (( GPU >= CRIT )); then
        notify-send -u critical -i gpu "GPU caliente" "${GPU}°C" \
            -h "string:x-canonical-private-synchronous:temp-gpu"
    fi
fi
