# 📅 Profile Collection & Setup Instructions

## Current Status

✅ **chugh** - Collected and synced to GitHub  
❌ **CWH** - Awaiting configuration files  
❌ **Civilian** - Awaiting configuration files  

---

## How to Collect Configurations from Each Profile

### For CWH Profile:

1. **Log in to Windows as CWH user**

2. **Open PowerShell (Run as Administrator)**

3. **Copy configuration files to a collection folder:**
```powershell
# Create a collection folder
New-Item -Path "C:\Users\CWH\ConfigBackup" -ItemType Directory -Force

# Copy .wslconfig
Copy-Item -Path "C:\Users\CWH\.wslconfig" -Destination "C:\Users\CWH\ConfigBackup\.wslconfig" -Force

# Copy Docker configs
Copy-Item -Path "C:\Users\CWH\AppData\Roaming\Docker\daemon.json" -Destination "C:\Users\CWH\ConfigBackup\daemon.json" -Force
Copy-Item -Path "C:\Users\CWH\AppData\Roaming\Docker\config.json" -Destination "C:\Users\CWH\ConfigBackup\config.json" -Force

# Verify files were copied
Get-ChildItem "C:\Users\CWH\ConfigBackup"
```

4. **Upload to this repository** (or share via secure method)

---

### For Civilian Profile:

1. **Log in to Windows as Civilian user**

2. **Open PowerShell (Run as Administrator)**

3. **Copy configuration files to a collection folder:**
```powershell
# Create a collection folder
New-Item -Path "C:\Users\Civilian\ConfigBackup" -ItemType Directory -Force

# Copy .wslconfig
Copy-Item -Path "C:\Users\Civilian\.wslconfig" -Destination "C:\Users\Civilian\ConfigBackup\.wslconfig" -Force

# Copy Docker configs
Copy-Item -Path "C:\Users\Civilian\AppData\Roaming\Docker\daemon.json" -Destination "C:\Users\Civilian\ConfigBackup\daemon.json" -Force
Copy-Item -Path "C:\Users\Civilian\AppData\Roaming\Docker\config.json" -Destination "C:\Users\Civilian\ConfigBackup\config.json" -Force

# Verify files were copied
Get-ChildItem "C:\Users\Civilian\ConfigBackup"
```

4. **Upload to this repository** (or share via secure method)

---

## If Files Don't Exist

If any profile doesn't have the configuration files yet, that's OK:

```powershell
# Check if .wslconfig exists
Test-Path "C:\Users\CWH\.wslconfig"

# Check if Docker configs exist
Test-Path "C:\Users\CWH\AppData\Roaming\Docker\daemon.json"
Test-Path "C:\Users\CWH\AppData\Roaming\Docker\config.json"
```

If they don't exist, they'll be created when we deploy the optimized configurations from this repository.

---

## Once Files Are Uploaded

After you upload the CWH and Civilian configurations, I will:

1. ✅ Compare all three profiles side-by-side
2. ✅ Create a detailed comparison document (PROFILES.md)
3. ✅ Generate profile-specific optimization recommendations
4. ✅ Create golden templates in `templates/` folder
5. ✅ Build automated sync scripts for future updates
6. ✅ Document deployment process in DEPLOYMENT.md

---

## Quick File Locations Reference

| Item | Location |
|------|----------|
| **.wslconfig** | `C:\Users\[USERNAME]\.wslconfig` |
| **daemon.json** | `C:\Users\[USERNAME]\AppData\Roaming\Docker\daemon.json` |
| **config.json** | `C:\Users\[USERNAME]\AppData\Roaming\Docker\config.json` |

---

## Next Steps

1. Collect configs from **CWH** profile using PowerShell script above
2. Collect configs from **Civilian** profile using PowerShell script above
3. Upload both to GitHub repository (in `profiles/CWH/` and `profiles/Civilian/` folders)
4. I will analyze and generate full multi-profile optimization strategy

---

**Ready to proceed?** Upload the configuration files from CWH and Civilian profiles.
