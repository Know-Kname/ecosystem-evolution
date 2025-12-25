#!/usr/bin/env bash
#===============================================================================
# wsl-setup.sh - WSL User Environment Canonical Setup
#===============================================================================
# This script is the canonical WSL user setup configuration.
# It is applied to all WSL users to ensure uniform environment across:
#   - All users within a single WSL distribution
#   - All WSL distributions on a machine
#   - All machines syncing from this repository
#
# Usage:
#   For current user:  ./wsl-setup.sh
#   For all users:     sudo ./wsl-setup.sh --system-wide
#   From Windows:      wsl -u root -- /path/to/wsl-setup.sh --system-wide
#
# Version: 3.2.0
#===============================================================================

set -o errexit
set -o nounset
set -o pipefail

readonly VERSION="3.2.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Canonical shell configuration additions
readonly SHELL_CONFIG_MARKER="# Device Ecosystem Manager - Canonical Config"

#===============================================================================
# CANONICAL SHELL CONFIGURATION
#===============================================================================

# This is the uniform shell configuration applied to all users
read -r -d '' CANONICAL_BASHRC << 'BASHRC_CONTENT' || true
# Device Ecosystem Manager - Canonical Config
# Applied: {{TIMESTAMP}}
# Version: {{VERSION}}
# DO NOT EDIT - Managed by Device Ecosystem Manager

# ===== Environment Variables =====
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-vim}"
export PAGER="less"
export LESS="-R"

# ===== NVM Configuration =====
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ===== pyenv Configuration =====
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# ===== Path Additions =====
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# ===== Aliases - Navigation =====
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ===== Aliases - Safety =====
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ===== Aliases - Utilities =====
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# ===== Aliases - Docker =====
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dlog='docker logs -f'
alias dexec='docker exec -it'
alias dprune='docker system prune -af'

# ===== Aliases - Git =====
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# ===== History Configuration =====
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
shopt -s histappend

# ===== Shell Options =====
shopt -s checkwinsize
shopt -s cdspell
shopt -s dirspell 2>/dev/null || true
shopt -s globstar 2>/dev/null || true

# ===== Colored Man Pages =====
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# ===== Prompt Customization =====
if [ -n "$BASH_VERSION" ]; then
    # Git branch in prompt
    parse_git_branch() {
        git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
    }
    
    # Colorful prompt with git branch
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(parse_git_branch)\[\033[00m\]\$ '
fi

# End Device Ecosystem Manager - Canonical Config
BASHRC_CONTENT

#===============================================================================
# FUNCTIONS
#===============================================================================

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[OK] $1"
}

log_warning() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Apply canonical config to a single user
apply_to_user() {
    local user_home="$1"
    local username
    username="$(basename "$user_home")"
    
    if [[ ! -d "$user_home" ]]; then
        log_warning "Home directory not found: $user_home"
        return 1
    fi
    
    local bashrc="${user_home}/.bashrc"
    local backup="${user_home}/.bashrc.pre-ecosystem.bak"
    
    # Check if already applied
    if grep -q "$SHELL_CONFIG_MARKER" "$bashrc" 2>/dev/null; then
        log_info "Config already applied to: $username (updating)"
        # Remove old config block
        sed -i "/$SHELL_CONFIG_MARKER/,/End Device Ecosystem Manager/d" "$bashrc"
    else
        # Create backup
        if [[ -f "$bashrc" ]]; then
            cp "$bashrc" "$backup"
            log_info "Backed up existing .bashrc for: $username"
        fi
    fi
    
    # Apply canonical config with timestamp
    local config_with_timestamp
    config_with_timestamp="${CANONICAL_BASHRC//\{\{TIMESTAMP\}\}/$(get_timestamp)}"
    config_with_timestamp="${config_with_timestamp//\{\{VERSION\}\}/$VERSION}"
    
    echo "" >> "$bashrc"
    echo "$config_with_timestamp" >> "$bashrc"
    
    # Fix ownership if running as root
    if [[ $EUID -eq 0 ]]; then
        local uid gid
        uid="$(stat -c '%u' "$user_home")"
        gid="$(stat -c '%g' "$user_home")"
        chown "$uid:$gid" "$bashrc"
        [[ -f "$backup" ]] && chown "$uid:$gid" "$backup"
    fi
    
    log_success "Applied canonical config to: $username"
}

