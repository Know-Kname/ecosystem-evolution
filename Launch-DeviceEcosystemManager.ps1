<#
.SYNOPSIS
    Launcher for Device Ecosystem Manager with automatic elevation
.DESCRIPTION
    This script automatically requests administrator privileges and launches
    the Device Ecosystem Manager. Use this for convenient desktop shortcuts.
#>

$scriptPath = Join-Path $PSScriptRoot "Device-Ecosystem-Manager-v3.2.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Device-Ecosystem-Manager-v3.2.ps1 not found!" -ForegroundColor Red
    Write-Host "Expected location: $scriptPath" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Cyan
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`""
    exit 0
}

# Already running as admin, just launch the script
& $scriptPath
