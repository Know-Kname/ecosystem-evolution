# Docker & WSL2 Multi-Profile Configuration Management

**Repository:** Centralized configuration management for Docker Desktop and WSL2 across three Windows user profiles: `chugh`, `CWH`, and `Civilian`.

---

## 📁 Repository Structure

```
.
├── README.md                          # This file
├── DEPLOYMENT.md                      # Step-by-step deployment guide
├── PROFILES.md                        # Profile comparison & specifications
├── SYNC.md                            # Sync strategy & automation
│
├── profiles/
│   ├── chugh/                         # Development/Primary profile
│   │   ├── .wslconfig
│   │   ├── daemon.json
│   │   └── config.json
│   │
│   ├── CWH/                           # Secondary profile
│   │   ├── .wslconfig
│   │   ├── daemon.json
│   │   └── config.json
│   │
│   └── Civilian/                      # Tertiary/Utility profile
│       ├── .wslconfig
│       ├── daemon.json
│       └── config.json
│
├── templates/
│   ├── .wslconfig.template            # Golden WSL2 template
│   ├── daemon.json.template           # Golden Docker template
│   ├── config.json.template           # Golden CLI config template
│   └── CUSTOMIZATION.md               # How to customize per profile
│
├── scripts/
│   ├── sync-all-profiles.ps1          # PowerShell: Sync configs across profiles
│   ├── backup-configs.ps1             # Backup current configs
│   ├── validate-configs.ps1           # Validate JSON/INI syntax
│   └── apply-configs.md               # Manual application steps
│
└── docs/
    ├── PERFORMANCE.md                 # Performance tuning explained
    ├── TROUBLESHOOTING.md             # Common issues & fixes
    └── CHANGELOG.md                   # Version history & updates
```

---

## 🎯 Quick Start

1. **Review profiles:** See [PROFILES.md](./PROFILES.md) to understand each profile's purpose
2. **Compare configs:** Check [profiles/](./profiles/) folder for current configuration
3. **Deploy:** Follow [DEPLOYMENT.md](./DEPLOYMENT.md) for step-by-step setup
4. **Sync:** Use scripts in [scripts/](./scripts/) to keep configs in sync

---

## 📊 Profile Overview

| Profile | Purpose | Memory | CPUs | Notes |
|---------|---------|--------|------|-------|
| **chugh** | Primary dev/production | 12GB | 6 | Main Eternavue, pentesting |
| **CWH** | Secondary/work | TBD | TBD | To be analyzed |
| **Civilian** | Utility/testing | TBD | TBD | To be analyzed |

*Details to be populated after uploading CWH & Civilian configs*

---

## 🔄 Sync Strategy

- **Golden Template:** `templates/` contains base configurations
- **Profile-Specific Overrides:** Each profile in `profiles/` can deviate for local needs
- **Automation:** `scripts/sync-all-profiles.ps1` pulls latest from main branch
- **Backup:** Always backup before applying changes

---

## 🚀 Key Settings Optimized

✅ WSL2 memory allocation per system specs  
✅ Docker BuildKit enabled (50% faster builds)  
✅ Logging rotation (prevents disk bloat)  
✅ Registry mirrors (faster image pulls)  
✅ Live-restore (zero-downtime restarts)  
✅ Network optimization (mirrored mode on Windows 11)  

---

## 📝 Next Steps

1. Upload configs from **CWH** and **Civilian** profiles
2. Create [PROFILES.md](./PROFILES.md) with detailed comparison
3. Generate profile-specific templates in [templates/](./templates/)
4. Create PowerShell sync scripts for automation
5. Document deployment procedure in [DEPLOYMENT.md](./DEPLOYMENT.md)

---

## 📞 Support

For issues or questions:
- Check [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
- Review [PERFORMANCE.md](./docs/PERFORMANCE.md) for optimization details
- See [scripts/validate-configs.ps1](./scripts/validate-configs.ps1) to validate syntax

---

**Last Updated:** 2025-12-31  
**Status:** 🔴 Awaiting CWH & Civilian profile uploads
