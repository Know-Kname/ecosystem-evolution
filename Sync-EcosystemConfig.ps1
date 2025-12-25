#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lightweight scheduled sync script for Device Ecosystem Manager
    
.DESCRIPTION
    This script is designed to be run by Task Scheduler to enforce
    configuration uniformity across all user profiles on the machine.
    
    It performs the following:
    1. Pulls latest configuration from git repository (if available)
    2. Detects configuration drift across all profiles
    3. Optionally auto-repairs drift to match canonical config
    
.PARAMETER AutoRepair
    Automatically fix detected drift without prompting
    
.PARAMETER ReportOnly
    Only detect and report drift, don't make changes
    
.PARAMETER Silent
    Suppress console output (for scheduled task use)
    
.EXAMPLE
    .\Sync-EcosystemConfig.ps1 -AutoRepair -Silent
    
.NOTES
    Author: Device Ecosystem Manager Team
    Version: 3.2.0
#>

[CmdletBinding()]
param(
    [switch]$AutoRepair,
    [switch]$ReportOnly,
    [switch]$Silent
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '3.2.0'

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir = 'C:\ProgramData\DeviceEcosystem\logs'
$LogFile = Join-Path $LogDir "sync-$(Get-Date -Format 'yyyyMMdd').log"

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-SyncLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    
    if (-not $Silent) {
        switch ($Level) {
            'ERROR'   { Write-Host $entry -ForegroundColor Red }
            'WARNING' { Write-Host $entry -ForegroundColor Yellow }
            'SUCCESS' { Write-Host $entry -ForegroundColor Green }
            default   { Write-Host $entry }
        }
    }
}

function Get-UserProfiles {
    $excludedProfiles = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')
    
    Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $excludedProfiles } |
        Where-Object { Test-Path (Join-Path $_.FullName 'NTUSER.DAT') } |
        ForEach-Object {
            @{
                Name = $_.Name
                Path = $_.FullName
                WSLConfigPath = Join-Path $_.FullName '.wslconfig'
                HasWSLConfig = Test-Path (Join-Path $_.FullName '.wslconfig')
            }
        }
}

function Get-CanonicalWSLConfig {
    $canonicalPath = Join-Path $ScriptDir 'canonical-config\wslconfig.ini'
    
    if (-not (Test-Path $canonicalPath)) {
        Write-SyncLog "Canonical config not found: $canonicalPath" -Level 'ERROR'
        return $null
    }
    
    $template = Get-Content -Path $canonicalPath -Raw
    
    # Get system specs for placeholder replacement
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $processors = $cs.NumberOfLogicalProcessors
    
    $optimalMemory = [math]::Max(2, [math]::Min([math]::Floor($totalRAM * 0.5), 16))
    $optimalProcessors = [math]::Max(2, [math]::Floor($processors * 0.8))
    
    # Replace placeholders
    $config = $template
    $config = $config -replace '\{\{MEMORY\}\}', $optimalMemory
    $config = $config -replace '\{\{PROCESSORS\}\}', $optimalProcessors
    $config = $config -replace '\{\{HOSTNAME\}\}', $env:COMPUTERNAME
    $config = $config -replace '\{\{TIMESTAMP\}\}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    
    return $config
}

function Sync-GitRepository {
    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    
    if (-not $gitPath) {
        Write-SyncLog "Git not available - skipping repository sync" -Level 'WARNING'
        return $false
    }
    
    $gitDir = Join-Path $ScriptDir '.git'
    if (-not (Test-Path $gitDir)) {
        Write-SyncLog "Not a git repository - skipping sync" -Level 'WARNING'
        return $false
    }
    
    try {
        Push-Location $ScriptDir
        
        $fetchOutput = git fetch --quiet 2>&1
        $status = git status -uno 2>&1
        
        if ($status -match 'behind') {
            Write-SyncLog "Updates available - pulling..." -Level 'INFO'
            $pullOutput = git pull --quiet 2>&1
            Write-SyncLog "Repository updated" -Level 'SUCCESS'
        }
        else {
            Write-SyncLog "Repository is up to date" -Level 'INFO'
        }
        
        Pop-Location
        return $true
    }
    catch {
        Write-SyncLog "Git sync failed: $($_.Exception.Message)" -Level 'ERROR'
        Pop-Location
        return $false
    }
}

