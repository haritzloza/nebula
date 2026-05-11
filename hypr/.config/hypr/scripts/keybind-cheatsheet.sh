#!/usr/bin/env bash
# keybind-cheatsheet.sh — popup rofi con todos los keybinds de Hyprland
#
# Parsea ~/.config/hypr/conf/keybinds.conf y muestra:
#   MOD+KEY    Acción humanizada     (ejecutable resultante)
#
# Selecciona uno con Enter para EJECUTARLO directamente.
# Atajo: SUPER+SHIFT+K (ver keybinds.conf)

set -euo pipefail

CONF="$HOME/.config/hypr/conf/keybinds.conf"
ROFI_THEME="$HOME/.config/rofi/themes/cheatsheet.rasi"

[[ -f "$CONF" ]] || { notify-send "Cheatsheet" "No encuentro $CONF"; exit 1; }

# Resolver variables $mod, $term, etc. del propio archivo
declare -A VARS
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\$([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        VARS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
done < "$CONF"

expand_vars() {
    local s="$1"
    for k in "${!VARS[@]}"; do
        s="${s//\$$k/${VARS[$k]}}"
    done
    echo "$s"
}

# Extraer todos los `bind*  = MODS, KEY, ACCION, ARG`
mapfile -t LINES < <(grep -E '^[[:space:]]*bind[elm]*[[:space:]]*=' "$CONF")

ROWS=""
for line in "${LINES[@]}"; do
    rhs="${line#*=}"
    rhs="${rhs## }"
    IFS=',' read -ra parts <<< "$rhs"
    [[ ${#parts[@]} -ge 3 ]] || continue

    mods="${parts[0]## }"; mods="${mods%% }"
    key="${parts[1]## }";  key="${key%% }"
    action="${parts[2]## }"; action="${action%% }"
    arg=""
    [[ ${#parts[@]} -ge 4 ]] && arg=$(IFS=','; echo "${parts[*]:3}")
    arg="${arg## }"; arg="${arg%% }"

    mods=$(expand_vars "$mods")
    arg=$(expand_vars "$arg")
    [[ -z "$mods" ]] && combo="$key" || combo="$mods + $key"

    # Humaniza algunas acciones comunes
    case "$action" in
        exec)             label="$arg" ;;
        workspace)        label="Workspace $arg" ;;
        movetoworkspace)  label="Mover ventana a workspace $arg" ;;
        movefocus)        label="Foco $arg" ;;
        movewindow)       label="Mover ventana $arg" ;;
        killactive)       label="Cerrar ventana" ;;
        togglefloating)   label="Toggle flotante" ;;
        fullscreen)       label="Fullscreen" ;;
        togglesplit)      label="Toggle split" ;;
        pseudo)           label="Pseudo-tile" ;;
        togglespecialworkspace) label="Toggle workspace especial: $arg" ;;
        exit)             label="Salir de Hyprland" ;;
        *)                label="$action${arg:+ $arg}" ;;
    esac

    # Acolchar combo a 30 chars
    printf -v PADDED '%-32s' "$combo"
    ROWS+="$PADDED→  $label"$'\n'
done

# Ordenar por combo
SORTED=$(printf '%s' "$ROWS" | sort -u)

# rofi dmenu con tema cheatsheet (cae a launcher si no existe)
rofi_args=(-dmenu -i -p "" -no-custom -theme-str 'window {width: 60%;}')
[[ -f "$ROFI_THEME" ]] && rofi_args+=(-theme "$ROFI_THEME")

CHOICE=$(printf '%s' "$SORTED" | rofi "${rofi_args[@]}" -mesg "<b>Keybinds Hyprland</b>   ·   ${#LINES[@]} atajos   ·   Enter ejecuta") || exit 0

# Ejecutar la acción seleccionada
[[ -z "$CHOICE" ]] && exit 0
ACTION="${CHOICE#*→  }"
# Heurística: si parece comando ejecutable, lánzalo via hyprctl dispatch exec
if command -v "${ACTION%% *}" >/dev/null 2>&1; then
    hyprctl dispatch exec "$ACTION" >/dev/null
else
    notify-send "Cheatsheet" "$CHOICE"
fi
