# ========================================
# Docker/WSL2 Configuration Collection
# Profile: CWH
# Date: 2025-12-31
# ========================================
# 
# This script collects Docker and WSL2 configuration files
# from the CWH Windows user profile for backup and analysis.
#
# USAGE:
#   1. Log in to Windows as CWH user
#   2. Open PowerShell as Administrator
#   3. Copy this entire script and paste into PowerShell
#   4. Press Enter to execute
#   5. Files will be collected to C:\Users\CWH\ConfigBackup
#

$CollectionPath = "C:\Users\CWH\ConfigBackup"
$Username = $env:USERNAME

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Docker/WSL2 Configuration Collection" -ForegroundColor Cyan
Write-Host "Profile: $Username" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create backup directory
Write-Host "[1/5] Creating backup directory..." -ForegroundColor Yellow
if (-not (Test-Path $CollectionPath)) {
    New-Item -Path $CollectionPath -ItemType Directory -Force | Out-Null
    Write-Host "  ✅ Created: $CollectionPath" -ForegroundColor Green
} else {
    Write-Host "  ✅ Already exists: $CollectionPath" -ForegroundColor Green
}

Write-Host ""

# Copy .wslconfig
Write-Host "[2/5] Copying .wslconfig..." -ForegroundColor Yellow
$wslconfigPath = "C:\Users\$Username\.wslconfig"
if (Test-Path $wslconfigPath) {
    Copy-Item -Path $wslconfigPath -Destination "$CollectionPath\.wslconfig" -Force
    Write-Host "  ✅ Copied: .wslconfig" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Not found: .wslconfig (This is OK, will be created during deployment)" -ForegroundColor Yellow
}

Write-Host ""

# Copy daemon.json
Write-Host "[3/5] Copying Docker daemon.json..." -ForegroundColor Yellow
$daemonJsonPath = "C:\Users\$Username\AppData\Roaming\Docker\daemon.json"
if (Test-Path $daemonJsonPath) {
    Copy-Item -Path $daemonJsonPath -Destination "$CollectionPath\daemon.json" -Force
    Write-Host "  ✅ Copied: daemon.json" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Not found: daemon.json (This is OK, will be created during deployment)" -ForegroundColor Yellow
}

Write-Host ""

# Copy config.json
Write-Host "[4/5] Copying Docker config.json..." -ForegroundColor Yellow
$configJsonPath = "C:\Users\$Username\AppData\Roaming\Docker\config.json"
if (Test-Path $configJsonPath) {
    Copy-Item -Path $configJsonPath -Destination "$CollectionPath\config.json" -Force
    Write-Host "  ✅ Copied: config.json" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Not found: config.json (This is OK, will be created during deployment)" -ForegroundColor Yellow
}

Write-Host ""

# Verify and list files
Write-Host "[5/5] Verifying collected files..." -ForegroundColor Yellow
$files = Get-ChildItem $CollectionPath -ErrorAction SilentlyContinue

if ($files.Count -gt 0) {
    Write-Host "  ✅ Successfully collected $($files.Count) file(s):" -ForegroundColor Green
    foreach ($file in $files) {
        Write-Host "     - $($file.Name) ($($file.Length) bytes)" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠️  No files found (This is expected if Docker/WSL2 haven't been configured yet)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Collection Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Open File Explorer to: $CollectionPath" -ForegroundColor White
Write-Host "2. Select all files (Ctrl+A)" -ForegroundColor White
Write-Host "3. Compress to ZIP (Right-click > Send to > Compressed folder)" -ForegroundColor White
Write-Host "4. Upload ZIP to GitHub repository: profiles/CWH/" -ForegroundColor White
Write-Host ""
