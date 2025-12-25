# Quick Start Guide - Device Ecosystem Manager

## 🚀 Fastest Way to Run

### Option 1: Double-click the Launcher (Recommended)
1. Double-click `Launch-DeviceEcosystemManager.bat`
2. Click "Yes" on the UAC prompt
3. Done! The manager will open with admin privileges

### Option 2: PowerShell Launcher
1. Right-click `Launch-DeviceEcosystemManager.ps1`
2. Select "Run with PowerShell"
3. Click "Yes" on the UAC prompt

### Option 3: Manual PowerShell (Advanced)
1. Right-click PowerShell icon → "Run as Administrator"
2. Navigate to the directory:
   ```powershell
   cd C:\Users\CWH\ecosystem-evolution
   ```
3. Run the script:
   ```powershell
   .\Device-Ecosystem-Manager-v3.2.ps1
   ```

---

## 📌 Create a Desktop Shortcut

### For the Batch Launcher:
1. Right-click `Launch-DeviceEcosystemManager.bat`
2. Select "Send to" → "Desktop (create shortcut)"
3. Rename the shortcut to "Device Ecosystem Manager"
4. (Optional) Right-click shortcut → Properties → Change Icon

### For Direct PowerShell Access:
1. Right-click on Desktop → New → Shortcut
2. Enter this location:
   ```
   powershell.exe -ExecutionPolicy Bypass -File "C:\Users\CWH\ecosystem-evolution\Device-Ecosystem-Manager-v3.2.ps1"
   ```
3. Name it "Device Ecosystem Manager"
4. Right-click the shortcut → Properties → Advanced → Check "Run as administrator"

---

## 🎯 What Each File Does

| File | Purpose |
|------|---------|
| `Device-Ecosystem-Manager-v3.2.ps1` | Main PowerShell script (requires admin) |
| `Launch-DeviceEcosystemManager.bat` | Windows batch launcher (auto-elevates) |
| `Launch-DeviceEcosystemManager.ps1` | PowerShell launcher (auto-elevates) |
| `Sync-EcosystemConfig.ps1` | Scheduled sync script for Task Scheduler |
| `setup-wsl-ecosystem-v3.2.sh` | WSL/Ubuntu setup script |

---

## ✅ First Run Checklist

After launching for the first time:

1. **System Inventory**: Choose option `[1]` to see your system status
2. **Health Check**: Review WSL2 and Docker configuration
3. **Sync to All Profiles**: Choose option `[5]` to apply config to all users
4. **Install Enforcement**: Choose option `[8]` to schedule hourly checks

---

## 🔧 Common Tasks

### Apply Configuration to All User Profiles
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Sync-Profiles
```

### Check for Configuration Drift
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Detect-Drift
```

### Auto-Fix WSL Issues
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode Fix-WSL -AutoFix
```

### Run Health Check
```powershell
.\Device-Ecosystem-Manager-v3.2.ps1 -Mode HealthCheck
```

---

## 🐧 WSL Setup

After configuring Windows, set up your WSL environment:

```bash
cd /mnt/c/Users/CWH/ecosystem-evolution
chmod +x setup-wsl-ecosystem-v3.2.sh
./setup-wsl-ecosystem-v3.2.sh
```

---

## 📚 Full Documentation

- **Code Quality Improvements**: `CODE_QUALITY_IMPROVEMENTS_SUMMARY.md`
- **Windows 11 Optimizations**: `WINDOWS11_WSL2_OPTIMIZATIONS.md`
- **Main README**: `README.md`

---

## 🆘 Troubleshooting

### "Script cannot be run because it contains a #requires statement"
**Solution**: You need to run PowerShell as Administrator. Use one of the launchers above.

### "Running scripts is disabled on this system"
**Solution**: Run PowerShell as Admin and execute:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### UAC Prompt Doesn't Appear
**Solution**:
1. Check if UAC is enabled in Windows settings
2. Try running PowerShell as Admin manually first

### "Access Denied" Errors
**Solution**: Ensure you clicked "Yes" on the UAC prompt to grant admin privileges.

---

## 🎉 You're All Set!

The script is now ready to use. All syntax errors have been fixed and the code is optimized for Windows 11 and WSL2!

**Latest Version**: 3.2.0
**Last Updated**: 2025-12-25
**Branch**: claude/improve-code-quality-vCHCC
