# ~/.zshrc — Haritz (CachyOS + Hyprland)

# History
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=$HOME/.zsh_history
setopt INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

# Comportamiento
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS CORRECT INTERACTIVE_COMMENTS NO_BEEP
bindkey -e

# zinit (gestor de plugins)
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" 2>/dev/null || true
fi
source "${ZINIT_HOME}/zinit.zsh" 2>/dev/null || true

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab

autoload -Uz compinit && compinit -C

# Completion UX
zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'eza --color=always --icons $realpath 2>/dev/null || ls -la $realpath'

# Tools
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"
command -v fzf      >/dev/null && source <(fzf --zsh) 2>/dev/null

# Aliases — generales
alias ll='eza -lah --icons --git'
alias ls='eza --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias lg='lazygit'

# Sysadmin
alias k='k9s'
alias ld='lazydocker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias ports='ss -tulpn'
alias myip='curl -s ifconfig.me; echo'
alias serve='python -m http.server'

# Claude
alias c='claude'
alias cc='claude --continue'
alias cp='~/.config/hypr/scripts/claude-popup.sh'

# CachyOS / pacman
alias up='paru -Syu --noconfirm'
alias upd='checkupdates && paru -Qua'
alias clean='paru -Sc --noconfirm && paru -Rns $(paru -Qtdq) 2>/dev/null || true'
alias mirrors='sudo cachyos-rate-mirrors'

# SSH rápido (lista hosts de ~/.ssh/config)
sshto() {
    local host
    host=$(grep -E '^Host ' ~/.ssh/config 2>/dev/null | awk '{print $2}' | grep -v '\*' | fzf)
    [[ -n "$host" ]] && ssh "$host"
}

# Editor
export EDITOR=nvim
export VISUAL=nvim

# PATH
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Pokémon + sysinfo al abrir una terminal nueva (solo TTY interactiva, no tmux/ssh-pipe)
if [[ $- == *i* && -z "$TMUX" && -z "$VIM" && -z "$ZED_TERM" && -t 1 ]]; then
    if command -v fastfetch >/dev/null; then
        fastfetch
    elif command -v pokemon-colorscripts >/dev/null; then
        pokemon-colorscripts -r --no-title
    fi
fi

# Atajo: nuevo Pokémon en cualquier momento → `pkmn`
alias pkmn='pokemon-colorscripts -r --no-title'
alias pkmnfull='fastfetch'

# Carga local (no versionada)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
