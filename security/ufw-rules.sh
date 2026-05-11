#!/usr/bin/env bash
# Reglas UFW base — ejecutar con sudo
set -euo pipefail

command -v ufw >/dev/null || { echo "ufw no instalado"; exit 1; }

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH con rate-limit (anti-brute)
ufw limit 22/tcp comment 'ssh (rate-limited)'

# mDNS (descubrimiento red local)
ufw allow 5353/udp comment 'mdns'

# KDE Connect / GSConnect (opcional, descomenta si lo usas)
# ufw allow 1714:1764/tcp comment 'kdeconnect'
# ufw allow 1714:1764/udp comment 'kdeconnect'

# Steam / juegos en LAN (opcional)
# ufw allow from 192.168.0.0/16 to any port 27031:27036 comment 'steam in-home streaming'

ufw logging low
ufw --force enable
ufw status verbose
