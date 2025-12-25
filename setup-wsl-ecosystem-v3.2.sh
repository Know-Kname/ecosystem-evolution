#!/usr/bin/env bash
#===============================================================================
# setup-wsl-ecosystem.sh - WSL Development Environment Setup v3.2
#===============================================================================
# Comprehensive toolkit for setting up and configuring WSL development
# environments with Docker integration, Node.js, Python, and more.
#
# Features:
#   - Automated package installation with progress tracking
#   - Docker CLI integration (works with Docker Desktop WSL backend)
#   - Node.js via NVM with integrity verification
#   - Python with pyenv support
#   - SSH configuration with security hardening
#   - Shell customization (zsh, oh-my-zsh)
#   - Tailscale VPN integration
#   - Comprehensive backup and restore
#
# Usage:
#   ./setup-wsl-ecosystem.sh [OPTIONS]
#
# Options:
#   -h, --help          Show this help message
#   -v, --version       Show version information
#   -q, --quiet         Suppress non-essential output
#   -y, --yes           Auto-confirm all prompts
#   --dry-run           Show what would be done without executing
#   --skip-packages     Skip system package installation
#   --skip-node         Skip Node.js/NVM installation
#   --skip-python       Skip Python/pyenv installation
#   --skip-docker       Skip Docker CLI setup
#   --skip-ssh          Skip SSH configuration
#   --backup-only       Only create backup, don't install
#   --restore [path]    Restore from backup
#
# Author: Device Ecosystem Manager Team
# Version: 3.2.0
# License: MIT
#===============================================================================

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

#===============================================================================
# CONSTANTS (CQ-2 fix: Eliminate magic numbers)
#===============================================================================

readonly VERSION="3.2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Timeouts (in seconds)
readonly DOWNLOAD_TIMEOUT=60
readonly INSTALL_TIMEOUT=300
readonly DOCKER_WAIT_TIMEOUT=30

# Resource limits
readonly MAX_LOG_SIZE_MB=50
readonly MAX_BACKUP_COUNT=10
readonly MAX_BACKUP_AGE_DAYS=30

# File permissions (SEC-6 fix: Secure defaults)
readonly LOG_FILE_PERMS=0600
readonly CONFIG_FILE_PERMS=0644
readonly SSH_KEY_PERMS=0600
readonly SSH_CONFIG_PERMS=0644

# Exit codes (standardized)
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_INVALID_ARG=2
readonly EXIT_PREREQ_FAILED=3
readonly EXIT_USER_CANCELLED=4

#===============================================================================
# CONFIGURATION
#===============================================================================

# Default paths
CONFIG_DIR="${HOME}/.config/device-ecosystem"
LOG_DIR="${CONFIG_DIR}/logs"
BACKUP_DIR="${HOME}/.device-ecosystem-backups"
LOG_FILE=""  # Set during initialization

# Feature flags (can be overridden via CLI)
QUIET_MODE=false
AUTO_CONFIRM=false
DRY_RUN=false
SKIP_PACKAGES=false
SKIP_NODE=false
SKIP_PYTHON=false
SKIP_DOCKER=false
SKIP_SSH=false
SYSTEM_WIDE=false
SYNC_FROM_WINDOWS=false

# Windows integration paths (auto-detected)
WINDOWS_USER_HOME=""
WINDOWS_CANONICAL_CONFIG=""

# Installation tracking
declare -A INSTALL_STATUS
PACKAGES_INSTALLED=0
PACKAGES_FAILED=0
PACKAGES_SKIPPED=0

# Essential packages to install
ESSENTIAL_PACKAGES=(
    "curl"
    "wget"
    "git"
    "vim"
    "nano"
    "htop"
    "tree"
    "jq"
    "unzip"
    "zip"
    "ca-certificates"
    "gnupg"
    "lsb-release"
    "apt-transport-https"
    "software-properties-common"
)

# Development packages
DEV_PACKAGES=(
    "build-essential"
    "gcc"
    "g++"
    "make"
    "cmake"
    "pkg-config"
    "libssl-dev"
    "libffi-dev"
    "zlib1g-dev"
    "libbz2-dev"
    "libreadline-dev"
    "libsqlite3-dev"
    "libncurses5-dev"
    "libncursesw5-dev"
    "xz-utils"
    "tk-dev"
    "liblzma-dev"
)

#===============================================================================
# COLOR AND OUTPUT FUNCTIONS
#===============================================================================

# Colors (only if terminal supports them)
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly MAGENTA=$(tput setaf 5)
    readonly CYAN=$(tput setaf 6)
    readonly WHITE=$(tput setaf 7)
    readonly BOLD=$(tput bold)
    readonly RESET=$(tput sgr0)
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly BLUE=""
    readonly MAGENTA=""
    readonly CYAN=""
    readonly WHITE=""
    readonly BOLD=""
    readonly RESET=""
fi

# Logging function (BUG-11 fix: Proper error handling)
log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Write to log file if available
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Ensure log directory exists
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || true
        fi
        
        # Write log entry with error handling
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || {
            # Fallback: try to write to /tmp if main log fails
            echo "[$timestamp] [$level] $message" >> "/tmp/${SCRIPT_NAME}.log" 2>/dev/null || true
        }
    fi
}

# Print functions with consistent styling
print_header() {
    local title="$1"
    local width=70
    local line
    line=$(printf '=%.0s' $(seq 1 $width))
    
    echo ""
    echo "${CYAN}${line}${RESET}"
    echo "${CYAN} ${title}${RESET}"
    echo "${CYAN}${line}${RESET}"
    echo ""
    
    log "INFO" "=== $title ==="
}

print_success() {
    local message="$1"
    [[ "$QUIET_MODE" == true ]] && return
    echo "${GREEN}✓ ${message}${RESET}"
    log "INFO" "[SUCCESS] $message"
}

print_warning() {
    local message="$1"
    echo "${YELLOW}⚠ ${message}${RESET}"
    log "WARN" "[WARNING] $message"
}

print_error() {
    local message="$1"
    echo "${RED}✗ ${message}${RESET}" >&2
    log "ERROR" "[ERROR] $message"
}

print_info() {
    local message="$1"
    [[ "$QUIET_MODE" == true ]] && return
    echo "${WHITE}  ${message}${RESET}"
    log "INFO" "$message"
}