function Compare-Configs {
    param(
        [string]$Canonical,
        [string]$Current
    )
    
    if ([string]::IsNullOrEmpty($Current)) {
        return $false
    }
    
    # Normalize line endings and whitespace for comparison
    $canonicalNorm = ($Canonical -replace '\r\n', "`n").Trim()
    $currentNorm = ($Current -replace '\r\n', "`n").Trim()
    
    return $canonicalNorm -eq $currentNorm
}

# Main execution
Write-SyncLog "=== Device Ecosystem Sync v$ScriptVersion started ===" -Level 'INFO'

# Step 1: Try to sync from git
Write-SyncLog "Step 1: Checking for repository updates..." -Level 'INFO'
Sync-GitRepository | Out-Null

# Step 2: Load canonical config
Write-SyncLog "Step 2: Loading canonical configuration..." -Level 'INFO'
$canonicalConfig = Get-CanonicalWSLConfig

if (-not $canonicalConfig) {
    Write-SyncLog "Cannot proceed without canonical configuration" -Level 'ERROR'
    exit 1
}

# Step 3: Get all profiles and check for drift
Write-SyncLog "Step 3: Checking all user profiles for drift..." -Level 'INFO'
$profiles = @(Get-UserProfiles)

$matching = 0
$drifted = 0
$missing = 0
$repaired = 0

foreach ($profile in $profiles) {
    if (-not $profile.HasWSLConfig) {
        Write-SyncLog "  $($profile.Name): MISSING" -Level 'WARNING'
        $missing++
        
        if ($AutoRepair -and -not $ReportOnly) {
            try {
                $canonicalConfig | Out-File -FilePath $profile.WSLConfigPath -Encoding UTF8 -Force
                Write-SyncLog "  $($profile.Name): REPAIRED (created)" -Level 'SUCCESS'
                $repaired++
            }
            catch {
                Write-SyncLog "  $($profile.Name): REPAIR FAILED - $($_.Exception.Message)" -Level 'ERROR'
            }
        }
    }
    else {
        $currentConfig = Get-Content -Path $profile.WSLConfigPath -Raw -ErrorAction SilentlyContinue
        
        if (Compare-Configs -Canonical $canonicalConfig -Current $currentConfig) {
            Write-SyncLog "  $($profile.Name): OK" -Level 'SUCCESS'
            $matching++
        }
        else {
            Write-SyncLog "  $($profile.Name): DRIFTED" -Level 'WARNING'
            $drifted++
            
            if ($AutoRepair -and -not $ReportOnly) {
                try {
                    # Backup existing
                    $backupPath = "$($profile.WSLConfigPath).bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                    Copy-Item -Path $profile.WSLConfigPath -Destination $backupPath -Force
                    
                    # Apply canonical
                    $canonicalConfig | Out-File -FilePath $profile.WSLConfigPath -Encoding UTF8 -Force
                    Write-SyncLog "  $($profile.Name): REPAIRED" -Level 'SUCCESS'
                    $repaired++
                }
                catch {
                    Write-SyncLog "  $($profile.Name): REPAIR FAILED - $($_.Exception.Message)" -Level 'ERROR'
                }
            }
        }
    }
}

# Summary
Write-SyncLog "=== Sync Complete ===" -Level 'INFO'
Write-SyncLog "  Profiles checked: $($profiles.Count)" -Level 'INFO'
Write-SyncLog "  Matching: $matching" -Level 'INFO'
Write-SyncLog "  Drifted: $drifted" -Level $(if ($drifted -gt 0) { 'WARNING' } else { 'INFO' })
Write-SyncLog "  Missing: $missing" -Level $(if ($missing -gt 0) { 'WARNING' } else { 'INFO' })

if ($AutoRepair) {
    Write-SyncLog "  Repaired: $repaired" -Level $(if ($repaired -gt 0) { 'SUCCESS' } else { 'INFO' })
}

# Exit code: 0 if all matching, 1 if drift detected
$hasDrift = ($drifted -gt 0) -or ($missing -gt 0 -and -not $AutoRepair)
exit $(if ($hasDrift -and -not $AutoRepair) { 1 } else { 0 })

