#!/usr/bin/env bash
# install.sh — bootstrap interactivo (whiptail) para dotfiles CachyOS + Hyprland
#
# Modos:
#   ./install.sh                      → menú interactivo TUI
#   ./install.sh --auto               → instala perfil "completo" sin preguntar
#   ./install.sh --minimal            → instala perfil "mínimo" sin preguntar
#   ./install.sh --dry-run            → no aplica nada, sólo muestra qué haría
#   ./install.sh --skip-pkgs          → sólo stow (no toca pacman/AUR)
#   ./install.sh --profile=NAME       → carga packages/profiles/NAME.profile

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$DOTFILES_DIR/packages/profiles"
STATE_FILE="$DOTFILES_DIR/.install.state"

ALL_STOW_PACKAGES=(hypr waybar rofi kitty nvim tmux zsh starship swaync claude ssh wlogout fastfetch hyprpaper matugen systemd-user)
DEFAULT_STOW=(hypr waybar rofi kitty zsh starship swaync claude wlogout fastfetch)

DRYRUN=0
SKIP_PKGS=0
PROFILE=""
AUTO=0

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✔ \033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !! \033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m XX \033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [opciones]

  (sin args)         Menú interactivo TUI (whiptail)
  --auto             Perfil "completo" sin preguntar
  --minimal          Perfil "mínimo" sin preguntar
  --profile=NAME     Carga packages/profiles/NAME.profile
  --dry-run          stow -n (no aplica)
  --skip-pkgs        Sólo stow
  -h|--help          Esta ayuda

Perfiles incluidos: minimal, full, custom
EOF
}

for arg in "$@"; do
    case "$arg" in
        --auto)        AUTO=1; PROFILE="full" ;;
        --minimal)     AUTO=1; PROFILE="minimal" ;;
        --profile=*)   AUTO=1; PROFILE="${arg#*=}" ;;
        --dry-run)     DRYRUN=1 ;;
        --skip-pkgs)   SKIP_PKGS=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             err "Argumento desconocido: $arg" ;;
    esac
done

[[ "$(uname -s)" == "Linux" ]] || err "Sólo Linux/CachyOS"
command -v pacman >/dev/null   || err "pacman no encontrado — ¿estás en Arch/CachyOS?"

