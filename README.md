# Device Ecosystem Manager

Enterprise-grade toolkit for managing WSL2, Docker Desktop, and Windows development environment configuration across all user profiles on a device.

## Overview

This repository contains comprehensive tools for setting up and managing development ecosystems on Windows with WSL2 and Docker Desktop integration.

### Components

- **Device-Ecosystem-Manager-v3.2.ps1** - PowerShell script for Windows-side management
- **setup-wsl-ecosystem-v3.2.sh** - Bash script for WSL-side environment setup

## Features

### Device Ecosystem Manager (PowerShell)

- **Multi-Profile Sync** - Propagate WSL configuration to ALL Windows user profiles
- **Git-Based Config Sync** - Pull canonical configuration from repository
- **Configuration Drift Detection** - Detect when profiles differ from canonical config
- **Scheduled Enforcement** - Automatic hourly drift detection and repair
- Device-wide WSL2 configuration management
- Docker Desktop integration diagnostics and repair
- Comprehensive backup and restore with diff preview
- Health scoring and issue tracking
- Automated repair capabilities

### WSL Ecosystem Setup (Bash)

- **System-Wide Mode** - Apply configuration to all WSL users at once
- **Windows Integration** - Sync canonical config from Windows repository
- Automated package installation with progress tracking
- Docker CLI integration (works with Docker Desktop WSL backend)
- Node.js via NVM with integrity verification
- Python with pyenv support
- SSH configuration with security hardening
- Shell customization
- Comprehensive backup and restore

### Canonical Configuration

The `canonical-config/` directory serves as the **single source of truth** for all machines:

- `wslconfig.ini` - WSL2 configuration template with machine-specific placeholders
- `docker-settings.json` - Docker Desktop settings template
- `wsl-setup.sh` - WSL user environment canonical setup
- `manifest.json` - Version and sync metadata

## Requirements

### Device Ecosystem Manager

- Windows 10 2004+ or Windows 11
- PowerShell 5.1+
- Administrator privileges

### WSL Ecosystem Setup

- WSL2 installed and configured
- Ubuntu or compatible Linux distribution
- Bash shell

## Installation

### Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ecosystem_evolution.git
   cd ecosystem_evolution
   ```

2. **Windows Side Setup:**
   ```powershell
   # Run as Administrator
   .\Device-Ecosystem-Manager-v3.2.ps1
   ```

3. **WSL Side Setup:**
   ```bash
   # From within WSL
   chmod +x setup-wsl-ecosystem-v3.2.sh
   ./setup-wsl-ecosystem-v3.2.sh
   ```

## Usage

### Device Ecosystem Manager

#### Interactive Mode (Default)
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1
```

#### Health Check
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode HealthCheck
```

#### Auto-Fix WSL Issues
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Fix-WSL -AutoFix
```

#### Available Modes
- `Interactive` - Interactive menu mode (default)
- `Inventory` - Display system inventory
- `Fix-WSL` - Repair WSL2 configuration issues
- `Fix-Docker` - Repair Docker Desktop integration
- `Configure-All` - Configure all detected components
- `Backup` - Create backup of configurations
- `Restore` - Restore from backup
- `HealthCheck` - Run health check and display score
- `Verify` - Verify current configuration
- `Version` - Display version information
- `Sync-Profiles` - Sync configuration to all Windows user profiles
- `Sync-Repo` - Pull latest config from git and apply to all profiles
- `Detect-Drift` - Compare all profiles against canonical config
- `Install-Enforcement` - Install scheduled task for automatic enforcement

#### Multi-Profile Sync Examples

```powershell
# Sync WSL config to all user profiles on this machine
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Sync-Profiles

# Pull latest config from git and apply everywhere
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Sync-Repo

# Check for configuration drift across profiles
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Detect-Drift

# Install hourly scheduled enforcement
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Install-Enforcement
```

### WSL Ecosystem Setup

#### Full Installation
```bash
./setup-wsl-ecosystem-v3.2.sh
```

#### Skip Specific Components
```bash
./setup-wsl-ecosystem-v3.2.sh --skip-node --skip-python
```

#### Dry Run
```bash
./setup-wsl-ecosystem-v3.2.sh --dry-run
```

#### Available Options
- `-h, --help` - Show help message
- `-v, --version` - Show version information
- `-q, --quiet` - Suppress non-essential output
- `-y, --yes` - Auto-confirm all prompts
- `--dry-run` - Show what would be done without executing
- `--skip-packages` - Skip system package installation
- `--skip-node` - Skip Node.js/NVM installation
- `--skip-python` - Skip Python/pyenv installation
- `--skip-docker` - Skip Docker CLI setup
- `--skip-ssh` - Skip SSH configuration
- `--backup-only` - Only create backup, don't install
- `--restore [path]` - Restore from backup
- `--system-wide` - Apply configuration to ALL WSL users (requires root)
- `--sync-from-windows` - Sync canonical config from Windows repository
- `--apply-canonical` - Apply canonical shell config only

#### Multi-User Examples

```bash
# Apply configuration to all users in WSL (run as root)
sudo ./setup-wsl-ecosystem-v3.2.sh --system-wide

# Sync from Windows canonical config
./setup-wsl-ecosystem-v3.2.sh --sync-from-windows

# Just apply canonical shell config to current user
./setup-wsl-ecosystem-v3.2.sh --apply-canonical
```

## Version

**Current Version:** 3.2.0

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues, questions, or contributions, please open an issue on GitHub.

## Authors

Device Ecosystem Manager Team