# Apply to /etc/skel for new users
apply_to_skel() {
    local skel_bashrc="/etc/skel/.bashrc"
    
    if [[ ! -d "/etc/skel" ]]; then
        log_warning "/etc/skel not found"
        return 1
    fi
    
    # Check if already applied
    if grep -q "$SHELL_CONFIG_MARKER" "$skel_bashrc" 2>/dev/null; then
        log_info "Config already in /etc/skel (updating)"
        sed -i "/$SHELL_CONFIG_MARKER/,/End Device Ecosystem Manager/d" "$skel_bashrc"
    fi
    
    local config_with_timestamp
    config_with_timestamp="${CANONICAL_BASHRC//\{\{TIMESTAMP\}\}/$(get_timestamp)}"
    config_with_timestamp="${config_with_timestamp//\{\{VERSION\}\}/$VERSION}"
    
    echo "" >> "$skel_bashrc"
    echo "$config_with_timestamp" >> "$skel_bashrc"
    
    log_success "Applied canonical config to /etc/skel (new users)"
}

# System-wide application
apply_system_wide() {
    if [[ $EUID -ne 0 ]]; then
        log_error "--system-wide requires root privileges"
        log_info "Run: sudo $SCRIPT_NAME --system-wide"
        exit 1
    fi
    
    log_info "Applying canonical configuration system-wide..."
    
    # Apply to all existing users
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            apply_to_user "$user_home" || true
        fi
    done
    
    # Apply to root if exists
    if [[ -d "/root" ]]; then
        apply_to_user "/root" || true
    fi
    
    # Apply to /etc/skel for future users
    apply_to_skel
    
    log_success "System-wide configuration complete"
}

# Show help
show_help() {
    cat << EOF
WSL Setup - Canonical Configuration v${VERSION}

Usage: $SCRIPT_NAME [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --version       Show version information
    --system-wide       Apply to all users (requires root)
    --check             Check if canonical config is applied
    --remove            Remove canonical config additions

Examples:
    $SCRIPT_NAME                    # Apply to current user
    sudo $SCRIPT_NAME --system-wide # Apply to all users
    $SCRIPT_NAME --check            # Check current status

EOF
}

# Check if config is applied
check_status() {
    local bashrc="${HOME}/.bashrc"
    
    if grep -q "$SHELL_CONFIG_MARKER" "$bashrc" 2>/dev/null; then
        log_success "Canonical config IS applied to current user"
        # Extract version
        local applied_version
        applied_version=$(grep "Version:" "$bashrc" | head -1 | awk '{print $3}')
        log_info "Applied version: ${applied_version:-unknown}"
        return 0
    else
        log_warning "Canonical config is NOT applied to current user"
        return 1
    fi
}

# Remove canonical config
remove_config() {
    local bashrc="${HOME}/.bashrc"
    local backup="${HOME}/.bashrc.pre-ecosystem.bak"
    
    if ! grep -q "$SHELL_CONFIG_MARKER" "$bashrc" 2>/dev/null; then
        log_info "Canonical config not found - nothing to remove"
        return 0
    fi
    
    sed -i "/$SHELL_CONFIG_MARKER/,/End Device Ecosystem Manager/d" "$bashrc"
    
    # Remove empty lines at end of file
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$bashrc" 2>/dev/null || true
    
    log_success "Removed canonical config from .bashrc"
    
    if [[ -f "$backup" ]]; then
        log_info "Original backup available at: $backup"
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "WSL Setup - Canonical Configuration v${VERSION}"
            exit 0
            ;;
        --system-wide)
            apply_system_wide
            ;;
        --check)
            check_status
            ;;
        --remove)
            remove_config
            ;;
        "")
            # Default: apply to current user
            log_info "Applying canonical configuration to current user..."
            apply_to_user "$HOME"
            log_success "Configuration applied. Run 'source ~/.bashrc' to activate."
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