# ────────────────────────────────────────────────────────────────────────────
# whiptail bootstrap
# ────────────────────────────────────────────────────────────────────────────
ensure_whiptail() {
    if ! command -v whiptail >/dev/null; then
        log "Instalando whiptail (libnewt) para el menú"
        sudo pacman -S --needed --noconfirm libnewt
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Estado por flag (todas las decisiones del usuario)
# ────────────────────────────────────────────────────────────────────────────
declare -A FLAGS=(
    [base]=1
    [hypr]=1
    [waybar]=1
    [theme_dynamic]=0
    [gaming]=0
    [editors_ai]=0
    [dev_extra]=0
    [sysadmin]=0
    [hardening]=0
    [wallpapers]=0
    [sddm]=0
    [monitors]=0
)

declare -a SELECTED_STOW=()

apply_profile() {
    local p="$PROFILE_DIR/$1.profile"
    [[ -f "$p" ]] || err "Perfil no encontrado: $p"
    # shellcheck disable=SC1090
    source "$p"
    log "Perfil cargado: $1"
}

# ────────────────────────────────────────────────────────────────────────────
# Menús TUI
# ────────────────────────────────────────────────────────────────────────────
menu_profile() {
    local choice
    choice=$(whiptail --title "Dotfiles · Haritz" \
        --backtitle "CachyOS + Hyprland" \
        --menu "¿Qué perfil quieres usar?\n\nElige uno o 'Custom' para escoger pieza a pieza." \
        18 78 5 \
        "minimal"  "Solo Hyprland + Waybar + Kitty + Claude widget" \
        "full"     "Todo (gaming + dev + AI + sysadmin + hardening)" \
        "custom"   "Elegir manualmente cada componente" \
        3>&1 1>&2 2>&3) || exit 0
    PROFILE="$choice"
}

menu_custom() {
    local result
    result=$(whiptail --title "Componentes a instalar" \
        --backtitle "Espacio para marcar · Enter para confirmar" \
        --separate-output \
        --checklist "Selecciona componentes:" 24 80 15 \
            "hypr"          "Hyprland + scripts (recomendado)"              ON  \
            "waybar"        "Waybar con widget Claude"                       ON  \
            "theme_dynamic" "Theming dinámico (matugen + swww)"              OFF \
            "gaming"        "Capa gaming (Steam, Lutris, MangoHud)"          OFF \
            "editors_ai"    "Editores AI (VSCode, Cursor, Zed, Claude Desktop)" OFF \
            "dev_extra"     "Dev extra (LazyVim, tmux plugins, lazygit)"     ON  \
            "sysadmin"      "Sysadmin (k9s, lazydocker, sshfs)"              OFF \
            "wallpapers"    "Wallpapers aesthetic (submodule MIT)"           ON  \
            "sddm"          "SDDM Astronaut theme (login bonito)"            OFF \
            "monitors"      "Monitors systemd-user (battery/temp/disk)"      OFF \
            "hardening"     "Hardening (UFW, sshd, sudoers)"                 OFF \
        3>&1 1>&2 2>&3) || exit 0

    # Limpiar selección
    for k in "${!FLAGS[@]}"; do FLAGS[$k]=0; done
    FLAGS[base]=1

    while IFS= read -r item; do
        FLAGS[$item]=1
    done <<< "$result"
}

menu_review() {
    local body=""
    for k in "${!FLAGS[@]}"; do
        local mark="✘"
        [[ "${FLAGS[$k]}" == 1 ]] && mark="✔"
        body+=" $mark  $k\n"
    done
    whiptail --title "Confirmar instalación" \
        --yesno "Resumen:\n\n$body\n¿Continuar?" 24 60 || exit 0
}

# ────────────────────────────────────────────────────────────────────────────
# Aplicación de FLAGS → paquetes pacman/AUR + stow set
# ────────────────────────────────────────────────────────────────────────────
PACMAN_FILES=()
AUR_FILES=()

build_install_set() {
    SELECTED_STOW=()
    PACMAN_FILES+=("$DOTFILES_DIR/packages/pacman.txt")

    [[ ${FLAGS[hypr]}          == 1 ]] && SELECTED_STOW+=(hypr)
    [[ ${FLAGS[waybar]}        == 1 ]] && SELECTED_STOW+=(waybar)
    SELECTED_STOW+=(rofi kitty zsh starship swaync claude wlogout fastfetch)

    if [[ ${FLAGS[theme_dynamic]} == 1 ]]; then
        PACMAN_FILES+=("$DOTFILES_DIR/packages/extra/swww.txt")
        AUR_FILES+=("$DOTFILES_DIR/packages/extra/matugen.txt")
        SELECTED_STOW+=(matugen)
    else
        SELECTED_STOW+=(hyprpaper)
    fi

    if [[ ${FLAGS[gaming]} == 1 ]]; then
        PACMAN_FILES+=("$DOTFILES_DIR/packages/gaming.txt")
        AUR_FILES+=("$DOTFILES_DIR/packages/aur-gaming.txt")
    fi

    if [[ ${FLAGS[editors_ai]} == 1 ]]; then
        AUR_FILES+=("$DOTFILES_DIR/packages/extra/editors-ai.txt")
    fi

    if [[ ${FLAGS[dev_extra]} == 1 ]]; then
        PACMAN_FILES+=("$DOTFILES_DIR/packages/extra/dev.txt")
        SELECTED_STOW+=(nvim tmux)
    fi

    if [[ ${FLAGS[sysadmin]} == 1 ]]; then
        PACMAN_FILES+=("$DOTFILES_DIR/packages/extra/sysadmin.txt")
        AUR_FILES+=("$DOTFILES_DIR/packages/aur.txt")
        SELECTED_STOW+=(ssh)
    fi

    if [[ ${FLAGS[sddm]} == 1 ]]; then
        AUR_FILES+=("$DOTFILES_DIR/packages/extra/sddm.txt")
    fi

    if [[ ${FLAGS[monitors]} == 1 ]]; then
        SELECTED_STOW+=(systemd-user)
        PACMAN_FILES+=("$DOTFILES_DIR/packages/extra/monitors.txt")
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Instaladores
# ────────────────────────────────────────────────────────────────────────────
install_pacman_file() {
    local file="$1"
    [[ -f "$file" ]] || { warn "no existe $file"; return 0; }
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$file")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log "pacman -S desde $(basename "$file") (${#pkgs[@]} paquetes)"
    (( DRYRUN )) && { printf '  %s\n' "${pkgs[@]}"; return 0; }
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

ensure_aur_helper() {
    command -v paru >/dev/null && return 0
    command -v yay  >/dev/null && return 0
    log "Instalando paru (AUR helper)"
    sudo pacman -S --needed --noconfirm base-devel git
    local tmp; tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -si --noconfirm)
    rm -rf "$tmp"
}

install_aur_file() {
    local file="$1"
    [[ -f "$file" ]] || { warn "no existe $file"; return 0; }
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$file")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    ensure_aur_helper
    local helper; helper="$(command -v paru || command -v yay)"
    log "$helper -S desde $(basename "$file") (${#pkgs[@]} paquetes)"
    (( DRYRUN )) && { printf '  %s\n' "${pkgs[@]}"; return 0; }
    "$helper" -S --needed --noconfirm "${pkgs[@]}"
}

ensure_exec_bits() {
    log "chmod +x scripts"
    chmod +x "$DOTFILES_DIR"/hypr/.config/hypr/scripts/*.sh        2>/dev/null || true
    chmod +x "$DOTFILES_DIR"/waybar/.config/waybar/scripts/*.sh    2>/dev/null || true
    chmod +x "$DOTFILES_DIR"/security/*.sh                         2>/dev/null || true
    chmod +x "$DOTFILES_DIR"/scripts/*.sh                          2>/dev/null || true
    chmod +x "$DOTFILES_DIR"/systemd-user/.config/scripts/*.sh     2>/dev/null || true
    chmod +x "$DOTFILES_DIR"/install.sh
}

stow_packages() {
    command -v stow >/dev/null || sudo pacman -S --needed --noconfirm stow
    local flags=(-t "$HOME" -v -R)
    (( DRYRUN )) && flags+=(-n)
    log "stow ${flags[*]} ${SELECTED_STOW[*]}"
    (cd "$DOTFILES_DIR" && stow "${flags[@]}" "${SELECTED_STOW[@]}")
}

ensure_theme_stubs() {
    # Crea stubs vacíos para que los `source`/`@import` de colors.* nunca fallen,
    # esté matugen instalado o no.
    log "Creando stubs de colors.* (matugen overwrites después)"
    (( DRYRUN )) && return 0
    mkdir -p "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/rofi/themes" \
             "$HOME/.config/kitty" "$HOME/.config/swaync"
    : > "$HOME/.config/hypr/colors.conf"
    : > "$HOME/.config/waybar/colors.css"
    : > "$HOME/.config/rofi/themes/colors.rasi"
    : > "$HOME/.config/kitty/colors.conf"
    : > "$HOME/.config/swaync/colors.css"
}

run_matugen_initial() {
    [[ ${FLAGS[theme_dynamic]} == 1 ]] || return 0
    command -v matugen >/dev/null || { warn "matugen no instalado todavía, skip"; return 0; }
    (( DRYRUN )) && return 0
    local pick="$HOME/Pictures/wallpapers"
    [[ -d "$pick" ]] || return 0
    local wp; wp=$(find -L "$pick" -maxdepth 3 -type f \
        \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) | head -1)
    [[ -n "$wp" ]] || return 0
    log "Generando paleta inicial Material You desde $(basename "$wp")"
    matugen image "$wp" --mode dark || warn "matugen falló — revisa el wallpaper"
}

fetch_wallpapers() {
    [[ ${FLAGS[wallpapers]} == 1 ]] || return 0
    local wp_repo="$DOTFILES_DIR/wallpapers/aesthetic"
    if [[ ! -d "$wp_repo/.git" ]]; then
        log "Clonando D3Ext/aesthetic-wallpapers (MIT, ~150MB)"
        (( DRYRUN )) || git clone --depth=1 https://github.com/D3Ext/aesthetic-wallpapers.git "$wp_repo"
    else
        log "Actualizando wallpapers"
        (( DRYRUN )) || (cd "$wp_repo" && git pull --ff-only --quiet)
    fi
    mkdir -p "$HOME/Pictures"
    (( DRYRUN )) || ln -sfn "$wp_repo/images" "$HOME/Pictures/wallpapers"
}

apply_monitors() {
    [[ ${FLAGS[monitors]} == 1 ]] || return 0
    local svc="$DOTFILES_DIR/systemd-user/.config/systemd/user"
    [[ -d "$svc" ]] || return 0
    log "Habilitando monitors systemd-user"
    (( DRYRUN )) && return 0
    mkdir -p "$HOME/.config/systemd/user"
    for unit in "$svc"/*.{service,timer}; do
        [[ -e "$unit" ]] || continue
        systemctl --user enable --now "$(basename "$unit")" 2>/dev/null || true
    done
}

apply_sddm() {
    [[ ${FLAGS[sddm]} == 1 ]] || return 0
    (( DRYRUN )) && { log "[dry] aplicaría SDDM Astronaut"; return 0; }
    local src="$DOTFILES_DIR/sddm/etc/sddm.conf.d"
    [[ -d "$src" ]] || return 0
    log "Aplicando SDDM Astronaut theme"
    sudo mkdir -p /etc/sddm.conf.d
    sudo install -m 0644 "$src"/*.conf /etc/sddm.conf.d/
    sudo systemctl enable sddm.service 2>/dev/null || warn "habilita SDDM manualmente"
    ok "SDDM configurado — verás el theme al reiniciar"
}

apply_hardening() {
    [[ ${FLAGS[hardening]} == 1 ]] || return 0
    local sec="$DOTFILES_DIR/security"
    (( DRYRUN )) && { log "[dry] aplicaría $sec"; return 0; }

    whiptail --title "Hardening" --yesno \
        "Vas a aplicar:\n - ufw (deny incoming, ssh rate-limit)\n - sshd_config endurecido\n - sudoers timeout extendido\n\n¿Continuar?" 14 70 || return 0

    sudo bash "$sec/ufw-rules.sh"
    if [[ -f "$sec/sshd_config.hardened" ]]; then
        sudo cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
        sudo install -m 0644 "$sec/sshd_config.hardened" /etc/ssh/sshd_config
        sudo systemctl reload sshd || warn "sshd no recargado"
    fi
    [[ -f "$sec/sudoers.d/wheel-nopasswd-timeout" ]] && \
        sudo install -m 0440 "$sec/sudoers.d/wheel-nopasswd-timeout" /etc/sudoers.d/wheel-nopasswd-timeout && \
        sudo visudo -c
}

setup_shell() {
    (( DRYRUN )) && return 0
    if [[ "$SHELL" != *zsh ]]; then
        chsh -s "$(command -v zsh)" || warn "chsh falló — cámbialo a mano"
    fi
}

setup_ssh_key() {
    (( DRYRUN )) && return 0
    [[ -f "$HOME/.ssh/id_ed25519" ]] && return 0
    log "Generando clave SSH ed25519"
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$(hostname)-$(whoami)"
}

enable_services() {
    (( DRYRUN )) && return 0
    log "Habilitando servicios base"
    sudo systemctl enable --now NetworkManager bluetooth 2>/dev/null || true
    systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true
}

post_install_summary() {
    cat <<EOF

$(printf '\033[1;32m')╔══════════════════════════════════════════════╗
║          Instalación completa ✔              ║
╚══════════════════════════════════════════════╝$(printf '\033[0m')

  Reinicia la sesión (logout) y entra en Hyprland.

  Atajos clave:
    SUPER + RET          Terminal
    SUPER + C            Claude popup
    SUPER + SHIFT + C    Claude scratchpad
    SUPER + SHIFT + K    Keybind cheatsheet  ← NUEVO
    SUPER + W            Cambiar wallpaper
    SUPER + G            Gamemode visual toggle

  Logs: ~/.local/state/claude-popup/popup.log
  Re-stow: cd $DOTFILES_DIR && stow -R ${SELECTED_STOW[*]}

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────
main() {
    log "Dotfiles dir: $DOTFILES_DIR"

    if (( ! AUTO )); then
        ensure_whiptail
        menu_profile
    fi

    if [[ "$PROFILE" == "custom" ]]; then
        menu_custom
    elif [[ -n "$PROFILE" ]]; then
        apply_profile "$PROFILE"
    fi

    if (( ! AUTO )); then
        menu_review
    fi

    build_install_set
    ensure_exec_bits

    if (( ! SKIP_PKGS )); then
        for f in "${PACMAN_FILES[@]}"; do install_pacman_file "$f"; done
        for f in "${AUR_FILES[@]}";    do install_aur_file    "$f"; done
    fi

    fetch_wallpapers
    ensure_theme_stubs
    stow_packages
    run_matugen_initial

    setup_shell
    setup_ssh_key
    enable_services
    apply_monitors
    apply_sddm
    apply_hardening

    # Persistir estado
    {
        echo "# Última instalación: $(date -Is)"
        echo "PROFILE=$PROFILE"
        for k in "${!FLAGS[@]}"; do echo "FLAG_$k=${FLAGS[$k]}"; done
        echo "STOW=\"${SELECTED_STOW[*]}\""
    } > "$STATE_FILE"

    (( DRYRUN )) || post_install_summary
}

main "$@"