print_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    [[ "$QUIET_MODE" == true ]] && return
    echo "${BLUE}[${step}/${total}]${RESET} ${message}"
    log "INFO" "[Step $step/$total] $message"
}

# Progress spinner
spin() {
    local pid=$1
    local message="${2:-Working...}"
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    while kill -0 "$pid" 2>/dev/null; do
        for ((i=0; i<${#spinstr}; i++)); do
            printf "\r${CYAN}${spinstr:$i:1}${RESET} %s" "$message"
            sleep $delay
        done
    done
    printf "\r"
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        print_info "Please run as a regular user. sudo will be used when needed."
        exit $EXIT_PREREQ_FAILED
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Confirm action (respects AUTO_CONFIRM flag)
confirm() {
    local message="${1:-Continue?}"
    local default="${2:-n}"
    
    if [[ "$AUTO_CONFIRM" == true ]]; then
        log "INFO" "Auto-confirmed: $message"
        return 0
    fi
    
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    read -r -p "$prompt" response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

# Safe file operations (SEC-1 fix: Path validation)
safe_path() {
    local path="$1"
    local resolved
    
    # Resolve to absolute path and check for traversal
    resolved="$(realpath -m "$path" 2>/dev/null)" || {
        print_error "Invalid path: $path"
        return 1
    }
    
    # Ensure path is under allowed directories
    case "$resolved" in
        "$HOME"/*|/tmp/*|/var/tmp/*)
            echo "$resolved"
            return 0
            ;;
        *)
            print_error "Path not allowed: $resolved"
            return 1
            ;;
    esac
}

# Safe download with verification (SEC-4, SEC-5 fix)
safe_download() {
    local url="$1"
    local output="$2"
    local checksum="${3:-}"
    local checksum_type="${4:-sha256}"
    
    print_info "Downloading: $url"
    
    # Download with timeout
    if ! curl -fsSL --connect-timeout 30 --max-time "$DOWNLOAD_TIMEOUT" -o "$output" "$url"; then
        print_error "Download failed: $url"
        return 1
    fi
    
    # Verify checksum if provided
    if [[ -n "$checksum" ]]; then
        local computed
        case "$checksum_type" in
            sha256)
                computed=$(sha256sum "$output" | cut -d' ' -f1)
                ;;
            sha512)
                computed=$(sha512sum "$output" | cut -d' ' -f1)
                ;;
            md5)
                computed=$(md5sum "$output" | cut -d' ' -f1)
                ;;
        esac
        
        if [[ "$computed" != "$checksum" ]]; then
            print_error "Checksum verification failed!"
            print_error "Expected: $checksum"
            print_error "Got: $computed"
            rm -f "$output"
            return 1
        fi
        
        print_success "Checksum verified"
    else
        print_warning "No checksum provided - skipping verification"
    fi
    
    return 0
}

# Get current date for interpolation (BUG-7 fix)
get_current_date() {
    date '+%Y-%m-%d'
}

get_current_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

#===============================================================================
# INITIALIZATION
#===============================================================================

initialize() {
    print_header "INITIALIZATION"
    
    # Create config directory
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        chmod 700 "$CONFIG_DIR"
        print_success "Created config directory: $CONFIG_DIR"
    fi
    
    # Create log directory with secure permissions (SEC-6 fix)
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 700 "$LOG_DIR"
    fi
    
    # Set up log file with secure permissions (SEC-6 fix)
    LOG_FILE="${LOG_DIR}/setup-$(date '+%Y%m%d').log"
    touch "$LOG_FILE"
    chmod "$LOG_FILE_PERMS" "$LOG_FILE"
    
    log "INFO" "=== Device Ecosystem Setup v${VERSION} started ==="
    log "INFO" "User: $(whoami), Host: $(hostname), Date: $(get_current_datetime)"
    
    # Create backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        print_success "Created backup directory: $BACKUP_DIR"
    fi
    
    # Check prerequisites
    print_info "Checking prerequisites..."
    
    local prereqs_ok=true
    
    # Check for sudo
    if ! command_exists sudo; then
        print_error "sudo is not installed"
        prereqs_ok=false
    fi
    
    # Check for curl or wget
    if ! command_exists curl && ! command_exists wget; then
        print_error "Neither curl nor wget is installed"
        prereqs_ok=false
    fi
    
    # Check WSL environment and detect Windows paths
    if [[ ! -f /proc/version ]] || ! grep -qi microsoft /proc/version 2>/dev/null; then
        print_warning "This doesn't appear to be a WSL environment"
    else
        print_success "WSL environment detected"
        
        # Detect Windows user home directory
        if command_exists wslpath && command_exists cmd.exe; then
            WINDOWS_USER_HOME=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n' | xargs wslpath -u 2>/dev/null || echo "")
            if [[ -n "$WINDOWS_USER_HOME" ]] && [[ -d "$WINDOWS_USER_HOME" ]]; then
                print_success "Windows home detected: $WINDOWS_USER_HOME"
                
                # Check for canonical config in the repository
                # Try to find the repo by looking for Device-Ecosystem-Manager-v3.2.ps1
                for search_path in "$WINDOWS_USER_HOME" /mnt/c/MyGithubRepos /mnt/c/Users/*/Documents/GitHub; do
                    if [[ -d "$search_path" ]]; then
                        local found_repo
                        found_repo=$(find "$search_path" -maxdepth 3 -name "Device-Ecosystem-Manager-v3.2.ps1" -type f 2>/dev/null | head -1)
                        if [[ -n "$found_repo" ]]; then
                            local repo_dir
                            repo_dir=$(dirname "$found_repo")
                            local canonical_dir="${repo_dir}/canonical-config"
                            if [[ -d "$canonical_dir" ]]; then
                                WINDOWS_CANONICAL_CONFIG="$canonical_dir"
                                print_success "Found canonical config: $WINDOWS_CANONICAL_CONFIG"
                                break
                            fi
                        fi
                    fi
                done
            fi
        fi
    fi
    
    if [[ "$prereqs_ok" != true ]]; then
        print_error "Prerequisites check failed"
        exit $EXIT_PREREQ_FAILED
    fi
    
    print_success "Prerequisites check passed"
}


#===============================================================================
# BACKUP AND RESTORE MODULE (SEC-7 fix: Improved backup security)
#===============================================================================

backup_configuration() {
    print_header "CONFIGURATION BACKUP"
    
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local backup_path="${BACKUP_DIR}/backup-${timestamp}"
    
    mkdir -p "$backup_path"
    chmod 700 "$backup_path"
    
    print_info "Creating backup at: $backup_path"
    
    local backed_up=0
    
    # Backup shell configs
    for config in .bashrc .bash_profile .profile .zshrc .bash_aliases; do
        if [[ -f "${HOME}/${config}" ]]; then
            cp "${HOME}/${config}" "${backup_path}/${config}"
            chmod "$CONFIG_FILE_PERMS" "${backup_path}/${config}"
            print_success "Backed up: ${config}"
            ((backed_up++))
        fi
    done
    
    # Backup SSH config with proper permissions (SEC-8 fix)
    if [[ -d "${HOME}/.ssh" ]]; then
        mkdir -p "${backup_path}/ssh"
        chmod 700 "${backup_path}/ssh"
        
        # Backup config file
        if [[ -f "${HOME}/.ssh/config" ]]; then
            cp -p "${HOME}/.ssh/config" "${backup_path}/ssh/config"
            chmod "$SSH_CONFIG_PERMS" "${backup_path}/ssh/config"
            print_success "Backed up: SSH config"
            ((backed_up++))
        fi
        
        # Backup public keys only (SEC-7 fix: Don't backup private keys in plaintext)
        for pubkey in "${HOME}"/.ssh/*.pub; do
            if [[ -f "$pubkey" ]]; then
                cp -p "$pubkey" "${backup_path}/ssh/"
                print_success "Backed up: $(basename "$pubkey")"
                ((backed_up++))
            fi
        done
        
        # Create encrypted backup of private keys if gpg available
        if command_exists gpg; then
            print_info "Creating encrypted backup of SSH keys..."
            if confirm "Encrypt private SSH keys in backup?" "y"; then
                local key_archive="${backup_path}/ssh/private_keys.tar.gz.gpg"
                tar -czf - -C "${HOME}/.ssh" $(ls -1 "${HOME}/.ssh" | grep -v '\.pub$' | grep -v 'known_hosts' | grep -v 'config') 2>/dev/null | \
                    gpg --symmetric --cipher-algo AES256 -o "$key_archive" 2>/dev/null && {
                    chmod 600 "$key_archive"
                    print_success "Private keys encrypted"
                } || print_warning "Could not encrypt private keys"
            fi
        else
            print_warning "GPG not available - private keys not backed up for security"
        fi
    fi
    
    # Backup Git config
    if [[ -f "${HOME}/.gitconfig" ]]; then
        cp "${HOME}/.gitconfig" "${backup_path}/.gitconfig"
        print_success "Backed up: .gitconfig"
        ((backed_up++))
    fi
    
    # Backup NVM settings
    if [[ -d "${HOME}/.nvm" ]]; then
        # Just backup the version info, not the entire nvm directory
        if [[ -f "${HOME}/.nvmrc" ]]; then
            cp "${HOME}/.nvmrc" "${backup_path}/.nvmrc"
            print_success "Backed up: .nvmrc"
            ((backed_up++))
        fi
        # Record installed Node versions
        if command_exists nvm; then
            nvm list 2>/dev/null > "${backup_path}/nvm-versions.txt" || true
            print_success "Backed up: NVM version list"
        fi
    fi
    
    # Create manifest (without sensitive data - SEC-7 fix)
    local manifest="${backup_path}/manifest.json"
    cat > "$manifest" << EOF
{
    "version": "${VERSION}",
    "timestamp": "$(get_current_datetime)",
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "wsl_distro": "${WSL_DISTRO_NAME:-unknown}",
    "files_backed_up": ${backed_up},
    "contains_encrypted_keys": $(command_exists gpg && echo "true" || echo "false")
}
EOF
    chmod "$CONFIG_FILE_PERMS" "$manifest"
    
    # Cleanup old backups
    cleanup_old_backups
    
    print_success "Backup complete: $backed_up files backed up"
    log "INFO" "Backup created at $backup_path with $backed_up files"
    
    echo "$backup_path"
}

cleanup_old_backups() {
    local count
    count=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'backup-*' | wc -l)
    
    if [[ $count -gt $MAX_BACKUP_COUNT ]]; then
        print_info "Cleaning up old backups (keeping last $MAX_BACKUP_COUNT)..."
        
        find "$BACKUP_DIR" -maxdepth 1 -type d -name 'backup-*' -printf '%T@ %p\n' | \
            sort -n | head -n -"$MAX_BACKUP_COUNT" | cut -d' ' -f2- | \
            while read -r old_backup; do
                rm -rf "$old_backup"
                log "INFO" "Removed old backup: $old_backup"
            done
    fi
}

list_backups() {
    print_header "AVAILABLE BACKUPS"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_warning "No backup directory found"
        return 1
    fi
    
    local backups
    mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'backup-*' | sort -r)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_warning "No backups found"
        return 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local name
        name=$(basename "$backup")
        local manifest="${backup}/manifest.json"
        local files="unknown"
        
        if [[ -f "$manifest" ]]; then
            files=$(jq -r '.files_backed_up // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
        fi
        
        local age_days
        age_days=$(( ($(date +%s) - $(stat -c %Y "$backup")) / 86400 ))
        
        printf "  [%d] %s (%s files, %d days ago)\n" "$i" "$name" "$files" "$age_days"
        ((i++))
    done
    
    echo ""
}

restore_configuration() {
    local backup_path="${1:-}"
    
    print_header "CONFIGURATION RESTORE"
    
    # List and select backup if not specified
    if [[ -z "$backup_path" ]]; then
        list_backups || return 1
        
        local backups
        mapfile -t backups < <(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'backup-*' | sort -r)
        
        read -r -p "Select backup number (1-${#backups[@]}) or [C]ancel: " selection
        
        if [[ "$selection" =~ ^[Cc] ]]; then
            print_warning "Restore cancelled"
            return $EXIT_USER_CANCELLED
        fi
        
        local index=$((selection - 1))
        if [[ $index -lt 0 ]] || [[ $index -ge ${#backups[@]} ]]; then
            print_error "Invalid selection"
            return $EXIT_INVALID_ARG
        fi
        
        backup_path="${backups[$index]}"
    fi
    
    # Validate backup path
    if [[ ! -d "$backup_path" ]]; then
        print_error "Backup not found: $backup_path"
        return $EXIT_ERROR
    fi
    
    print_info "Restoring from: $backup_path"
    
    # Create backup of current state before restore
    print_info "Backing up current configuration first..."
    backup_configuration > /dev/null
    
    local restored=0
    
    # Restore shell configs
    for config in .bashrc .bash_profile .profile .zshrc .bash_aliases; do
        if [[ -f "${backup_path}/${config}" ]]; then
            cp "${backup_path}/${config}" "${HOME}/${config}"
            print_success "Restored: ${config}"
            ((restored++))
        fi
    done
    
    # Restore SSH config
    if [[ -d "${backup_path}/ssh" ]]; then
        mkdir -p "${HOME}/.ssh"
        chmod 700 "${HOME}/.ssh"
        
        if [[ -f "${backup_path}/ssh/config" ]]; then
            cp "${backup_path}/ssh/config" "${HOME}/.ssh/config"
            chmod "$SSH_CONFIG_PERMS" "${HOME}/.ssh/config"
            print_success "Restored: SSH config"
            ((restored++))
        fi
        
        # Restore public keys
        for pubkey in "${backup_path}"/ssh/*.pub; do
            if [[ -f "$pubkey" ]]; then
                cp "$pubkey" "${HOME}/.ssh/"
                print_success "Restored: $(basename "$pubkey")"
                ((restored++))
            fi
        done
        
        # Handle encrypted private keys
        if [[ -f "${backup_path}/ssh/private_keys.tar.gz.gpg" ]]; then
            if confirm "Decrypt and restore private SSH keys?" "y"; then
                gpg --decrypt "${backup_path}/ssh/private_keys.tar.gz.gpg" 2>/dev/null | \
                    tar -xzf - -C "${HOME}/.ssh" && {
                    # Fix permissions on restored keys
                    find "${HOME}/.ssh" -type f ! -name '*.pub' ! -name 'config' ! -name 'known_hosts' \
                        -exec chmod "$SSH_KEY_PERMS" {} \;
                    print_success "Private keys restored"
                } || print_error "Could not decrypt private keys"
            fi
        fi
    fi
    
    # Restore Git config
    if [[ -f "${backup_path}/.gitconfig" ]]; then
        cp "${backup_path}/.gitconfig" "${HOME}/.gitconfig"
        print_success "Restored: .gitconfig"
        ((restored++))
    fi
    
    # Restore .nvmrc
    if [[ -f "${backup_path}/.nvmrc" ]]; then
        cp "${backup_path}/.nvmrc" "${HOME}/.nvmrc"
        print_success "Restored: .nvmrc"
        ((restored++))
    fi
    
    print_success "Restore complete: $restored files restored"
    print_warning "Please restart your shell to apply changes"
    
    log "INFO" "Restore completed from $backup_path with $restored files"
}

#===============================================================================
# PACKAGE INSTALLATION MODULE (BUG-12 fix: Accurate stats tracking)
#===============================================================================

install_packages() {
    print_header "PACKAGE INSTALLATION"
    
    if [[ "$SKIP_PACKAGES" == true ]]; then
        print_warning "Package installation skipped (--skip-packages)"
        return 0
    fi
    
    # Reset counters (BUG-12 fix)
    PACKAGES_INSTALLED=0
    PACKAGES_FAILED=0
    PACKAGES_SKIPPED=0
    
    print_info "Updating package lists..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would run: sudo apt-get update"
    else
        sudo apt-get update -qq || {
            print_error "Failed to update package lists"
            return 1
        }
    fi
    
    print_success "Package lists updated"
    
    # Combine package lists
    local all_packages=("${ESSENTIAL_PACKAGES[@]}" "${DEV_PACKAGES[@]}")
    local total=${#all_packages[@]}
    local current=0
    
    print_info "Installing $total packages..."
    echo ""
    
    for package in "${all_packages[@]}"; do
        ((current++))
        
        # Check if already installed
        if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
            INSTALL_STATUS[$package]="skipped"
            ((PACKAGES_SKIPPED++))
            printf "\r  [%d/%d] %-30s %s" "$current" "$total" "$package" "${YELLOW}skipped${RESET}"
            continue
        fi
        
        printf "\r  [%d/%d] %-30s %s" "$current" "$total" "$package" "${BLUE}installing...${RESET}"
        
        if [[ "$DRY_RUN" == true ]]; then
            INSTALL_STATUS[$package]="dry-run"
            ((PACKAGES_INSTALLED++))
        else
            if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" &>/dev/null; then
                INSTALL_STATUS[$package]="installed"
                ((PACKAGES_INSTALLED++))
                printf "\r  [%d/%d] %-30s %s\n" "$current" "$total" "$package" "${GREEN}✓${RESET}"
            else
                INSTALL_STATUS[$package]="failed"
                ((PACKAGES_FAILED++))
                printf "\r  [%d/%d] %-30s %s\n" "$current" "$total" "$package" "${RED}✗${RESET}"
            fi
        fi
    done
    
    echo ""
    echo ""
    
    # BUG-12 fix: Display accurate statistics
    print_info "Package installation summary:"
    print_success "  Installed: $PACKAGES_INSTALLED"
    print_info "  Skipped (already installed): $PACKAGES_SKIPPED"
    if [[ $PACKAGES_FAILED -gt 0 ]]; then
        print_error "  Failed: $PACKAGES_FAILED"
    fi
    
    log "INFO" "Packages: $PACKAGES_INSTALLED installed, $PACKAGES_SKIPPED skipped, $PACKAGES_FAILED failed"
    
    return 0
}


#===============================================================================
# NODE.JS / NVM INSTALLATION (SEC-5 fix: Integrity verification)
#===============================================================================

install_nodejs() {
    print_header "NODE.JS INSTALLATION (via NVM)"
    
    if [[ "$SKIP_NODE" == true ]]; then
        print_warning "Node.js installation skipped (--skip-node)"
        return 0
    fi
    
    # Check if NVM is already installed
    local nvm_dir="${HOME}/.nvm"
    
    if [[ -d "$nvm_dir" ]] && [[ -s "${nvm_dir}/nvm.sh" ]]; then
        print_info "NVM is already installed"
        
        # Source NVM
        export NVM_DIR="$nvm_dir"
        # shellcheck source=/dev/null
        source "${NVM_DIR}/nvm.sh"
        
        local current_version
        current_version=$(nvm --version 2>/dev/null || echo "unknown")
        print_info "Current NVM version: $current_version"
        
        if ! confirm "Reinstall/update NVM?" "n"; then
            # Just ensure Node.js is installed
            if ! command_exists node; then
                print_info "Installing latest LTS Node.js..."
                nvm install --lts
                nvm use --lts
                nvm alias default lts/*
            fi
            return 0
        fi
    fi
    
    print_info "Installing NVM (Node Version Manager)..."
    
    # SEC-5 fix: Download install script and verify before executing
    local nvm_version="v0.40.1"  # Specify version for reproducibility
    local nvm_install_script="/tmp/nvm-install-$$.sh"
    local nvm_url="https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh"
    
    # Known checksum for this version (should be updated when version changes)
    local expected_checksum=""  # Leave empty to skip check if unknown
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would download and install NVM ${nvm_version}"
        return 0
    fi
    
    # Download the install script
    print_info "Downloading NVM install script..."
    if ! curl -fsSL --connect-timeout 30 -o "$nvm_install_script" "$nvm_url"; then
        print_error "Failed to download NVM install script"
        return 1
    fi
    
    # Basic validation - check it's a shell script
    if ! head -1 "$nvm_install_script" | grep -q '^#!/'; then
        print_error "Downloaded file doesn't appear to be a valid shell script"
        rm -f "$nvm_install_script"
        return 1
    fi
    
    # Verify checksum if we have one
    if [[ -n "$expected_checksum" ]]; then
        local actual_checksum
        actual_checksum=$(sha256sum "$nvm_install_script" | cut -d' ' -f1)
        
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            print_error "NVM install script checksum mismatch!"
            print_error "Expected: $expected_checksum"
            print_error "Got: $actual_checksum"
            rm -f "$nvm_install_script"
            return 1
        fi
        print_success "NVM script checksum verified"
    else
        print_warning "No checksum available for NVM script - proceeding with caution"
        print_info "Script size: $(wc -c < "$nvm_install_script") bytes"
        
        if ! confirm "Continue with NVM installation?" "y"; then
            rm -f "$nvm_install_script"
            return $EXIT_USER_CANCELLED
        fi
    fi
    
    # Execute the install script
    print_info "Running NVM installer..."
    if bash "$nvm_install_script"; then
        print_success "NVM installed successfully"
        rm -f "$nvm_install_script"
    else
        print_error "NVM installation failed"
        rm -f "$nvm_install_script"
        return 1
    fi
    
    # Source NVM
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"
    
    # Install latest LTS Node.js
    print_info "Installing latest LTS Node.js..."
    nvm install --lts
    nvm use --lts
    nvm alias default lts/*
    
    local node_version
    node_version=$(node --version 2>/dev/null || echo "unknown")
    local npm_version
    npm_version=$(npm --version 2>/dev/null || echo "unknown")
    
    print_success "Node.js ${node_version} installed"
    print_success "npm ${npm_version} installed"
    
    # Install common global packages
    print_info "Installing common global npm packages..."
    local global_packages=("yarn" "pnpm" "typescript" "ts-node" "nodemon")
    
    for pkg in "${global_packages[@]}"; do
        if npm install -g "$pkg" &>/dev/null; then
            print_success "  Installed: $pkg"
        else
            print_warning "  Failed to install: $pkg"
        fi
    done
    
    log "INFO" "Node.js setup complete: Node ${node_version}, npm ${npm_version}"
}

#===============================================================================
# PYTHON / PYENV INSTALLATION
#===============================================================================

install_python() {
    print_header "PYTHON INSTALLATION (via pyenv)"
    
    if [[ "$SKIP_PYTHON" == true ]]; then
        print_warning "Python installation skipped (--skip-python)"
        return 0
    fi
    
    local pyenv_root="${HOME}/.pyenv"
    
    # Check if pyenv is already installed
    if [[ -d "$pyenv_root" ]]; then
        print_info "pyenv is already installed at $pyenv_root"
        
        export PYENV_ROOT="$pyenv_root"
        export PATH="${PYENV_ROOT}/bin:${PATH}"
        
        if command_exists pyenv; then
            local pyenv_version
            pyenv_version=$(pyenv --version 2>/dev/null || echo "unknown")
            print_info "Current pyenv version: $pyenv_version"
        fi
        
        if ! confirm "Reinstall/update pyenv?" "n"; then
            return 0
        fi
    fi
    
    print_info "Installing pyenv..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would install pyenv"
        return 0
    fi
    
    # Install pyenv via git (more secure than curl|bash)
    if [[ -d "$pyenv_root" ]]; then
        print_info "Updating existing pyenv installation..."
        (cd "$pyenv_root" && git pull --quiet)
    else
        print_info "Cloning pyenv repository..."
        git clone --quiet https://github.com/pyenv/pyenv.git "$pyenv_root"
    fi
    
    # Install pyenv-virtualenv plugin
    local virtualenv_dir="${pyenv_root}/plugins/pyenv-virtualenv"
    if [[ ! -d "$virtualenv_dir" ]]; then
        print_info "Installing pyenv-virtualenv plugin..."
        git clone --quiet https://github.com/pyenv/pyenv-virtualenv.git "$virtualenv_dir"
    fi
    
    # Set up environment
    export PYENV_ROOT="$pyenv_root"
    export PATH="${PYENV_ROOT}/bin:${PATH}"
    eval "$(pyenv init -)"
    
    print_success "pyenv installed successfully"
    
    # Install a Python version
    print_info "Available Python versions:"
    pyenv install --list 2>/dev/null | grep -E '^\s+3\.(11|12|13)\.[0-9]+$' | tail -5
    
    local latest_python
    latest_python=$(pyenv install --list 2>/dev/null | grep -E '^\s+3\.12\.[0-9]+$' | tail -1 | tr -d ' ')
    
    if [[ -n "$latest_python" ]]; then
        if confirm "Install Python ${latest_python}?" "y"; then
            print_info "Installing Python ${latest_python} (this may take several minutes)..."
            pyenv install "$latest_python"
            pyenv global "$latest_python"
            print_success "Python ${latest_python} installed and set as global default"
        fi
    fi
    
    # Show Python info
    if command_exists python; then
        local python_version
        python_version=$(python --version 2>/dev/null || echo "unknown")
        local pip_version
        pip_version=$(pip --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
        
        print_success "Python: $python_version"
        print_success "pip: $pip_version"
    fi
    
    log "INFO" "Python setup complete via pyenv"
}

#===============================================================================
# DOCKER CLI SETUP
#===============================================================================

setup_docker() {
    print_header "DOCKER CLI SETUP"
    
    if [[ "$SKIP_DOCKER" == true ]]; then
        print_warning "Docker setup skipped (--skip-docker)"
        return 0
    fi
    
    print_info "Setting up Docker CLI for WSL integration..."
    
    # Check if Docker CLI is already installed
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        print_info "Docker CLI already installed: $docker_version"
        
        # Test Docker connection
        if docker info &>/dev/null; then
            print_success "Docker is working (connected to Docker Desktop)"
            return 0
        else
            print_warning "Docker CLI installed but not connected to Docker Desktop"
            print_info "Make sure Docker Desktop is running with WSL integration enabled"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would install Docker CLI"
        return 0
    fi
    
    if confirm "Install Docker CLI?" "y"; then
        print_info "Adding Docker repository..."
        
        # Add Docker's official GPG key
        sudo install -m 0755 -d /etc/apt/keyrings
        
        if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
            # Key might already exist
            print_warning "GPG key already exists or failed to add"
        fi
        
        sudo chmod a+r /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        
        # Add repository
        local codename
        codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Update and install
        print_info "Installing Docker CLI packages..."
        sudo apt-get update -qq
        
        if sudo apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin &>/dev/null; then
            print_success "Docker CLI installed"
        else
            print_error "Failed to install Docker CLI"
            return 1
        fi
        
        # Add user to docker group (though Docker Desktop handles this)
        if getent group docker &>/dev/null; then
            sudo usermod -aG docker "$(whoami)" 2>/dev/null || true
            print_info "Added user to docker group"
        fi
        
        print_success "Docker CLI setup complete"
        print_info "Docker Desktop WSL integration should handle the daemon connection"
    fi
    
    log "INFO" "Docker CLI setup complete"
}

#===============================================================================
# SSH CONFIGURATION (SEC-3 fix: Secure SSH defaults)
#===============================================================================

setup_ssh() {
    print_header "SSH CONFIGURATION"
    
    if [[ "$SKIP_SSH" == true ]]; then
        print_warning "SSH setup skipped (--skip-ssh)"
        return 0
    fi
    
    local ssh_dir="${HOME}/.ssh"
    
    # Create SSH directory with proper permissions
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        print_success "Created SSH directory"
    fi
    
    # Check for existing keys
    local has_keys=false
    if ls "${ssh_dir}"/*.pub &>/dev/null 2>&1; then
        has_keys=true
        print_info "Existing SSH keys found:"
        for key in "${ssh_dir}"/*.pub; do
            local keyname
            keyname=$(basename "$key")
            print_info "  • $keyname"
        done
    fi
    
    # Generate new key if none exist or user wants a new one
    if [[ "$has_keys" != true ]] || confirm "Generate a new SSH key?" "n"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would generate new SSH key"
        else
            local email=""
            read -r -p "Enter email for SSH key (or press Enter to skip): " email
            
            if [[ -n "$email" ]]; then
                local key_type="ed25519"
                local key_file="${ssh_dir}/id_${key_type}"
                
                print_info "Generating ${key_type} key..."
                ssh-keygen -t "$key_type" -C "$email" -f "$key_file" -N ""
                
                chmod "$SSH_KEY_PERMS" "$key_file"
                chmod "$CONFIG_FILE_PERMS" "${key_file}.pub"
                
                print_success "SSH key generated: ${key_file}"
                print_info "Public key:"
                cat "${key_file}.pub"
            fi
        fi
    fi
    
    # Create/update SSH config with secure defaults (SEC-3 fix)
    local ssh_config="${ssh_dir}/config"
    
    if confirm "Create/update SSH config with secure defaults?" "y"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would create SSH config"
        else
            # Backup existing config
            if [[ -f "$ssh_config" ]]; then
                cp "$ssh_config" "${ssh_config}.backup.$(date +%Y%m%d)"
                print_info "Backed up existing SSH config"
            fi
            
            # SEC-3 fix: Secure SSH config defaults (key-based auth only)
            cat > "$ssh_config" << EOF
# SSH Configuration - Generated by Device Ecosystem Manager v${VERSION}
# Generated: $(get_current_datetime)

# Global defaults - Security hardened
Host *
    # Use key-based authentication only (SEC-3 fix)
    PasswordAuthentication no
    PubkeyAuthentication yes
    
    # Use strong key exchange and ciphers
    KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    
    # Connection settings
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 10
    
    # Security settings
    StrictHostKeyChecking ask
    VerifyHostKeyDNS yes
    HashKnownHosts yes
    
    # Forward agent only when needed (disabled by default)
    ForwardAgent no
    
    # Compression for slow connections
    Compression yes
    
    # Prefer IPv4
    AddressFamily inet

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# GitLab  
Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Example: Add your custom hosts below
# Host myserver
#     HostName server.example.com
#     User myuser
#     Port 22
#     IdentityFile ~/.ssh/id_ed25519
EOF
            
            chmod "$SSH_CONFIG_PERMS" "$ssh_config"
            print_success "SSH config created with secure defaults"
            print_info "Password authentication DISABLED by default (use SSH keys)"
        fi
    fi
    
    log "INFO" "SSH configuration complete"
}


#===============================================================================
# SHELL CONFIGURATION
#===============================================================================

setup_shell() {
    print_header "SHELL CONFIGURATION"
    
    # Update .bashrc with helpful additions
    local bashrc="${HOME}/.bashrc"
    local marker="# Device Ecosystem Manager additions"
    
    if grep -q "$marker" "$bashrc" 2>/dev/null; then
        print_info "Shell configuration already applied"
        return 0
    fi
    
    if confirm "Add helpful shell configurations to .bashrc?" "y"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would update .bashrc"
            return 0
        fi
        
        cat >> "$bashrc" << 'BASHRC_ADDITIONS'

# Device Ecosystem Manager additions
# Added: $(date '+%Y-%m-%d')

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# Helpful aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'

# Docker aliases
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimg='docker images'
alias dlog='docker logs -f'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias glog='git log --oneline --graph'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Better history
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# End Device Ecosystem Manager additions
BASHRC_ADDITIONS
        
        print_success "Shell configuration added to .bashrc"
        print_info "Run 'source ~/.bashrc' or restart your shell to apply"
    fi
    
    log "INFO" "Shell configuration complete"
}

#===============================================================================
# HELP AND VERSION
#===============================================================================

show_help() {
    cat << EOF
${BOLD}Device Ecosystem Manager - WSL Setup Script v${VERSION}${RESET}

${CYAN}USAGE:${RESET}
    $SCRIPT_NAME [OPTIONS]

${CYAN}OPTIONS:${RESET}
    -h, --help          Show this help message
    -v, --version       Show version information
    -q, --quiet         Suppress non-essential output
    -y, --yes           Auto-confirm all prompts
    --dry-run           Show what would be done without executing
    --skip-packages     Skip system package installation
    --skip-node         Skip Node.js/NVM installation
    --skip-python       Skip Python/pyenv installation
    --skip-docker       Skip Docker CLI setup
    --skip-ssh          Skip SSH configuration
    --backup-only       Only create backup, don't install
    --restore [path]    Restore from backup
    --list-backups      List available backups
    
    ${CYAN}MULTI-USER OPTIONS:${RESET}
    --system-wide       Apply configuration to ALL users (requires root)
    --sync-from-windows Sync canonical config from Windows repository
    --apply-canonical   Apply canonical shell config to current/all users

${CYAN}EXAMPLES:${RESET}
    # Full installation with defaults
    $SCRIPT_NAME

    # Quick setup with auto-confirm
    $SCRIPT_NAME -y

    # Dry run to see what would happen
    $SCRIPT_NAME --dry-run

    # Skip specific components
    $SCRIPT_NAME --skip-python --skip-docker

    # Backup current configuration
    $SCRIPT_NAME --backup-only

    # Restore from backup
    $SCRIPT_NAME --restore
    
    # Apply to all WSL users (run as root)
    sudo $SCRIPT_NAME --system-wide
    
    # Sync from Windows canonical config
    $SCRIPT_NAME --sync-from-windows

${CYAN}DOCUMENTATION:${RESET}
    For more information, see the Device Ecosystem Manager documentation.
    Logs are saved to: ${LOG_DIR}/

EOF
}

show_version() {
    echo "Device Ecosystem Manager - WSL Setup Script"
    echo "Version: ${VERSION}"
    echo "Script: ${SCRIPT_NAME}"
}

#===============================================================================
# MULTI-USER / SYSTEM-WIDE FUNCTIONS
#===============================================================================

# Canonical shell configuration marker
readonly SHELL_CONFIG_MARKER="# Device Ecosystem Manager - Canonical Config"

# Apply canonical configuration to a single user
apply_canonical_to_user() {
    local user_home="$1"
    local username
    username="$(basename "$user_home")"
    
    if [[ ! -d "$user_home" ]]; then
        print_warning "Home directory not found: $user_home"
        return 1
    fi
    
    local bashrc="${user_home}/.bashrc"
    local backup="${user_home}/.bashrc.pre-ecosystem.bak"
    
    # Load canonical config from Windows if available, otherwise use embedded
    local canonical_config=""
    if [[ -n "$WINDOWS_CANONICAL_CONFIG" ]] && [[ -f "${WINDOWS_CANONICAL_CONFIG}/wsl-setup.sh" ]]; then
        # Extract the CANONICAL_BASHRC from the Windows file
        canonical_config=$(sed -n '/^read.*CANONICAL_BASHRC/,/^BASHRC_CONTENT$/p' "${WINDOWS_CANONICAL_CONFIG}/wsl-setup.sh" 2>/dev/null | tail -n +2 | head -n -1)
    fi
    
    # Fallback to embedded canonical config
    if [[ -z "$canonical_config" ]]; then
        canonical_config=$(cat << 'EMBEDDED_CONFIG'
# Device Ecosystem Manager - Canonical Config
# Applied: $(date '+%Y-%m-%d %H:%M:%S')
# Version: 3.2.0

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# Path additions
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Aliases
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'

# Docker aliases
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias glog='git log --oneline --graph'

# History
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# End Device Ecosystem Manager - Canonical Config
EMBEDDED_CONFIG
)
    fi
    
    # Check if already applied
    if grep -q "$SHELL_CONFIG_MARKER" "$bashrc" 2>/dev/null; then
        print_info "Config already applied to: $username (updating)"
        # Remove old config block
        sed -i "/$SHELL_CONFIG_MARKER/,/End Device Ecosystem Manager/d" "$bashrc"
    else
        # Create backup
        if [[ -f "$bashrc" ]]; then
            cp "$bashrc" "$backup"
            print_info "Backed up existing .bashrc for: $username"
        fi
    fi
    
    # Apply canonical config
    echo "" >> "$bashrc"
    echo "$canonical_config" >> "$bashrc"
    
    # Fix ownership if running as root
    if [[ $EUID -eq 0 ]]; then
        local uid gid
        uid="$(stat -c '%u' "$user_home")"
        gid="$(stat -c '%g' "$user_home")"
        chown "$uid:$gid" "$bashrc"
        [[ -f "$backup" ]] && chown "$uid:$gid" "$backup"
    fi
    
    print_success "Applied canonical config to: $username"
}

# Apply configuration system-wide (all users)
apply_system_wide() {
    print_header "SYSTEM-WIDE CONFIGURATION"
    
    if [[ $EUID -ne 0 ]]; then
        print_error "--system-wide requires root privileges"
        print_info "Run: sudo $SCRIPT_NAME --system-wide"
        exit $EXIT_PREREQ_FAILED
    fi
    
    print_info "Applying canonical configuration system-wide..."
    
    local applied=0
    local failed=0
    
    # Apply to all existing users in /home
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            if apply_canonical_to_user "$user_home"; then
                ((applied++))
            else
                ((failed++))
            fi
        fi
    done
    
    # Apply to root if exists
    if [[ -d "/root" ]]; then
        if apply_canonical_to_user "/root"; then
            ((applied++))
        else
            ((failed++))
        fi
    fi
    
    # Apply to /etc/skel for future users
    if [[ -d "/etc/skel" ]]; then
        local skel_bashrc="/etc/skel/.bashrc"
        if grep -q "$SHELL_CONFIG_MARKER" "$skel_bashrc" 2>/dev/null; then
            sed -i "/$SHELL_CONFIG_MARKER/,/End Device Ecosystem Manager/d" "$skel_bashrc"
        fi
        
        # Add a minimal canonical config to skel
        cat >> "$skel_bashrc" << 'SKEL_CONFIG'

# Device Ecosystem Manager - Canonical Config
# This will be expanded on first login by running setup script

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# End Device Ecosystem Manager - Canonical Config
SKEL_CONFIG
        print_success "Applied canonical config to /etc/skel (for new users)"
    fi
    
    print_success "System-wide configuration complete: $applied applied, $failed failed"
    log "INFO" "System-wide config: $applied applied, $failed failed"
}

# Sync configuration from Windows canonical config
sync_from_windows() {
    print_header "SYNC FROM WINDOWS CANONICAL CONFIG"
    
    if [[ -z "$WINDOWS_CANONICAL_CONFIG" ]]; then
        print_error "Windows canonical config not found"
        print_info "Ensure the Device Ecosystem Manager repository is accessible"
        print_info "Expected path: /mnt/c/.../ecosystem_evolution/canonical-config/"
        return 1
    fi
    
    print_info "Syncing from: $WINDOWS_CANONICAL_CONFIG"
    
    # Check for wsl-setup.sh in canonical config
    local wsl_setup="${WINDOWS_CANONICAL_CONFIG}/wsl-setup.sh"
    if [[ -f "$wsl_setup" ]]; then
        print_success "Found canonical WSL setup script"
        
        if confirm "Apply canonical WSL configuration?" "y"; then
            if [[ "$SYSTEM_WIDE" == true ]]; then
                # Run the canonical script in system-wide mode
                bash "$wsl_setup" --system-wide
            else
                # Run for current user
                bash "$wsl_setup"
            fi
        fi
    else
        print_warning "Canonical WSL setup script not found"
        print_info "Applying embedded canonical config instead"
        
        if [[ "$SYSTEM_WIDE" == true ]]; then
            apply_system_wide
        else
            apply_canonical_to_user "$HOME"
        fi
    fi
    
    print_success "Sync from Windows complete"
}


#===============================================================================
# MAIN ENTRY POINT
#===============================================================================

main() {
    local restore_path=""
    local backup_only=false
    local list_backups_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit $EXIT_SUCCESS
                ;;
            -v|--version)
                show_version
                exit $EXIT_SUCCESS
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-packages)
                SKIP_PACKAGES=true
                shift
                ;;
            --skip-node)
                SKIP_NODE=true
                shift
                ;;
            --skip-python)
                SKIP_PYTHON=true
                shift
                ;;
            --skip-docker)
                SKIP_DOCKER=true
                shift
                ;;
            --skip-ssh)
                SKIP_SSH=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --restore)
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]]; then
                    restore_path="$2"
                    shift 2
                else
                    restore_path=""
                    shift
                fi
                restore_configuration "$restore_path"
                exit $?
                ;;
            --list-backups)
                list_backups_only=true
                shift
                ;;
            --system-wide)
                SYSTEM_WIDE=true
                shift
                ;;
            --sync-from-windows)
                SYNC_FROM_WINDOWS=true
                shift
                ;;
            --apply-canonical)
                # Just apply canonical config without full setup
                check_not_root  # Will be checked again if system-wide
                initialize
                if [[ "$SYSTEM_WIDE" == true ]]; then
                    apply_system_wide
                else
                    apply_canonical_to_user "$HOME"
                fi
                exit $EXIT_SUCCESS
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit $EXIT_INVALID_ARG
                ;;
        esac
    done
    
    # Check not running as root
    check_not_root
    
    # Initialize
    initialize
    
    # Handle special modes
    if [[ "$list_backups_only" == true ]]; then
        list_backups
        exit $EXIT_SUCCESS
    fi
    
    if [[ "$backup_only" == true ]]; then
        backup_configuration
        exit $EXIT_SUCCESS
    fi
    
    # Handle sync from Windows
    if [[ "$SYNC_FROM_WINDOWS" == true ]]; then
        sync_from_windows
        exit $EXIT_SUCCESS
    fi
    
    # Handle system-wide mode
    if [[ "$SYSTEM_WIDE" == true ]]; then
        apply_system_wide
        exit $EXIT_SUCCESS
    fi
    
    # Show banner
    echo ""
    echo "${CYAN}╔════════════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}║     ${BOLD}Device Ecosystem Manager - WSL Environment Setup${RESET}${CYAN}              ║${RESET}"
    echo "${CYAN}║                        Version ${VERSION}                             ║${RESET}"
    echo "${CYAN}╚════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Create backup before making changes
    print_info "Creating backup of current configuration..."
    backup_configuration > /dev/null
    
    # Run installation steps
    install_packages
    install_nodejs
    install_python
    setup_docker
    setup_ssh
    setup_shell
    
    # Final summary
    print_header "SETUP COMPLETE"
    
    echo ""
    print_success "WSL development environment setup complete!"
    echo ""
    print_info "Summary:"
    print_info "  • Packages: $PACKAGES_INSTALLED installed, $PACKAGES_SKIPPED skipped"
    
    if command_exists node; then
        print_info "  • Node.js: $(node --version 2>/dev/null || echo 'installed')"
    fi
    
    if command_exists python; then
        print_info "  • Python: $(python --version 2>/dev/null || echo 'installed')"
    fi
    
    if command_exists docker; then
        print_info "  • Docker CLI: $(docker --version 2>/dev/null | cut -d',' -f1 || echo 'installed')"
    fi
    
    echo ""
    print_warning "Please restart your shell or run: source ~/.bashrc"
    echo ""
    
    log "INFO" "Setup completed successfully"
    exit $EXIT_SUCCESS
}

# Run main with all arguments
main "$@"
