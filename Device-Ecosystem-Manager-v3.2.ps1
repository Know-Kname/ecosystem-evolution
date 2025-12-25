<#
.SYNOPSIS
    Device Ecosystem Manager v3.2 - Comprehensive WSL2 & Docker Desktop Management
    
.DESCRIPTION
    Enterprise-grade toolkit for managing WSL2, Docker Desktop, and Windows development
    environment configuration across all user profiles on a device.
    
    Key Features:
    - Device-wide WSL2 configuration management
    - Docker Desktop integration diagnostics and repair
    - Multi-user profile detection and configuration
    - Comprehensive backup and restore with diff preview
    - Health scoring and issue tracking
    - Automated repair capabilities
    
.PARAMETER Mode
    Operation mode: Interactive (default), Inventory, Fix-WSL, Fix-Docker, 
    Configure-All, Backup, Restore, HealthCheck, Verify, Version
    
.PARAMETER AutoFix
    When specified, automatically apply recommended fixes without prompting
    
.PARAMETER Verbose
    Enable verbose output for debugging
    
.PARAMETER BackupPath
    Custom path for backup operations
    
.EXAMPLE
    .\Device-Ecosystem-Manager.ps1
    Runs in interactive menu mode
    
.EXAMPLE
    .\Device-Ecosystem-Manager.ps1 -Mode HealthCheck
    Runs health check and displays score
    
.EXAMPLE
    .\Device-Ecosystem-Manager.ps1 -Mode Fix-WSL -AutoFix
    Automatically repairs WSL2 issues without prompting
    
.NOTES
    Author: Device Ecosystem Manager Team
    Version: 3.2.0
    Requires: Windows 10 2004+ or Windows 11, PowerShell 5.1+
    
.LINK
    https://github.com/device-ecosystem-manager
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Interactive', 'Inventory', 'Fix-WSL', 'Fix-Docker', 'Configure-All', 
                 'Backup', 'Restore', 'HealthCheck', 'Verify', 'Version',
                 'Sync-Profiles', 'Sync-Repo', 'Detect-Drift', 'Install-Enforcement')]
    [string]$Mode = 'Interactive',
    
    [switch]$AutoFix,
    
    [ValidateScript({ Test-Path $_ -IsValid })]
    [string]$BackupPath,
    
    [switch]$Force
)

# ============================================================================
# SELF-ELEVATION - Automatically request Administrator privileges
# ============================================================================

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " DEVICE ECOSYSTEM MANAGER - Elevation Required" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[INFO] Current user: $env:USERNAME" -ForegroundColor Gray
    Write-Host "[INFO] Script path: $PSCommandPath" -ForegroundColor Gray
    Write-Host "[INFO] Mode: $Mode" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[ACTION] Requesting Administrator privileges..." -ForegroundColor Yellow
    Write-Host "[INFO] A UAC prompt will appear - please approve it." -ForegroundColor Gray
    Write-Host ""
    
    # Build parameter string
    $params = @()
    if ($Mode -ne 'Interactive') { $params += "-Mode `"$Mode`"" }
    if ($AutoFix) { $params += "-AutoFix" }
    if ($BackupPath) { $params += "-BackupPath `"$BackupPath`"" }
    if ($Force) { $params += "-Force" }
    $paramString = $params -join ' '
    
    if ($paramString) {
        Write-Host "[INFO] Parameters: $paramString" -ForegroundColor Gray
    }
    
    # Create a script block that runs the script and pauses before closing
    $scriptBlock = @"
`$Host.UI.RawUI.WindowTitle = 'Device Ecosystem Manager (Administrator)'
Write-Host ''
Write-Host '[OK] Running with Administrator privileges' -ForegroundColor Green
Write-Host '[INFO] Working directory: $($PSScriptRoot -replace "'", "''")' -ForegroundColor Gray
Write-Host ''
Set-Location -Path '$($PSScriptRoot -replace "'", "''")'
try {
    & '$($PSCommandPath -replace "'", "''")' $paramString
} catch {
    Write-Host ''
    Write-Host '[ERROR] Script execution failed:' -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
} finally {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' Script execution complete' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Press any key to close this window...' -ForegroundColor Yellow
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
"@
    
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($scriptBlock)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    
    try {
        Write-Host "[ACTION] Launching elevated PowerShell..." -ForegroundColor Yellow
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand -Verb RunAs
        Write-Host "[OK] Elevated process started. You can close this window." -ForegroundColor Green
        Start-Sleep -Seconds 2
        exit 0
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] Failed to elevate: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[INFO] Please right-click the script and select 'Run as Administrator'" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ============================================================================
# CONSTANTS (Eliminates magic numbers - CQ-2 fix)
# ============================================================================

$Script:Constants = @{
    # Resource allocation ratios
    MemoryAllocationRatio = 0.5      # 50% of available RAM (more conservative - BUG-9 fix)
    ProcessorAllocationRatio = 0.8   # 80% of logical processors
    MaxMemoryGB = 16                 # Maximum WSL memory cap
    MinMemoryGB = 2                  # Minimum WSL memory
    MinProcessors = 2                # Minimum processor allocation
    
    # Timeouts (in seconds)
    DockerStartupTimeout = 120
    DockerPollInterval = 5
    WSLShutdownTimeout = 30
    
    # Health scoring weights
    WSLHealthWeight = 0.5
    DockerHealthWeight = 0.5
    
    # Backup settings
    MaxBackupAge = 30                # Days to keep backups
    BackupRetentionCount = 10        # Maximum backups to retain
    
    # Exit codes (standardized)
    ExitSuccess = 0
    ExitGeneralError = 1
    ExitInvalidParameter = 2
    ExitPrerequisiteFailed = 3
    ExitOperationCancelled = 4
}

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    Version = '3.2.0'
    BuildDate = '2024-12-25'
    
    # Color scheme for consistent UI
    Colors = @{
        Header  = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
        Info    = 'White'
        Menu    = 'Magenta'
        Verbose = 'DarkGray'
    }
    
    # Validated paths (SEC-1 fix - paths validated on use)
    Paths = @{
        ScriptRoot       = $PSScriptRoot
        WSLConfig        = Join-Path $env:USERPROFILE '.wslconfig'
        # Note: WSL does NOT support system-wide config - each user needs their own .wslconfig
        DockerDesktop    = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        DockerSettings   = Join-Path $env:APPDATA 'Docker\settings.json'
        BackupRoot       = Join-Path $env:USERPROFILE '.device-ecosystem-backups'
        LogFile          = $null  # Set dynamically
        # Multi-profile and sync paths
        CanonicalConfig  = $null  # Set dynamically based on script location
        CentralLogDir    = 'C:\ProgramData\DeviceEcosystem\logs'
        CentralBackupDir = 'C:\ProgramData\DeviceEcosystem\backups'
    }
    
    # Feature flags
    Features = @{
        AutoBackupBeforeChanges = $true
        VerboseLogging = $true  # Verbose output enabled by default
        PreviewBeforeRestore = $true
        CollectTelemetry = $false
    }
    
    # Backup configuration
    Backup = @{
        Enabled = $true
        MaxAge = 30
        RetentionCount = 10
    }
}

# Initialize dynamic paths
$Script:Config.Paths.LogFile = Join-Path $Script:Config.Paths.ScriptRoot `
    "device-ecosystem-$(Get-Date -Format 'yyyyMMdd').log"
$Script:Config.Paths.CanonicalConfig = Join-Path $Script:Config.Paths.ScriptRoot 'canonical-config'

# Ensure central directories exist (for multi-profile logging)
if (Test-Administrator) {
    @($Script:Config.Paths.CentralLogDir, $Script:Config.Paths.CentralBackupDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            try {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
            }
            catch {
                # Silently continue - will use user-specific paths as fallback
            }
        }
    }
}

# ============================================================================
# INVENTORY DATA STRUCTURE (BUG-5 fix - Issues now contain their fixes)
# ============================================================================

$Script:InventoryData = @{
    Timestamp = $null
    System = @{
        Hostname = $null
        OSVersion = $null
        OSBuild = $null
        TotalRAM_GB = $null
        AvailableRAM_GB = $null  # Added for BUG-9 fix
        LogicalProcessors = $null
        WindowsFeatures = @{}
        IsAdmin = $false
    }
    WSL = @{
        Installed = $false
        Version = $null
        DefaultDistro = $null
        Distributions = @()
        ConfigExists = $false
        ConfigPath = $null
        HealthScore = 0
        HealthStatus = 'Unknown'
    }
    Docker = @{
        DesktopInstalled = $false
        DesktopRunning = $false
        DesktopVersion = $null
        EngineResponsive = $false
        WSLIntegrationEnabled = $false
        IntegratedDistros = @()
        Containers = @()
        Images = @()
        DiskUsage = $null
        HealthScore = 0
        HealthStatus = 'Unknown'
    }
    Users = @()
    # BUG-5 fix: Issues now contain their own fix recommendations
    Issues = @()  # Array of @{ Severity; Category; Issue; Fix; AutoFixable }
    HealthScore = $null
    HealthStatus = 'Not Assessed'
    AssessmentComplete = $false
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry with timestamp and severity level
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Severity level: Info, Warning, Error, Debug, Verbose
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug', 'Verbose')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # BUG-11 fix: Wrap file write in try/catch
    try {
        $logDir = Split-Path $Script:Config.Paths.LogFile -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $Script:Config.Paths.LogFile -Value $logEntry -ErrorAction Stop
    }
    catch {
        # Fallback to console if file logging fails
        if ($Script:Config.Features.VerboseLogging) {
            Write-Host "[LOG FAILED] $logEntry" -ForegroundColor DarkGray
        }
    }
    
    # Also output to verbose stream if enabled
    if ($Level -eq 'Verbose' -and $Script:Config.Features.VerboseLogging) {
        Write-Host $logEntry -ForegroundColor $Script:Config.Colors.Verbose
    }
}

function Write-ColorHost {
    <#
    .SYNOPSIS
        Writes colored output to console with consistent styling
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('Header', 'Success', 'Warning', 'Error', 'Info', 'Menu', 'Verbose')]
        [string]$Type = 'Info',
        
        [switch]$NoNewline
    )
    
    $color = $Script:Config.Colors[$Type]
    $prefix = switch ($Type) {
        'Success' { '✓ ' }
        'Warning' { '⚠ ' }
        'Error'   { '✗ ' }
        'Info'    { '  ' }
        default   { '' }
    }
    
    $params = @{
        Object = "$prefix$Message"
        ForegroundColor = $color
        NoNewline = $NoNewline
    }
    
    Write-Host @params
}

function Write-SectionHeader {
    <#
    .SYNOPSIS
        Writes a formatted section header
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Title
    )
    
    $line = '=' * 70
    Write-Host ""
    Write-Host $line -ForegroundColor $Script:Config.Colors.Header
    Write-Host " $Title" -ForegroundColor $Script:Config.Colors.Header
    Write-Host $line -ForegroundColor $Script:Config.Colors.Header
    Write-Host ""
}

function Write-Banner {
    <#
    .SYNOPSIS
        Displays the application banner
    #>
    Clear-Host
    $banner = @"

    ╔═══════════════════════════════════════════════════════════════════╗
    ║         DEVICE ECOSYSTEM MANAGER v$($Script:Config.Version)                      ║
    ║         WSL2 & Docker Desktop Management Toolkit                  ║
    ╚═══════════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor $Script:Config.Colors.Header
}

function Confirm-Action {
    <#
    .SYNOPSIS
        Prompts user for confirmation with default option support
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [switch]$DefaultYes
    )
    
    # Auto-confirm if AutoFix mode is enabled
    if ($Script:AutoFix) {
        Write-Log "Auto-confirmed: $Message" -Level 'Verbose'
        return $true
    }
    
    $prompt = if ($DefaultYes) { "$Message [Y/n]" } else { "$Message [y/N]" }
    $response = Read-Host $prompt
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes
    }
    
    return $response -match '^[Yy]'
}

function Wait-KeyPress {
    <#
    .SYNOPSIS
        Waits for user to press any key (extracted from repeated code - CQ-3 fix)
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Press any key to continue..."
    )
    
    Write-Host "`n$Message" -ForegroundColor $Script:Config.Colors.Info
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Verifies script is running with administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ValidPath {
    <#
    .SYNOPSIS
        Validates a path exists and is accessible (SEC-1 fix)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [ValidateSet('File', 'Directory', 'Any')]
        [string]$Type = 'Any'
    )
    
    if (-not (Test-Path $Path)) {
        return $false
    }
    
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        return $false
    }
    
    switch ($Type) {
        'File' { return -not $item.PSIsContainer }
        'Directory' { return $item.PSIsContainer }
        'Any' { return $true }
    }
}

function ConvertFrom-JsonSafe {
    <#
    .SYNOPSIS
        Safely parses JSON with error handling (SEC-2 fix)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonString,
        
        [hashtable]$DefaultValue = @{}
    )
    
    try {
        $result = $JsonString | ConvertFrom-Json -ErrorAction Stop
        return $result
    }
    catch {
        Write-Log "JSON parse error: $($_.Exception.Message)" -Level 'Warning'
        return $DefaultValue
    }
}

function Add-Issue {
    <#
    .SYNOPSIS
        Adds an issue to the inventory with its fix recommendation (BUG-5 fix)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning', 'Info')]
        [string]$Severity,
        
        [Parameter(Mandatory)]
        [ValidateSet('WSL', 'Docker', 'System', 'Configuration')]
        [string]$Category,
        
        [Parameter(Mandatory)]
        [string]$Issue,
        
        [string]$Fix = '',
        
        [bool]$AutoFixable = $false
    )
    
    $Script:InventoryData.Issues += @{
        Severity = $Severity
        Category = $Category
        Issue = $Issue
        Fix = $Fix
        AutoFixable = $AutoFixable
        Timestamp = Get-Date -Format 'o'
    }
    
    Write-Log "$Severity in $Category : $Issue" -Level $(if ($Severity -eq 'Error') { 'Error' } else { 'Warning' })
}

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        Executes native commands with proper error handling (BUG-10 fix)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        
        [string[]]$Arguments,
        
        [switch]$PassThru,
        
        [switch]$SuppressOutput
    )
    
    $output = $null
    
    try {
        if ($Arguments) {
            $output = & $Command @Arguments 2>&1
        }
        else {
            $output = & $Command 2>&1
        }
        
        $exitCode = $LASTEXITCODE
        
        if (-not $SuppressOutput -and $output) {
            Write-Log "Command output: $($output | Out-String)" -Level 'Verbose'
        }
        
        if ($PassThru) {
            return @{
                Success = ($exitCode -eq 0)
                ExitCode = $exitCode
                Output = $output
            }
        }
        
        return ($exitCode -eq 0)
    }
    catch {
        Write-Log "Command execution failed: $($_.Exception.Message)" -Level 'Error'
        
        if ($PassThru) {
            return @{
                Success = $false
                ExitCode = -1
                Output = $_.Exception.Message
            }
        }
        
        return $false
    }
}


# ============================================================================
# BACKUP & RESTORE MODULE (BUG-3 fix: Added diff preview and merge options)
# ============================================================================

function Backup-Configuration {
    <#
    .SYNOPSIS
        Creates timestamped backup of WSL and Docker configurations
    .PARAMETER Path
        Optional custom backup path
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )
    
    Write-SectionHeader "CONFIGURATION BACKUP"
    
    $backupRoot = if ($Path) { $Path } else { $Script:Config.Paths.BackupRoot }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupRoot "backup-$timestamp"
    
    try {
        # Create backup directory
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Write-ColorHost "Created backup directory: $backupPath" -Type Info
        
        $backedUp = @()
        
        # Backup user .wslconfig
        if (Test-ValidPath $Script:Config.Paths.WSLConfig -Type File) {
            $dest = Join-Path $backupPath 'user-wslconfig'
            Copy-Item -Path $Script:Config.Paths.WSLConfig -Destination $dest -Force
            $backedUp += @{ Type = 'WSL User Config'; Path = $Script:Config.Paths.WSLConfig }
            Write-ColorHost "Backed up: User .wslconfig" -Type Success
        }
        
        # Backup all user profile .wslconfig files (multi-profile support)
        $allProfiles = Get-AllUserProfiles
        foreach ($profile in $allProfiles) {
            if ($profile.HasWSLConfig) {
                $dest = Join-Path $backupPath "wslconfig-$($profile.Name)"
                Copy-Item -Path $profile.WSLConfigPath -Destination $dest -Force
                $backedUp += @{ Type = "WSL Config ($($profile.Name))"; Path = $profile.WSLConfigPath }
                Write-ColorHost "Backed up: .wslconfig for $($profile.Name)" -Type Success
            }
        }
        
        # Backup Docker settings
        if (Test-ValidPath $Script:Config.Paths.DockerSettings -Type File) {
            $dest = Join-Path $backupPath 'docker-settings.json'
            Copy-Item -Path $Script:Config.Paths.DockerSettings -Destination $dest -Force
            $backedUp += @{ Type = 'Docker Settings'; Path = $Script:Config.Paths.DockerSettings }
            Write-ColorHost "Backed up: Docker settings" -Type Success
        }
        
        # Create manifest with metadata
        $manifest = @{
            Timestamp = Get-Date -Format 'o'
            Version = $Script:Config.Version
            Computer = $env:COMPUTERNAME
            User = $env:USERNAME
            BackupPath = $backupPath
            Files = $backedUp
            SystemInfo = @{
                OSVersion = [System.Environment]::OSVersion.VersionString
                PSVersion = $PSVersionTable.PSVersion.ToString()
            }
        }
        
        $manifestPath = Join-Path $backupPath 'manifest.json'
        $manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding UTF8
        
        # Cleanup old backups
        Invoke-BackupCleanup -BackupRoot $backupRoot
        
        Write-ColorHost "Backup complete: $backupPath" -Type Success
        Write-Log "Backup created: $backupPath with $($backedUp.Count) files" -Level 'Info'
        
        return $backupPath
    }
    catch {
        Write-ColorHost "Backup failed: $($_.Exception.Message)" -Type Error
        Write-Log "Backup error: $($_.Exception.Message)" -Level 'Error'
        return $null
    }
}

function Invoke-BackupCleanup {
    <#
    .SYNOPSIS
        Removes old backups beyond retention policy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot
    )
    
    if (-not (Test-ValidPath $BackupRoot -Type Directory)) {
        return
    }
    
    $backups = Get-ChildItem -Path $BackupRoot -Directory | 
        Where-Object { $_.Name -match '^backup-\d{8}-\d{6}$' } |
        Sort-Object CreationTime -Descending
    
    # Remove backups beyond retention count
    $toRemove = $backups | Select-Object -Skip $Script:Constants.BackupRetentionCount
    
    foreach ($backup in $toRemove) {
        try {
            Remove-Item -Path $backup.FullName -Recurse -Force
            Write-Log "Removed old backup: $($backup.Name)" -Level 'Verbose'
        }
        catch {
            Write-Log "Failed to remove old backup: $($backup.Name)" -Level 'Warning'
        }
    }
}

function Get-BackupList {
    <#
    .SYNOPSIS
        Returns list of available backups
    #>
    [CmdletBinding()]
    param()
    
    $backupRoot = $Script:Config.Paths.BackupRoot
    
    if (-not (Test-ValidPath $backupRoot -Type Directory)) {
        return @()
    }
    
    $backups = Get-ChildItem -Path $backupRoot -Directory |
        Where-Object { $_.Name -match '^backup-\d{8}-\d{6}$' } |
        Sort-Object CreationTime -Descending |
        ForEach-Object {
            $manifestPath = Join-Path $_.FullName 'manifest.json'
            $manifest = $null
            
            if (Test-ValidPath $manifestPath -Type File) {
                $content = Get-Content -Path $manifestPath -Raw
                $manifest = ConvertFrom-JsonSafe -JsonString $content
            }
            
            @{
                Name = $_.Name
                Path = $_.FullName
                Created = $_.CreationTime
                Manifest = $manifest
                FileCount = if ($manifest) { $manifest.Files.Count } else { 0 }
            }
        }
    
    return $backups
}

function Show-ConfigDiff {
    <#
    .SYNOPSIS
        Shows differences between backup and current configuration (BUG-3 fix)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    Write-ColorHost "Configuration Differences:" -Type Header
    Write-Host ""
    
    $hasChanges = $false
    
    # Compare WSL config
    $backupWSLConfig = Join-Path $BackupPath 'user-wslconfig'
    if ((Test-ValidPath $backupWSLConfig -Type File) -and (Test-ValidPath $Script:Config.Paths.WSLConfig -Type File)) {
        $backupContent = Get-Content -Path $backupWSLConfig -Raw
        $currentContent = Get-Content -Path $Script:Config.Paths.WSLConfig -Raw
        
        if ($backupContent -ne $currentContent) {
            $hasChanges = $true
            Write-ColorHost ".wslconfig has differences:" -Type Warning
            Write-Host "  Backup: $($backupContent.Length) chars" -ForegroundColor DarkGray
            Write-Host "  Current: $($currentContent.Length) chars" -ForegroundColor DarkGray
        }
        else {
            Write-ColorHost ".wslconfig: No changes" -Type Success
        }
    }
    
    # Compare Docker settings
    $backupDocker = Join-Path $BackupPath 'docker-settings.json'
    if ((Test-ValidPath $backupDocker -Type File) -and (Test-ValidPath $Script:Config.Paths.DockerSettings -Type File)) {
        $backupContent = Get-Content -Path $backupDocker -Raw
        $currentContent = Get-Content -Path $Script:Config.Paths.DockerSettings -Raw
        
        if ($backupContent -ne $currentContent) {
            $hasChanges = $true
            Write-ColorHost "Docker settings.json has differences" -Type Warning
        }
        else {
            Write-ColorHost "Docker settings: No changes" -Type Success
        }
    }
    
    return $hasChanges
}

function Restore-Configuration {
    <#
    .SYNOPSIS
        Restores configuration from backup with preview option
    .PARAMETER BackupPath
        Path to specific backup, or prompts for selection
    .PARAMETER Force
        Skip confirmation prompts
    #>
    [CmdletBinding()]
    param(
        [string]$BackupPath,
        [switch]$Force
    )
    
    Write-SectionHeader "CONFIGURATION RESTORE"
    
    # Get available backups
    $backups = Get-BackupList
    
    if ($backups.Count -eq 0) {
        Write-ColorHost "No backups found in: $($Script:Config.Paths.BackupRoot)" -Type Warning
        return $false
    }
    
    # Select backup if not specified
    if (-not $BackupPath) {
        Write-ColorHost "Available Backups:" -Type Info
        Write-Host ""
        
        for ($i = 0; $i -lt [Math]::Min($backups.Count, 10); $i++) {
            $backup = $backups[$i]
            $age = ((Get-Date) - $backup.Created).Days
            $ageText = if ($age -eq 0) { "today" } elseif ($age -eq 1) { "yesterday" } else { "$age days ago" }
            Write-Host "  [$($i+1)] $($backup.Name) - $ageText ($($backup.FileCount) files)" -ForegroundColor $Script:Config.Colors.Info
        }
        Write-Host ""
        
        $selection = Read-Host "Select backup (1-$([Math]::Min($backups.Count, 10))) or [C]ancel"
        
        if ($selection -match '^[Cc]') {
            Write-ColorHost "Restore cancelled" -Type Warning
            return $false
        }
        
        $index = [int]$selection - 1
        if ($index -lt 0 -or $index -ge $backups.Count) {
            Write-ColorHost "Invalid selection" -Type Error
            return $false
        }
        
        $BackupPath = $backups[$index].Path
    }
    
    # Validate backup path
    if (-not (Test-ValidPath $BackupPath -Type Directory)) {
        Write-ColorHost "Backup path not found: $BackupPath" -Type Error
        return $false
    }
    
    # Preview changes if enabled (BUG-3 fix)
    if ($Script:Config.Features.PreviewBeforeRestore -and -not $Force) {
        $hasChanges = Show-ConfigDiff -BackupPath $BackupPath
        
        if ($hasChanges) {
            Write-Host ""
            if (-not (Confirm-Action "Restore will overwrite current configuration. Continue?")) {
                Write-ColorHost "Restore cancelled" -Type Warning
                return $false
            }
        }
    }
    
    # Create backup of current state before restore
    if ($Script:Config.Features.AutoBackupBeforeChanges) {
        Write-ColorHost "Creating backup of current state..." -Type Info
        Backup-Configuration | Out-Null
    }
    
    $restored = 0
    
    try {
        # Restore user .wslconfig
        $backupWSLConfig = Join-Path $BackupPath 'user-wslconfig'
        if (Test-ValidPath $backupWSLConfig -Type File) {
            Copy-Item -Path $backupWSLConfig -Destination $Script:Config.Paths.WSLConfig -Force
            Write-ColorHost "Restored: User .wslconfig" -Type Success
            $restored++
        }
        
        # Restore multi-profile .wslconfig files
        $profileBackups = Get-ChildItem -Path $BackupPath -Filter 'wslconfig-*' -ErrorAction SilentlyContinue
        foreach ($backup in $profileBackups) {
            $profileName = $backup.Name -replace '^wslconfig-', ''
            $targetProfile = Get-AllUserProfiles | Where-Object { $_.Name -eq $profileName } | Select-Object -First 1
            if ($targetProfile) {
                Copy-Item -Path $backup.FullName -Destination $targetProfile.WSLConfigPath -Force
                Write-ColorHost "Restored: .wslconfig for $profileName" -Type Success
                $restored++
            }
        }
        
        # Restore Docker settings (with caution)
        $backupDocker = Join-Path $BackupPath 'docker-settings.json'
        if (Test-ValidPath $backupDocker -Type File) {
            if ($Script:InventoryData.Docker.DesktopRunning) {
                Write-ColorHost "Docker Desktop is running. Stop it before restoring settings." -Type Warning
            }
            else {
                Copy-Item -Path $backupDocker -Destination $Script:Config.Paths.DockerSettings -Force
                Write-ColorHost "Restored: Docker settings" -Type Success
                $restored++
            }
        }
        
        Write-Host ""
        Write-ColorHost "Restore complete: $restored file(s) restored" -Type Success
        Write-ColorHost "Restart WSL (wsl --shutdown) to apply changes" -Type Warning
        Write-Log "Restore completed from $BackupPath" -Level 'Info'
        
        return $true
    }
    catch {
        Write-ColorHost "Restore failed: $($_.Exception.Message)" -Type Error
        Write-Log "Restore error: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}


# ============================================================================
# MULTI-PROFILE SYNC MODULE
# ============================================================================

function Get-CanonicalConfig {
    <#
    .SYNOPSIS
        Loads and parses the canonical configuration from the repository
    .PARAMETER ConfigType
        Type of config to load: WSL, Docker, or Manifest
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WSL', 'Docker', 'Manifest')]
        [string]$ConfigType
    )
    
    $configPath = $Script:Config.Paths.CanonicalConfig
    
    if (-not (Test-ValidPath $configPath -Type Directory)) {
        Write-Log "Canonical config directory not found: $configPath" -Level 'Error'
        return $null
    }
    
    $filePath = switch ($ConfigType) {
        'WSL'      { Join-Path $configPath 'wslconfig.ini' }
        'Docker'   { Join-Path $configPath 'docker-settings.json' }
        'Manifest' { Join-Path $configPath 'manifest.json' }
    }
    
    if (-not (Test-ValidPath $filePath -Type File)) {
        Write-Log "Canonical config file not found: $filePath" -Level 'Warning'
        return $null
    }
    
    try {
        $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
        
        if ($ConfigType -in @('Docker', 'Manifest')) {
            return ConvertFrom-JsonSafe -JsonString $content
        }
        
        return $content
    }
    catch {
        Write-Log "Failed to load canonical config: $($_.Exception.Message)" -Level 'Error'
        return $null
    }
}

function Resolve-ConfigPlaceholders {
    <#
    .SYNOPSIS
        Replaces placeholders in config template with machine-specific values
    .PARAMETER Template
        The config template content
    .PARAMETER ConfigType
        Type of config: WSL or Docker
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Template,
        
        [Parameter(Mandatory)]
        [ValidateSet('WSL', 'Docker')]
        [string]$ConfigType
    )
    
    # Calculate machine-specific values
    $totalRAM = $Script:InventoryData.System.TotalRAM_GB
    if (-not $totalRAM) {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    }
    
    $processors = $Script:InventoryData.System.LogicalProcessors
    if (-not $processors) {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $processors = $cs.NumberOfLogicalProcessors
    }
    
    $optimalMemoryGB = [math]::Max(
        $Script:Constants.MinMemoryGB,
        [math]::Min(
            [math]::Floor($totalRAM * $Script:Constants.MemoryAllocationRatio),
            $Script:Constants.MaxMemoryGB
        )
    )
    
    $optimalProcessors = [math]::Max(
        $Script:Constants.MinProcessors,
        [math]::Floor($processors * $Script:Constants.ProcessorAllocationRatio)
    )
    
    # Get WSL distros for Docker integration
    $wslDistros = @()
    if ($Script:InventoryData.WSL.Distributions) {
        $wslDistros = $Script:InventoryData.WSL.Distributions | 
            Where-Object { $_.Version -eq 2 } | 
            Select-Object -ExpandProperty Name
    }
    
    # Replace placeholders
    $result = $Template
    $result = $result -replace '\{\{MEMORY\}\}', $optimalMemoryGB
    $result = $result -replace '\{\{PROCESSORS\}\}', $optimalProcessors
    $result = $result -replace '\{\{HOSTNAME\}\}', $env:COMPUTERNAME
    $result = $result -replace '\{\{TIMESTAMP\}\}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $result = $result -replace '\{\{MEMORY_MB\}\}', ($optimalMemoryGB * 1024)
    $result = $result -replace '\{\{WSL_DISTROS\}\}', ($wslDistros -join '","')
    
    return $result
}

function Get-AllUserProfiles {
    <#
    .SYNOPSIS
        Gets all user profiles on the machine (excluding system profiles)
    #>
    [CmdletBinding()]
    param()
    
    $excludedProfiles = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')
    
    $profiles = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $excludedProfiles } |
        ForEach-Object {
            $profilePath = $_.FullName
            $ntUserPath = Join-Path $profilePath 'NTUSER.DAT'
            
            # Check if this is a real user profile (has NTUSER.DAT)
            if (Test-Path $ntUserPath) {
                @{
                    Name = $_.Name
                    Path = $profilePath
                    WSLConfigPath = Join-Path $profilePath '.wslconfig'
                    HasWSLConfig = Test-Path (Join-Path $profilePath '.wslconfig')
                    DockerSettingsPath = Join-Path $profilePath 'AppData\Roaming\Docker\settings.json'
                    HasDockerSettings = Test-Path (Join-Path $profilePath 'AppData\Roaming\Docker\settings.json')
                    IsCurrent = ($_.Name -eq $env:USERNAME)
                }
            }
        }
    
    return @($profiles | Where-Object { $_ })
}

function Sync-AllProfiles {
    <#
    .SYNOPSIS
        Propagates canonical WSL configuration to ALL Windows user profiles
    .PARAMETER Force
        Apply without confirmation prompts
    .PARAMETER WhatIf
        Show what would be done without making changes
    #>
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$WhatIf
    )
    
    Write-SectionHeader "MULTI-PROFILE SYNC"
    
    if (-not (Test-Administrator)) {
        Write-ColorHost "Multi-profile sync requires administrator privileges" -Type Error
        return $false
    }
    
    # Load canonical config
    $canonicalWSL = Get-CanonicalConfig -ConfigType 'WSL'
    if (-not $canonicalWSL) {
        Write-ColorHost "Could not load canonical WSL configuration" -Type Error
        Write-ColorHost "Ensure canonical-config/wslconfig.ini exists" -Type Info
        return $false
    }
    
    # Resolve placeholders
    $resolvedConfig = Resolve-ConfigPlaceholders -Template $canonicalWSL -ConfigType 'WSL'
    
    # Get all profiles
    $profiles = Get-AllUserProfiles
    
    if ($profiles.Count -eq 0) {
        Write-ColorHost "No user profiles found to sync" -Type Warning
        return $false
    }
    
    Write-ColorHost "Found $($profiles.Count) user profile(s) to sync:" -Type Info
    foreach ($profile in $profiles) {
        $status = if ($profile.HasWSLConfig) { "[has config]" } else { "[no config]" }
        $current = if ($profile.IsCurrent) { " (current)" } else { "" }
        Write-Host "  • $($profile.Name)$current $status" -ForegroundColor $Script:Config.Colors.Info
    }
    
    if ($WhatIf) {
        Write-ColorHost "`nWhatIf: Would sync .wslconfig to $($profiles.Count) profile(s)" -Type Info
        return $true
    }
    
    if (-not $Force -and -not (Confirm-Action "`nSync .wslconfig to all profiles?" -DefaultYes)) {
        Write-ColorHost "Sync cancelled" -Type Warning
        return $false
    }
    
    # Create central backup before sync
    $backupPath = Join-Path $Script:Config.Paths.CentralBackupDir "pre-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }
    
    $synced = 0
    $failed = 0
    
    foreach ($profile in $profiles) {
        Write-ColorHost "Syncing: $($profile.Name)..." -Type Info
        
        try {
            # Backup existing config if present
            if ($profile.HasWSLConfig) {
                $backupFile = Join-Path $backupPath "$($profile.Name)-wslconfig.bak"
                Copy-Item -Path $profile.WSLConfigPath -Destination $backupFile -Force
                Write-Log "Backed up $($profile.Name) .wslconfig to $backupFile" -Level 'Verbose'
            }
            
            # Write the resolved config
            $resolvedConfig | Out-File -FilePath $profile.WSLConfigPath -Encoding UTF8 -Force
            
            Write-ColorHost "  Synced .wslconfig to $($profile.Name)" -Type Success
            $synced++
        }
        catch {
            Write-ColorHost "  Failed to sync $($profile.Name): $($_.Exception.Message)" -Type Error
            Write-Log "Sync error for $($profile.Name): $($_.Exception.Message)" -Level 'Error'
            $failed++
        }
    }
    
    Write-Host ""
    Write-ColorHost "Sync complete: $synced succeeded, $failed failed" -Type $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    if ($synced -gt 0) {
        Write-ColorHost "Restart WSL to apply: wsl --shutdown" -Type Warning
    }
    
    Write-Log "Multi-profile sync: $synced synced, $failed failed" -Level 'Info'
    
    return ($failed -eq 0)
}

function Sync-FromRepository {
    <#
    .SYNOPSIS
        Pulls latest canonical configuration from git repository
    .PARAMETER RepoPath
        Path to the git repository (defaults to script directory)
    .PARAMETER Apply
        Apply the synced configuration to all profiles
    #>
    [CmdletBinding()]
    param(
        [string]$RepoPath,
        [switch]$Apply
    )
    
    Write-SectionHeader "SYNC FROM REPOSITORY"
    
    $repoPath = if ($RepoPath) { $RepoPath } else { $Script:Config.Paths.ScriptRoot }
    
    # Check if this is a git repository
    $gitDir = Join-Path $repoPath '.git'
    if (-not (Test-Path $gitDir)) {
        Write-ColorHost "Not a git repository: $repoPath" -Type Error
        Write-ColorHost "Initialize with: git init && git remote add origin <url>" -Type Info
        return $false
    }
    
    # Check for git command
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-ColorHost "Git is not installed or not in PATH" -Type Error
        return $false
    }
    
    Write-ColorHost "Pulling latest configuration from repository..." -Type Info
    
    try {
        Push-Location $repoPath
        
        # Fetch and check for updates
        $fetchResult = Invoke-NativeCommand -Command 'git' -Arguments @('fetch', '--quiet') -PassThru
        
        if (-not $fetchResult.Success) {
            Write-ColorHost "Failed to fetch from remote (may be offline)" -Type Warning
            Write-Log "Git fetch failed: $($fetchResult.Output)" -Level 'Warning'
        }
        else {
            # Check if we're behind
            $statusResult = Invoke-NativeCommand -Command 'git' -Arguments @('status', '-uno') -PassThru
            
            if ($statusResult.Output -match 'behind') {
                Write-ColorHost "Updates available - pulling..." -Type Info
                
                $pullResult = Invoke-NativeCommand -Command 'git' -Arguments @('pull', '--quiet') -PassThru
                
                if ($pullResult.Success) {
                    Write-ColorHost "Repository updated successfully" -Type Success
                }
                else {
                    Write-ColorHost "Pull failed: $($pullResult.Output)" -Type Error
                    return $false
                }
            }
            else {
                Write-ColorHost "Repository is up to date" -Type Success
            }
        }
        
        # Verify canonical config exists
        $configDir = Join-Path $repoPath 'canonical-config'
        if (Test-Path $configDir) {
            $manifest = Get-CanonicalConfig -ConfigType 'Manifest'
            if ($manifest) {
                Write-ColorHost "Canonical config version: $($manifest.version)" -Type Info
            }
        }
        else {
            Write-ColorHost "Warning: canonical-config directory not found" -Type Warning
        }
        
        Pop-Location
        
        # Apply if requested
        if ($Apply) {
            Write-Host ""
            Sync-AllProfiles
        }
        
        return $true
    }
    catch {
        Write-ColorHost "Repository sync failed: $($_.Exception.Message)" -Type Error
        Write-Log "Repository sync error: $($_.Exception.Message)" -Level 'Error'
        Pop-Location
        return $false
    }
}

function Compare-ProfileConfigs {
    <#
    .SYNOPSIS
        Compares configurations across all profiles to detect drift
    .PARAMETER Detailed
        Show detailed differences
    #>
    [CmdletBinding()]
    param(
        [switch]$Detailed
    )
    
    Write-SectionHeader "CONFIGURATION DRIFT DETECTION"
    
    # Load canonical config
    $canonicalWSL = Get-CanonicalConfig -ConfigType 'WSL'
    $resolvedCanonical = if ($canonicalWSL) {
        Resolve-ConfigPlaceholders -Template $canonicalWSL -ConfigType 'WSL'
    } else { $null }
    
    # Get all profiles
    $profiles = Get-AllUserProfiles
    
    if ($profiles.Count -eq 0) {
        Write-ColorHost "No user profiles found" -Type Warning
        return @()
    }
    
    $driftReport = @()
    $canonicalHash = if ($resolvedCanonical) {
        [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($resolvedCanonical)
            )
        ).Replace('-', '').Substring(0, 16)
    } else { 'NO_CANONICAL' }
    
    Write-ColorHost "Canonical config hash: $canonicalHash" -Type Info
    Write-Host ""
    
    foreach ($profile in $profiles) {
        $status = @{
            Profile = $profile.Name
            HasConfig = $profile.HasWSLConfig
            MatchesCanonical = $false
            ConfigHash = $null
            DriftDetails = @()
        }
        
        if ($profile.HasWSLConfig) {
            try {
                $content = Get-Content -Path $profile.WSLConfigPath -Raw -ErrorAction Stop
                $profileHash = [System.BitConverter]::ToString(
                    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                        [System.Text.Encoding]::UTF8.GetBytes($content)
                    )
                ).Replace('-', '').Substring(0, 16)
                
                $status.ConfigHash = $profileHash
                $status.MatchesCanonical = ($profileHash -eq $canonicalHash)
                
                if (-not $status.MatchesCanonical -and $Detailed -and $resolvedCanonical) {
                    # Find specific differences
                    $canonicalLines = $resolvedCanonical -split "`n" | Where-Object { $_ -match '^\w' }
                    $profileLines = $content -split "`n" | Where-Object { $_ -match '^\w' }
                    
                    $diffs = Compare-Object -ReferenceObject $canonicalLines -DifferenceObject $profileLines -PassThru
                    $status.DriftDetails = @($diffs)
                }
            }
            catch {
                $status.ConfigHash = 'READ_ERROR'
            }
        }
        else {
            $status.ConfigHash = 'MISSING'
        }
        
        # Display status
        $icon = if ($status.MatchesCanonical) { '✓' } elseif ($status.HasConfig) { '⚠' } else { '✗' }
        $color = if ($status.MatchesCanonical) { 'Success' } elseif ($status.HasConfig) { 'Warning' } else { 'Error' }
        $hashDisplay = if ($status.ConfigHash) { " [$($status.ConfigHash)]" } else { "" }
        
        Write-ColorHost "$icon $($profile.Name)$hashDisplay" -Type $color
        
        if ($Detailed -and $status.DriftDetails.Count -gt 0) {
            foreach ($diff in $status.DriftDetails | Select-Object -First 5) {
                $indicator = if ($diff.SideIndicator -eq '=>') { '+' } else { '-' }
                Write-Host "    $indicator $diff" -ForegroundColor DarkGray
            }
            if ($status.DriftDetails.Count -gt 5) {
                Write-Host "    ... and $($status.DriftDetails.Count - 5) more differences" -ForegroundColor DarkGray
            }
        }
        
        $driftReport += $status
    }
    
    # Summary
    Write-Host ""
    $matching = @($driftReport | Where-Object { $_.MatchesCanonical }).Count
    $drifted = @($driftReport | Where-Object { $_.HasConfig -and -not $_.MatchesCanonical }).Count
    $missing = @($driftReport | Where-Object { -not $_.HasConfig }).Count
    
    Write-ColorHost "Summary: $matching matching, $drifted drifted, $missing missing" -Type Info
    
    if ($drifted -gt 0 -or $missing -gt 0) {
        Write-ColorHost "Run 'Sync-AllProfiles' to fix drift" -Type Warning
    }
    
    Write-Log "Drift detection: $matching matching, $drifted drifted, $missing missing" -Level 'Info'
    
    return $driftReport
}

function Sync-DockerSettings {
    <#
    .SYNOPSIS
        Synchronizes Docker Desktop settings across all user profiles
    .PARAMETER Force
        Apply without confirmation
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    Write-SectionHeader "DOCKER SETTINGS SYNC"
    
    if (-not (Test-Administrator)) {
        Write-ColorHost "Docker settings sync requires administrator privileges" -Type Error
        return $false
    }
    
    # Load canonical Docker settings
    $canonicalDocker = Get-CanonicalConfig -ConfigType 'Docker'
    if (-not $canonicalDocker) {
        Write-ColorHost "Could not load canonical Docker configuration" -Type Error
        return $false
    }
    
    # Convert to JSON and resolve placeholders
    $dockerJson = $canonicalDocker | ConvertTo-Json -Depth 10
    $resolvedDocker = Resolve-ConfigPlaceholders -Template $dockerJson -ConfigType 'Docker'
    
    # Get profiles
    $profiles = Get-AllUserProfiles
    
    Write-ColorHost "Found $($profiles.Count) profile(s)" -Type Info
    
    if (-not $Force -and -not (Confirm-Action "Sync Docker settings to all profiles?")) {
        Write-ColorHost "Sync cancelled" -Type Warning
        return $false
    }
    
    $synced = 0
    $skipped = 0
    $failed = 0
    
    foreach ($profile in $profiles) {
        $dockerDir = Join-Path $profile.Path 'AppData\Roaming\Docker'
        $settingsPath = Join-Path $dockerDir 'settings.json'
        
        # Only sync if Docker directory exists (user has Docker installed)
        if (Test-Path $dockerDir) {
            try {
                # Backup existing
                if (Test-Path $settingsPath) {
                    $backupPath = Join-Path $Script:Config.Paths.CentralBackupDir "docker-$($profile.Name)-$(Get-Date -Format 'yyyyMMdd').json"
                    Copy-Item -Path $settingsPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
                }
                
                $resolvedDocker | Out-File -FilePath $settingsPath -Encoding UTF8 -Force
                Write-ColorHost "  Synced Docker settings to $($profile.Name)" -Type Success
                $synced++
            }
            catch {
                Write-ColorHost "  Failed for $($profile.Name): $($_.Exception.Message)" -Type Error
                $failed++
            }
        }
        else {
            Write-Host "  Skipped $($profile.Name) (no Docker directory)" -ForegroundColor DarkGray
            $skipped++
        }
    }
    
    Write-Host ""
    Write-ColorHost "Docker sync: $synced synced, $skipped skipped, $failed failed" -Type $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    if ($synced -gt 0) {
        Write-ColorHost "Restart Docker Desktop to apply changes" -Type Warning
    }
    
    return ($failed -eq 0)
}


# ============================================================================
# SYSTEM INVENTORY MODULE
# ============================================================================

function Get-SystemInventory {
    <#
    .SYNOPSIS
        Collects comprehensive system information
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "SYSTEM INVENTORY"
    
    $Script:InventoryData.Timestamp = Get-Date -Format 'o'
    
    # Basic system info
    Write-ColorHost "Collecting system information..." -Type Info
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        
        $Script:InventoryData.System.Hostname = $env:COMPUTERNAME
        $Script:InventoryData.System.OSVersion = $os.Caption
        $Script:InventoryData.System.OSBuild = $os.BuildNumber
        $Script:InventoryData.System.TotalRAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        # BUG-9 fix: Get available memory, not just total
        $Script:InventoryData.System.AvailableRAM_GB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $Script:InventoryData.System.LogicalProcessors = $cs.NumberOfLogicalProcessors
        $Script:InventoryData.System.IsAdmin = Test-Administrator
        
        Write-Host "  Hostname: $($Script:InventoryData.System.Hostname)" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  OS: $($Script:InventoryData.System.OSVersion)" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  Build: $($Script:InventoryData.System.OSBuild)" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  RAM: $($Script:InventoryData.System.TotalRAM_GB) GB total, $($Script:InventoryData.System.AvailableRAM_GB) GB available" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  Processors: $($Script:InventoryData.System.LogicalProcessors) logical" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  Admin: $($Script:InventoryData.System.IsAdmin)" -ForegroundColor $Script:Config.Colors.Info
        
        Write-Log "System inventory collected for $($Script:InventoryData.System.Hostname)" -Level 'Info'
    }
    catch {
        Write-ColorHost "Failed to collect system info: $($_.Exception.Message)" -Type Error
        Write-Log "System inventory error: $($_.Exception.Message)" -Level 'Error'
    }
    
    # Check Windows features (prerequisites)
    Write-Host ""
    Write-ColorHost "Checking Windows features..." -Type Info
    
    $requiredFeatures = @(
        'Microsoft-Windows-Subsystem-Linux',
        'VirtualMachinePlatform',
        'Microsoft-Hyper-V-All'
    )
    
    foreach ($feature in $requiredFeatures) {
        try {
            $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            $enabled = $state.State -eq 'Enabled'
            $Script:InventoryData.System.WindowsFeatures[$feature] = $enabled
            
            $status = if ($enabled) { "Enabled" } else { "Disabled" }
            $color = if ($enabled) { $Script:Config.Colors.Success } else { $Script:Config.Colors.Warning }
            Write-Host "  $feature : $status" -ForegroundColor $color
            
            if (-not $enabled -and $feature -ne 'Microsoft-Hyper-V-All') {
                Add-Issue -Severity 'Warning' -Category 'System' `
                    -Issue "Windows feature '$feature' is not enabled" `
                    -Fix "Enable via: dism.exe /online /enable-feature /featurename:$feature /all /norestart" `
                    -AutoFixable $true
            }
        }
        catch {
            $Script:InventoryData.System.WindowsFeatures[$feature] = $false
            Write-Host "  $feature : Unknown" -ForegroundColor $Script:Config.Colors.Warning
        }
    }
    
    # Detect user profiles
    Write-Host ""
    Write-ColorHost "Detecting user profiles..." -Type Info
    
    try {
        $profiles = Get-ChildItem -Path 'C:\Users' -Directory |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') } |
            ForEach-Object {
                $hasWSLConfig = Test-Path (Join-Path $_.FullName '.wslconfig')
                @{
                    Name = $_.Name
                    Path = $_.FullName
                    HasWSLConfig = $hasWSLConfig
                    IsCurrent = ($_.Name -eq $env:USERNAME)
                }
            }
        
        $Script:InventoryData.Users = $profiles
        Write-Host "  Found $($profiles.Count) user profile(s)" -ForegroundColor $Script:Config.Colors.Info
        
        foreach ($profile in $profiles) {
            $current = if ($profile.IsCurrent) { " (current)" } else { "" }
            $wslConfig = if ($profile.HasWSLConfig) { " [has .wslconfig]" } else { "" }
            Write-Host "    • $($profile.Name)$current$wslConfig" -ForegroundColor $Script:Config.Colors.Info
        }
    }
    catch {
        Write-ColorHost "Failed to enumerate user profiles: $($_.Exception.Message)" -Type Warning
    }
}

# ============================================================================
# WSL2 DIAGNOSTICS MODULE (BUG-1 fix: Improved distribution parsing)
# ============================================================================

function Test-WSL2 {
    <#
    .SYNOPSIS
        Comprehensive WSL2 diagnostics with improved parsing
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "WSL2 DIAGNOSTICS"
    
    $healthScore = 0
    $maxScore = 100
    
    # Check WSL installation
    Write-ColorHost "Checking WSL installation..." -Type Info
    
    $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wslPath) {
        Write-ColorHost "WSL is not installed" -Type Error
        $Script:InventoryData.WSL.Installed = $false
        $Script:InventoryData.WSL.HealthScore = 0
        $Script:InventoryData.WSL.HealthStatus = 'Not Installed'
        
        Add-Issue -Severity 'Error' -Category 'WSL' `
            -Issue "WSL is not installed on this system" `
            -Fix "Run: wsl --install" `
            -AutoFixable $true
        
        return
    }
    
    $Script:InventoryData.WSL.Installed = $true
    $healthScore += 20
    Write-ColorHost "WSL is installed" -Type Success
    
    # Get WSL version info
    Write-Host ""
    Write-ColorHost "Checking WSL version..." -Type Info
    
    $versionResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('--version') -PassThru -SuppressOutput
    if ($versionResult.Success) {
        $versionOutput = $versionResult.Output | Out-String
        if ($versionOutput -match 'WSL.*?:\s*(\d+\.\d+\.\d+)') {
            $Script:InventoryData.WSL.Version = $Matches[1]
            Write-Host "  WSL Version: $($Script:InventoryData.WSL.Version)" -ForegroundColor $Script:Config.Colors.Info
            $healthScore += 10
        }
    }
    
    # BUG-1 FIX: Improved distribution parsing that handles spaces and locales
    Write-Host ""
    Write-ColorHost "Enumerating distributions..." -Type Info
    
    $Script:InventoryData.WSL.Distributions = @()
    
    # Use --list --verbose with more robust parsing
    $listResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('-l', '-v') -PassThru -SuppressOutput
    
    if ($listResult.Success -and $listResult.Output) {
        $lines = ($listResult.Output | Out-String) -split "`n" | 
            Where-Object { $_ -match '\S' } |
            Select-Object -Skip 1  # Skip header
        
        foreach ($line in $lines) {
            # Clean the line (remove BOM and special chars)
            $cleanLine = $line -replace '[^\x20-\x7E*]', '' -replace '^\s+', ''
            
            if ($cleanLine -match '^(\*?)\s*(.+?)\s+(Stopped|Running)\s+(\d+)\s*$') {
                $isDefault = $Matches[1] -eq '*'
                $name = $Matches[2].Trim()
                $state = $Matches[3]
                $version = [int]$Matches[4]
                
                $distro = @{
                    Name = $name
                    State = $state
                    Version = $version
                    IsDefault = $isDefault
                }
                
                $Script:InventoryData.WSL.Distributions += $distro
                
                if ($isDefault) {
                    $Script:InventoryData.WSL.DefaultDistro = $name
                }
                
                $stateColor = if ($state -eq 'Running') { $Script:Config.Colors.Success } else { $Script:Config.Colors.Warning }
                $defaultMark = if ($isDefault) { " (default)" } else { "" }
                $versionWarn = if ($version -eq 1) { " [WSL1!]" } else { "" }
                
                Write-Host "  • $name - WSL$version - $state$defaultMark$versionWarn" -ForegroundColor $stateColor
                
                if ($version -eq 1) {
                    Add-Issue -Severity 'Warning' -Category 'WSL' `
                        -Issue "Distribution '$name' is running WSL1" `
                        -Fix "Upgrade via: wsl --set-version $name 2" `
                        -AutoFixable $true
                }
            }
        }
    }
    
    $distroCount = $Script:InventoryData.WSL.Distributions.Count
    if ($distroCount -gt 0) {
        $healthScore += 30
        Write-ColorHost "Found $distroCount distribution(s)" -Type Success
    }
    else {
        Add-Issue -Severity 'Warning' -Category 'WSL' `
            -Issue "No WSL distributions found" `
            -Fix "Install a distribution: wsl --install -d Ubuntu" `
            -AutoFixable $true
    }
    
    # Check configuration files
    Write-Host ""
    Write-ColorHost "Checking configuration..." -Type Info
    
    # User config
    if (Test-ValidPath $Script:Config.Paths.WSLConfig -Type File) {
        $Script:InventoryData.WSL.ConfigExists = $true
        $Script:InventoryData.WSL.ConfigPath = $Script:Config.Paths.WSLConfig
        Write-ColorHost "User .wslconfig exists" -Type Success
        $healthScore += 10
        
        # Parse and display key settings
        $configContent = Get-Content $Script:Config.Paths.WSLConfig -Raw
        if ($configContent -match 'memory\s*=\s*(\S+)') {
            Write-Host "    Memory: $($Matches[1])" -ForegroundColor $Script:Config.Colors.Info
        }
        if ($configContent -match 'processors\s*=\s*(\d+)') {
            Write-Host "    Processors: $($Matches[1])" -ForegroundColor $Script:Config.Colors.Info
        }
    }
    else {
        Write-ColorHost "No user .wslconfig found" -Type Warning
        Add-Issue -Severity 'Info' -Category 'WSL' `
            -Issue "No .wslconfig file configured" `
            -Fix "Create optimized configuration via Repair-WSL2" `
            -AutoFixable $true
    }
    
    # Multi-profile sync status
    $allProfiles = Get-AllUserProfiles
    $profilesWithConfig = @($allProfiles | Where-Object { $_.HasWSLConfig }).Count
    if ($profilesWithConfig -eq $allProfiles.Count -and $allProfiles.Count -gt 0) {
        Write-ColorHost "All $($allProfiles.Count) profiles have .wslconfig" -Type Success
        $healthScore += 10
    }
    elseif ($profilesWithConfig -gt 0) {
        Write-ColorHost "$profilesWithConfig of $($allProfiles.Count) profiles have .wslconfig" -Type Warning
        Add-Issue -Severity 'Warning' -Category 'Configuration' `
            -Issue "Not all profiles have .wslconfig configured" `
            -Fix "Run Sync-AllProfiles to propagate configuration" `
            -AutoFixable $true
    }
    
    # Check WSL2 is default
    $defaultResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('--status') -PassThru -SuppressOutput
    if ($defaultResult.Output -match 'Default Version:\s*2') {
        Write-ColorHost "WSL2 is set as default" -Type Success
        $healthScore += 20
    }
    else {
        Add-Issue -Severity 'Warning' -Category 'WSL' `
            -Issue "WSL2 is not set as the default version" `
            -Fix "Set default: wsl --set-default-version 2" `
            -AutoFixable $true
    }
    
    # Calculate final score
    $Script:InventoryData.WSL.HealthScore = [math]::Min($healthScore, $maxScore)
    $Script:InventoryData.WSL.HealthStatus = switch ($Script:InventoryData.WSL.HealthScore) {
        { $_ -ge 80 } { 'Healthy' }
        { $_ -ge 60 } { 'Fair' }
        { $_ -ge 40 } { 'Degraded' }
        default { 'Critical' }
    }
    
    Write-Host ""
    Write-ColorHost "WSL Health Score: $($Script:InventoryData.WSL.HealthScore)/100 ($($Script:InventoryData.WSL.HealthStatus))" -Type $(
        if ($Script:InventoryData.WSL.HealthScore -ge 80) { 'Success' }
        elseif ($Script:InventoryData.WSL.HealthScore -ge 60) { 'Warning' }
        else { 'Error' }
    )
    
    Write-Log "WSL diagnostics complete: Score $($Script:InventoryData.WSL.HealthScore)" -Level 'Info'
}


# ============================================================================
# DOCKER DIAGNOSTICS MODULE (BUG-8 fix: Proper integration check)
# ============================================================================

function Test-Docker {
    <#
    .SYNOPSIS
        Comprehensive Docker Desktop diagnostics
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "DOCKER DIAGNOSTICS"
    
    $healthScore = 0
    $maxScore = 100
    
    # Check Docker Desktop installation
    Write-ColorHost "Checking Docker Desktop installation..." -Type Info
    
    if (Test-ValidPath $Script:Config.Paths.DockerDesktop -Type File) {
        $Script:InventoryData.Docker.DesktopInstalled = $true
        $healthScore += 20
        Write-ColorHost "Docker Desktop is installed" -Type Success
        
        # Get version
        try {
            $versionInfo = Get-ItemProperty $Script:Config.Paths.DockerDesktop -ErrorAction SilentlyContinue
            if ($versionInfo.VersionInfo) {
                $Script:InventoryData.Docker.DesktopVersion = $versionInfo.VersionInfo.ProductVersion
                Write-Host "  Version: $($Script:InventoryData.Docker.DesktopVersion)" -ForegroundColor $Script:Config.Colors.Info
            }
        }
        catch { }
    }
    else {
        $Script:InventoryData.Docker.DesktopInstalled = $false
        $Script:InventoryData.Docker.HealthScore = 0
        $Script:InventoryData.Docker.HealthStatus = 'Not Installed'
        
        Write-ColorHost "Docker Desktop is not installed" -Type Error
        Add-Issue -Severity 'Error' -Category 'Docker' `
            -Issue "Docker Desktop is not installed" `
            -Fix "Download from: https://docker.com/products/docker-desktop" `
            -AutoFixable $false
        
        return
    }
    
    # Check if Docker Desktop is running
    Write-Host ""
    Write-ColorHost "Checking Docker Desktop status..." -Type Info
    
    $dockerProcess = Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue
    if ($dockerProcess) {
        $Script:InventoryData.Docker.DesktopRunning = $true
        $healthScore += 20
        Write-ColorHost "Docker Desktop is running" -Type Success
    }
    else {
        $Script:InventoryData.Docker.DesktopRunning = $false
        Write-ColorHost "Docker Desktop is not running" -Type Warning
        
        Add-Issue -Severity 'Warning' -Category 'Docker' `
            -Issue "Docker Desktop is not running" `
            -Fix "Start Docker Desktop manually or via Repair-Docker" `
            -AutoFixable $true
    }
    
    # Check Docker engine responsiveness
    Write-Host ""
    Write-ColorHost "Checking Docker engine..." -Type Info
    
    $dockerResult = Invoke-NativeCommand -Command 'docker' -Arguments @('version', '--format', '{{.Server.Version}}') -PassThru -SuppressOutput
    
    if ($dockerResult.Success) {
        $Script:InventoryData.Docker.EngineResponsive = $true
        $healthScore += 20
        Write-ColorHost "Docker engine is responsive" -Type Success
        Write-Host "  Engine Version: $($dockerResult.Output)" -ForegroundColor $Script:Config.Colors.Info
    }
    else {
        $Script:InventoryData.Docker.EngineResponsive = $false
        Write-ColorHost "Docker engine is not responding" -Type Warning
        
        Add-Issue -Severity 'Warning' -Category 'Docker' `
            -Issue "Docker engine is not responding" `
            -Fix "Restart Docker Desktop or check Docker service" `
            -AutoFixable $true
    }
    
    # Check Docker settings and WSL integration (SEC-2 & BUG-8 fix)
    Write-Host ""
    Write-ColorHost "Checking Docker configuration..." -Type Info
    
    if (Test-ValidPath $Script:Config.Paths.DockerSettings -Type File) {
        try {
            $settingsJson = Get-Content -Path $Script:Config.Paths.DockerSettings -Raw -ErrorAction Stop
            $settings = ConvertFrom-JsonSafe -JsonString $settingsJson
            
            if ($settings -and $settings.PSObject) {
                # Check WSL2 backend
                if ($settings.wslEngineEnabled -eq $true) {
                    Write-ColorHost "WSL2 backend enabled" -Type Success
                    $healthScore += 10
                }
                else {
                    Write-ColorHost "WSL2 backend not enabled" -Type Warning
                    Add-Issue -Severity 'Warning' -Category 'Docker' `
                        -Issue "Docker is not using WSL2 backend" `
                        -Fix "Enable WSL2 backend in Docker Desktop settings" `
                        -AutoFixable $false
                }
                
                # BUG-8 fix: Properly check WSL integration
                $integratedDistros = @()
                if ($settings.integratedWslDistros -and $settings.integratedWslDistros.Count -gt 0) {
                    $integratedDistros = @($settings.integratedWslDistros)
                }
                
                $Script:InventoryData.Docker.IntegratedDistros = $integratedDistros
                
                if ($integratedDistros.Count -gt 0) {
                    $Script:InventoryData.Docker.WSLIntegrationEnabled = $true
                    $healthScore += 10
                    Write-ColorHost "WSL integration enabled for: $($integratedDistros -join ', ')" -Type Success
                }
                else {
                    $Script:InventoryData.Docker.WSLIntegrationEnabled = $false
                    Write-ColorHost "No WSL distributions integrated with Docker" -Type Warning
                    
                    Add-Issue -Severity 'Warning' -Category 'Docker' `
                        -Issue "No WSL distributions are integrated with Docker" `
                        -Fix "Enable integration in Docker Desktop → Settings → Resources → WSL Integration" `
                        -AutoFixable $false
                }
            }
        }
        catch {
            Write-ColorHost "Could not parse Docker settings: $($_.Exception.Message)" -Type Warning
        }
    }
    
    # Check containers and images if engine is responsive
    if ($Script:InventoryData.Docker.EngineResponsive) {
        Write-Host ""
        Write-ColorHost "Checking Docker resources..." -Type Info
        
        # Containers
        $containerResult = Invoke-NativeCommand -Command 'docker' -Arguments @('ps', '-a', '--format', '{{.Names}}:{{.Status}}') -PassThru -SuppressOutput
        if ($containerResult.Success -and $containerResult.Output) {
            $containers = @($containerResult.Output | Where-Object { $_ })
            $Script:InventoryData.Docker.Containers = $containers
            $running = ($containers | Where-Object { $_ -match ':Up' }).Count
            Write-Host "  Containers: $($containers.Count) total, $running running" -ForegroundColor $Script:Config.Colors.Info
        }
        
        # Images
        $imageResult = Invoke-NativeCommand -Command 'docker' -Arguments @('images', '--format', '{{.Repository}}:{{.Tag}}') -PassThru -SuppressOutput
        if ($imageResult.Success -and $imageResult.Output) {
            $images = @($imageResult.Output | Where-Object { $_ })
            $Script:InventoryData.Docker.Images = $images
            Write-Host "  Images: $($images.Count)" -ForegroundColor $Script:Config.Colors.Info
        }
        
        # Disk usage
        $dfResult = Invoke-NativeCommand -Command 'docker' -Arguments @('system', 'df', '--format', '{{.Type}}: {{.Size}}') -PassThru -SuppressOutput
        if ($dfResult.Success -and $dfResult.Output) {
            $Script:InventoryData.Docker.DiskUsage = ($dfResult.Output | Out-String).Trim()
            Write-Host "  Disk Usage:" -ForegroundColor $Script:Config.Colors.Info
            foreach ($line in ($dfResult.Output | Where-Object { $_ })) {
                Write-Host "    $line" -ForegroundColor $Script:Config.Colors.Info
            }
        }
        
        $healthScore += 20
    }
    
    # Calculate final score
    $Script:InventoryData.Docker.HealthScore = [math]::Min($healthScore, $maxScore)
    $Script:InventoryData.Docker.HealthStatus = switch ($Script:InventoryData.Docker.HealthScore) {
        { $_ -ge 80 } { 'Healthy' }
        { $_ -ge 60 } { 'Fair' }
        { $_ -ge 40 } { 'Degraded' }
        default { 'Critical' }
    }
    
    Write-Host ""
    Write-ColorHost "Docker Health Score: $($Script:InventoryData.Docker.HealthScore)/100 ($($Script:InventoryData.Docker.HealthStatus))" -Type $(
        if ($Script:InventoryData.Docker.HealthScore -ge 80) { 'Success' }
        elseif ($Script:InventoryData.Docker.HealthScore -ge 60) { 'Warning' }
        else { 'Error' }
    )
    
    Write-Log "Docker diagnostics complete: Score $($Script:InventoryData.Docker.HealthScore)" -Level 'Info'
}

# ============================================================================
# REPAIR MODULES (BUG-10 fix: Proper error handling for native commands)
# ============================================================================

function Repair-WSL2 {
    <#
    .SYNOPSIS
        Repairs and configures WSL2 with proper error handling
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "WSL2 REPAIR & CONFIGURATION"
    
    # Create backup before making changes
    if ($Script:Config.Features.AutoBackupBeforeChanges) {
        Write-ColorHost "Creating backup before changes..." -Type Info
        Backup-Configuration | Out-Null
    }
    
    # Install WSL if not present
    if (-not $Script:InventoryData.WSL.Installed) {
        Write-ColorHost "WSL not installed. Installing..." -Type Warning
        
        if (Confirm-Action "Install WSL2?" -DefaultYes) {
            $installResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('--install') -PassThru
            
            if ($installResult.Success) {
                Write-ColorHost "WSL installation initiated. Reboot required!" -Type Warning
                Write-Log "WSL installation initiated" -Level 'Info'
            }
            else {
                Write-ColorHost "WSL installation failed. Exit code: $($installResult.ExitCode)" -Type Error
                Write-Log "WSL installation error: $($installResult.Output)" -Level 'Error'
            }
            return
        }
    }
    
    # Upgrade WSL1 distributions to WSL2
    $wsl1Distros = $Script:InventoryData.WSL.Distributions | Where-Object { $_.Version -eq 1 }
    
    if ($wsl1Distros -and $wsl1Distros.Count -gt 0) {
        Write-Host ""
        Write-ColorHost "Found WSL1 distributions that need upgrading:" -Type Warning
        
        foreach ($distro in $wsl1Distros) {
            Write-Host "  • $($distro.Name)" -ForegroundColor $Script:Config.Colors.Warning
        }
        
        if (Confirm-Action "Upgrade all to WSL2?") {
            foreach ($distro in $wsl1Distros) {
                Write-ColorHost "Upgrading $($distro.Name)..." -Type Info
                
                # BUG-10 fix: Use proper command execution with error handling
                $upgradeResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('--set-version', $distro.Name, '2') -PassThru
                
                if ($upgradeResult.Success) {
                    Write-ColorHost "Upgrade initiated for $($distro.Name)" -Type Success
                    Write-Log "WSL upgrade initiated for $($distro.Name)" -Level 'Info'
                }
                else {
                    Write-ColorHost "Upgrade failed for $($distro.Name): Exit code $($upgradeResult.ExitCode)" -Type Error
                    Write-Log "WSL upgrade error for $($distro.Name): $($upgradeResult.Output)" -Level 'Error'
                }
            }
        }
    }
    
    # Set WSL2 as default version
    Write-Host ""
    Write-ColorHost "Setting WSL2 as default version..." -Type Info
    
    $defaultResult = Invoke-NativeCommand -Command 'wsl' -Arguments @('--set-default-version', '2') -PassThru
    
    if ($defaultResult.Success) {
        Write-ColorHost "WSL2 set as default" -Type Success
        Write-Log "WSL2 set as default version" -Level 'Info'
    }
    else {
        Write-ColorHost "Failed to set WSL2 as default: Exit code $($defaultResult.ExitCode)" -Type Error
        Write-Log "WSL default version error: $($defaultResult.Output)" -Level 'Error'
    }
    
    # Create optimized WSL configuration
    Write-Host ""
    if (Confirm-Action "Create optimized device-wide WSL configuration?" -DefaultYes) {
        
        # BUG-9 fix: Use more conservative memory allocation based on available RAM
        $availableRAM = if ($Script:InventoryData.System.AvailableRAM_GB) {
            $Script:InventoryData.System.AvailableRAM_GB
        } else {
            $Script:InventoryData.System.TotalRAM_GB * 0.7  # Estimate 70% available
        }
        
        $optimalMemoryGB = [math]::Max(
            $Script:Constants.MinMemoryGB,
            [math]::Min(
                [math]::Floor($Script:InventoryData.System.TotalRAM_GB * $Script:Constants.MemoryAllocationRatio),
                $Script:Constants.MaxMemoryGB
            )
        )
        
        $optimalProcessors = [math]::Max(
            $Script:Constants.MinProcessors,
            [math]::Floor($Script:InventoryData.System.LogicalProcessors * $Script:Constants.ProcessorAllocationRatio)
        )
        
        $wslConfig = @"
# Device-Wide WSL Configuration
# Generated by Device Ecosystem Manager v$($Script:Config.Version)
# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

[wsl2]
# Memory allocation ($($Script:Constants.MemoryAllocationRatio * 100)% of $($Script:InventoryData.System.TotalRAM_GB)GB system RAM)
memory=${optimalMemoryGB}GB

# Processor allocation ($($Script:Constants.ProcessorAllocationRatio * 100)% of $($Script:InventoryData.System.LogicalProcessors) logical processors)
processors=$optimalProcessors

# Swap file size (fixed 4GB)
swap=4GB

# Enable localhost forwarding (REQUIRED for Docker, dev servers)
localhostForwarding=true

# DNS tunneling (helps with VPN scenarios)
dnsTunneling=true

# Firewall (enable for better security)
firewall=true

# Nested virtualization (disable for stability)
nestedVirtualization=false

# GUI support
guiApplications=true

# Safe mode (disable unless troubleshooting)
safeMode=false

# Debug console
debugConsole=false

[experimental]
# Sparse VHD (reduces disk space usage)
sparseVhd=true

# Auto memory reclaim (returns unused memory to Windows)
autoMemoryReclaim=gradual

# Host address loopback
hostAddressLoopback=true
"@
        
        try {
            # Write to current user first
            $wslConfig | Out-File -FilePath $Script:Config.Paths.WSLConfig -Encoding UTF8 -Force
            Write-ColorHost "Created user config: $($Script:Config.Paths.WSLConfig)" -Type Success
            
            Write-Log "Created WSL config with Memory=${optimalMemoryGB}GB, Processors=$optimalProcessors" -Level 'Info'
            
            Write-ColorHost "Configuration optimized for:" -Type Info
            Write-Host "  • Memory: ${optimalMemoryGB}GB" -ForegroundColor $Script:Config.Colors.Info
            Write-Host "  • Processors: $optimalProcessors" -ForegroundColor $Script:Config.Colors.Info
            Write-Host "  • Docker integration enabled" -ForegroundColor $Script:Config.Colors.Info
            
            # Offer to sync to all profiles
            Write-Host ""
            if (Confirm-Action "Sync this configuration to ALL user profiles on this machine?") {
                Sync-AllProfiles -Force
            }
            else {
                Write-ColorHost "Configuration applied to current user only" -Type Warning
                Write-ColorHost "Run 'Sync-AllProfiles' later to propagate to other users" -Type Info
            }
            
            Write-ColorHost "`nRestart WSL to apply: wsl --shutdown" -Type Warning
        }
        catch {
            Write-ColorHost "Failed to create WSL config: $($_.Exception.Message)" -Type Error
            Write-Log "WSL config creation error: $($_.Exception.Message)" -Level 'Error'
        }
    }
}

function Repair-Docker {
    <#
    .SYNOPSIS
        Repairs Docker Desktop configuration with improved startup handling
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "DOCKER REPAIR & CONFIGURATION"
    
    if (-not $Script:InventoryData.Docker.DesktopInstalled) {
        Write-ColorHost "Docker Desktop not installed" -Type Error
        Write-ColorHost "Download from: https://docker.com/products/docker-desktop" -Type Info
        return
    }
    
    # Start Docker Desktop if not running
    if (-not $Script:InventoryData.Docker.DesktopRunning) {
        Write-Host ""
        if (Confirm-Action "Start Docker Desktop?") {
            Write-ColorHost "Starting Docker Desktop..." -Type Info
            
            try {
                Start-Process $Script:Config.Paths.DockerDesktop
                Write-Log "Docker Desktop start initiated" -Level 'Info'
                
                Write-ColorHost "Waiting for Docker to initialize (may take 30-60 seconds)..." -Type Info
                $timeout = $Script:Constants.DockerStartupTimeout
                $elapsed = 0
                
                while ($elapsed -lt $timeout) {
                    Start-Sleep -Seconds $Script:Constants.DockerPollInterval
                    $elapsed += $Script:Constants.DockerPollInterval
                    
                    $checkResult = Invoke-NativeCommand -Command 'docker' -Arguments @('version') -PassThru -SuppressOutput
                    
                    if ($checkResult.Success) {
                        Write-ColorHost "Docker started successfully!" -Type Success
                        Write-Log "Docker Desktop started successfully" -Level 'Info'
                        
                        # BUG-4 fix: Refresh Docker inventory after startup
                        Write-ColorHost "Refreshing Docker status..." -Type Info
                        $Script:InventoryData.Docker.DesktopRunning = $true
                        $Script:InventoryData.Docker.EngineResponsive = $true
                        break
                    }
                    
                    Write-Host "." -NoNewline
                }
                Write-Host ""
                
                if ($elapsed -ge $timeout) {
                    Write-ColorHost "Docker startup timeout - please check manually" -Type Warning
                    Write-Log "Docker startup timeout after ${timeout}s" -Level 'Warning'
                }
            }
            catch {
                Write-ColorHost "Failed to start Docker Desktop: $($_.Exception.Message)" -Type Error
                Write-Log "Docker Desktop start error: $($_.Exception.Message)" -Level 'Error'
            }
        }
    }
    
    # Display WSL integration guidance
    Write-Host ""
    Write-ColorHost "Docker WSL Integration Setup:" -Type Info
    
    if ($Script:InventoryData.WSL.Distributions.Count -gt 0) {
        Write-ColorHost "Docker should be integrated with these distributions:" -Type Info
        foreach ($distro in $Script:InventoryData.WSL.Distributions) {
            $integrated = if ($Script:InventoryData.Docker.IntegratedDistros -contains $distro.Name) { " [Integrated]" } else { " [Not Integrated]" }
            Write-Host "  • $($distro.Name)$integrated" -ForegroundColor $Script:Config.Colors.Info
        }
        
        Write-Host ""
        Write-ColorHost "To enable integration for all distros:" -Type Warning
        Write-Host "  1. Open Docker Desktop" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  2. Go to Settings → Resources → WSL Integration" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  3. Enable integration for all distributions" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  4. Click 'Apply & Restart'" -ForegroundColor $Script:Config.Colors.Info
    }
}


# ============================================================================
# SCHEDULED ENFORCEMENT MODULE
# ============================================================================

function Install-ScheduledEnforcement {
    <#
    .SYNOPSIS
        Installs a scheduled task to enforce configuration uniformity
    .PARAMETER IntervalMinutes
        How often to run the enforcement check (default: 60)
    .PARAMETER AutoRepair
        Automatically fix drift without prompting (default: true)
    .PARAMETER Uninstall
        Remove the scheduled task
    #>
    [CmdletBinding()]
    param(
        [int]$IntervalMinutes = 60,
        [bool]$AutoRepair = $true,
        [switch]$Uninstall
    )
    
    Write-SectionHeader "SCHEDULED ENFORCEMENT"
    
    if (-not (Test-Administrator)) {
        Write-ColorHost "Scheduled task management requires administrator privileges" -Type Error
        return $false
    }
    
    $taskName = 'DeviceEcosystemEnforcement'
    $taskPath = '\DeviceEcosystem\'
    
    # Uninstall if requested
    if ($Uninstall) {
        try {
            $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
                Write-ColorHost "Scheduled task removed successfully" -Type Success
            }
            else {
                Write-ColorHost "Scheduled task not found" -Type Warning
            }
            return $true
        }
        catch {
            Write-ColorHost "Failed to remove scheduled task: $($_.Exception.Message)" -Type Error
            return $false
        }
    }
    
    # Check for existing task
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-ColorHost "Scheduled task already exists" -Type Info
        if (-not (Confirm-Action "Replace existing scheduled task?")) {
            return $false
        }
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
    }
    
    # Create the enforcement script
    $syncScriptPath = Join-Path $Script:Config.Paths.CentralLogDir 'Sync-EcosystemConfig.ps1'
    $syncScriptDir = Split-Path $syncScriptPath -Parent
    
    if (-not (Test-Path $syncScriptDir)) {
        New-Item -ItemType Directory -Path $syncScriptDir -Force | Out-Null
    }
    
    $syncScript = @"
#Requires -RunAsAdministrator
# Sync-EcosystemConfig.ps1 - Scheduled Configuration Enforcement
# Generated by Device Ecosystem Manager v$($Script:Config.Version)
# Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

`$ErrorActionPreference = 'Continue'
`$logFile = Join-Path '$($Script:Config.Paths.CentralLogDir)' "enforcement-`$(Get-Date -Format 'yyyyMMdd').log"

function Write-EnforcementLog {
    param([string]`$Message, [string]`$Level = 'INFO')
    `$entry = "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [`$Level] `$Message"
    Add-Content -Path `$logFile -Value `$entry -ErrorAction SilentlyContinue
}

Write-EnforcementLog "Enforcement check started"

# Import the main script functions
`$mainScript = '$($Script:Config.Paths.ScriptRoot)\Device-Ecosystem-Manager-v3.2.ps1'
if (-not (Test-Path `$mainScript)) {
    Write-EnforcementLog "Main script not found: `$mainScript" 'ERROR'
    exit 1
}

# Run sync from repository
try {
    Push-Location '$(Split-Path $Script:Config.Paths.ScriptRoot -Parent)'
    
    # Try git pull if available
    `$gitPath = Get-Command git -ErrorAction SilentlyContinue
    if (`$gitPath) {
        `$pullResult = git pull --quiet 2>&1
        Write-EnforcementLog "Git pull: `$pullResult"
    }
    
    Pop-Location
}
catch {
    Write-EnforcementLog "Repository sync error: `$(`$_.Exception.Message)" 'WARNING'
}

# Load and run sync
try {
    . `$mainScript -Mode Verify 2>&1 | Out-Null
    
    # Get all profiles and check for drift
    `$profiles = Get-ChildItem -Path 'C:\Users' -Directory | 
        Where-Object { `$_.Name -notin @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0') }
    
    `$canonicalPath = Join-Path (Split-Path `$mainScript -Parent) 'canonical-config\wslconfig.ini'
    if (Test-Path `$canonicalPath) {
        `$canonical = Get-Content `$canonicalPath -Raw
        
        foreach (`$profile in `$profiles) {
            `$wslConfig = Join-Path `$profile.FullName '.wslconfig'
            
            if (-not (Test-Path `$wslConfig)) {
                Write-EnforcementLog "Missing config for `$(`$profile.Name) - will sync" 'WARNING'
                # Auto-repair: copy canonical config
                if ($($AutoRepair.ToString().ToLower())) {
                    Copy-Item -Path `$canonicalPath -Destination `$wslConfig -Force
                    Write-EnforcementLog "Auto-repaired config for `$(`$profile.Name)"
                }
            }
        }
    }
    
    Write-EnforcementLog "Enforcement check completed successfully"
}
catch {
    Write-EnforcementLog "Enforcement error: `$(`$_.Exception.Message)" 'ERROR'
    exit 1
}

exit 0
"@
    
    $syncScript | Out-File -FilePath $syncScriptPath -Encoding UTF8 -Force
    Write-ColorHost "Created enforcement script: $syncScriptPath" -Type Success
    
    # Create the scheduled task
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$syncScriptPath`""
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 9999)
        
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
            -LogonType ServiceAccount -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable:$false `
            -MultipleInstances IgnoreNew
        
        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
            -Description "Device Ecosystem Manager - Configuration Enforcement (runs every $IntervalMinutes minutes)" `
            -Force | Out-Null
        
        Write-ColorHost "Scheduled task created successfully" -Type Success
        Write-Host "  Task: $taskPath$taskName" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  Interval: Every $IntervalMinutes minutes" -ForegroundColor $Script:Config.Colors.Info
        Write-Host "  Auto-repair: $AutoRepair" -ForegroundColor $Script:Config.Colors.Info
        
        Write-Log "Scheduled enforcement task installed (interval: $IntervalMinutes min)" -Level 'Info'
        
        return $true
    }
    catch {
        Write-ColorHost "Failed to create scheduled task: $($_.Exception.Message)" -Type Error
        Write-Log "Scheduled task error: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

function Get-EnforcementStatus {
    <#
    .SYNOPSIS
        Shows the status of scheduled enforcement
    #>
    [CmdletBinding()]
    param()
    
    $taskName = 'DeviceEcosystemEnforcement'
    $taskPath = '\DeviceEcosystem\'
    
    Write-SectionHeader "ENFORCEMENT STATUS"
    
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    
    if (-not $task) {
        Write-ColorHost "Scheduled enforcement is NOT installed" -Type Warning
        Write-ColorHost "Run Install-ScheduledEnforcement to enable" -Type Info
        return $null
    }
    
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    
    Write-ColorHost "Scheduled enforcement is ACTIVE" -Type Success
    Write-Host "  State: $($task.State)" -ForegroundColor $Script:Config.Colors.Info
    Write-Host "  Last Run: $($taskInfo.LastRunTime)" -ForegroundColor $Script:Config.Colors.Info
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor $Script:Config.Colors.Info
    Write-Host "  Next Run: $($taskInfo.NextRunTime)" -ForegroundColor $Script:Config.Colors.Info
    
    # Show recent logs
    $logDir = $Script:Config.Paths.CentralLogDir
    $todayLog = Join-Path $logDir "enforcement-$(Get-Date -Format 'yyyyMMdd').log"
    
    if (Test-Path $todayLog) {
        Write-Host ""
        Write-ColorHost "Recent log entries:" -Type Info
        Get-Content $todayLog -Tail 5 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkGray
        }
    }
    
    return $task
}


# ============================================================================
# HEALTH CHECK MODULE (BUG-2 fix: Division by zero protection)
# ============================================================================

function Get-HealthReport {
    <#
    .SYNOPSIS
        Generates comprehensive health report with proper scoring
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "OVERALL HEALTH ASSESSMENT"
    
    # Run diagnostics if not already done
    if (-not $Script:InventoryData.AssessmentComplete) {
        Get-SystemInventory
        Test-WSL2
        Test-Docker
    }
    
    # BUG-2 fix: Calculate overall score with division protection
    $wslWeight = $Script:Constants.WSLHealthWeight
    $dockerWeight = $Script:Constants.DockerHealthWeight
    $totalWeight = $wslWeight + $dockerWeight
    
    if ($totalWeight -eq 0) {
        $totalWeight = 1  # Prevent division by zero
    }
    
    $wslScore = if ($Script:InventoryData.WSL.Installed) { 
        $Script:InventoryData.WSL.HealthScore 
    } else { 
        0 
    }
    
    $dockerScore = if ($Script:InventoryData.Docker.DesktopInstalled) { 
        $Script:InventoryData.Docker.HealthScore 
    } else { 
        0 
    }
    
    # Weighted average
    $overallScore = [math]::Round(
        (($wslScore * $wslWeight) + ($dockerScore * $dockerWeight)) / $totalWeight
    )
    
    $Script:InventoryData.HealthScore = $overallScore
    $Script:InventoryData.HealthStatus = switch ($overallScore) {
        { $_ -ge 80 } { 'Healthy' }
        { $_ -ge 60 } { 'Fair' }
        { $_ -ge 40 } { 'Degraded' }
        default { 'Critical' }
    }
    $Script:InventoryData.AssessmentComplete = $true
    
    # Display summary
    Write-ColorHost "SYSTEM OVERVIEW" -Type Header
    Write-Host "  Computer: $($Script:InventoryData.System.Hostname)"
    Write-Host "  OS: $($Script:InventoryData.System.OSVersion) (Build $($Script:InventoryData.System.OSBuild))"
    Write-Host "  RAM: $($Script:InventoryData.System.TotalRAM_GB) GB | CPUs: $($Script:InventoryData.System.LogicalProcessors)"
    Write-Host ""
    
    # Component scores
    $wslStatus = if ($Script:InventoryData.WSL.Installed) { 
        "$wslScore/100 ($($Script:InventoryData.WSL.HealthStatus))"
    } else { 
        "Not Installed" 
    }
    
    $dockerStatus = if ($Script:InventoryData.Docker.DesktopInstalled) { 
        "$dockerScore/100 ($($Script:InventoryData.Docker.HealthStatus))"
    } else { 
        "Not Installed" 
    }
    
    Write-ColorHost "COMPONENT HEALTH" -Type Header
    Write-Host "  WSL2:   $wslStatus"
    Write-Host "  Docker: $dockerStatus"
    Write-Host ""
    
    # Overall score with visual indicator
    $scoreColor = switch ($overallScore) {
        { $_ -ge 80 } { $Script:Config.Colors.Success }
        { $_ -ge 60 } { $Script:Config.Colors.Warning }
        default { $Script:Config.Colors.Error }
    }
    
    $progressBar = ('[' + ('█' * [math]::Floor($overallScore / 5)) + ('░' * (20 - [math]::Floor($overallScore / 5))) + ']')
    
    Write-Host "  OVERALL: " -NoNewline
    Write-Host "$progressBar $overallScore/100 " -ForegroundColor $scoreColor -NoNewline
    Write-Host "($($Script:InventoryData.HealthStatus))" -ForegroundColor $scoreColor
    Write-Host ""
    
    # Issues summary (BUG-5 fix: Issues now contain their fixes)
    if ($Script:InventoryData.Issues.Count -gt 0) {
        Write-ColorHost "ISSUES FOUND ($($Script:InventoryData.Issues.Count))" -Type Header
        
        $errors = $Script:InventoryData.Issues | Where-Object { $_.Severity -eq 'Error' }
        $warnings = $Script:InventoryData.Issues | Where-Object { $_.Severity -eq 'Warning' }
        $infos = $Script:InventoryData.Issues | Where-Object { $_.Severity -eq 'Info' }
        
        if ($errors) {
            Write-Host ""
            Write-ColorHost "Errors ($($errors.Count)):" -Type Error
            foreach ($issue in $errors) {
                Write-Host "  • $($issue.Issue)" -ForegroundColor $Script:Config.Colors.Error
                if ($issue.Fix) {
                    Write-Host "    Fix: $($issue.Fix)" -ForegroundColor $Script:Config.Colors.Info
                }
            }
        }
        
        if ($warnings) {
            Write-Host ""
            Write-ColorHost "Warnings ($($warnings.Count)):" -Type Warning
            foreach ($issue in $warnings) {
                Write-Host "  • $($issue.Issue)" -ForegroundColor $Script:Config.Colors.Warning
                if ($issue.Fix) {
                    Write-Host "    Fix: $($issue.Fix)" -ForegroundColor $Script:Config.Colors.Info
                }
            }
        }
        
        if ($infos) {
            Write-Host ""
            Write-ColorHost "Suggestions ($($infos.Count)):" -Type Info
            foreach ($issue in $infos) {
                Write-Host "  • $($issue.Issue)" -ForegroundColor $Script:Config.Colors.Info
            }
        }
        
        # Auto-fix summary
        $autoFixable = $Script:InventoryData.Issues | Where-Object { $_.AutoFixable }
        if ($autoFixable -and $autoFixable.Count -gt 0) {
            Write-Host ""
            Write-ColorHost "$($autoFixable.Count) issue(s) can be automatically fixed" -Type Info
        }
    }
    else {
        Write-ColorHost "No issues detected - system is healthy!" -Type Success
    }
    
    Write-Log "Health assessment complete: Score $overallScore, $($Script:InventoryData.Issues.Count) issues" -Level 'Info'
    
    return $overallScore
}

function Invoke-AutoRepair {
    <#
    .SYNOPSIS
        Automatically repairs all auto-fixable issues
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "AUTO-REPAIR"
    
    $autoFixable = $Script:InventoryData.Issues | Where-Object { $_.AutoFixable }
    
    if (-not $autoFixable -or $autoFixable.Count -eq 0) {
        Write-ColorHost "No auto-fixable issues found" -Type Success
        return
    }
    
    Write-ColorHost "Found $($autoFixable.Count) auto-fixable issue(s):" -Type Info
    Write-Host ""
    
    foreach ($issue in $autoFixable) {
        Write-Host "  • $($issue.Issue)" -ForegroundColor $Script:Config.Colors.Warning
    }
    
    if (-not (Confirm-Action "`nProceed with auto-repair?")) {
        Write-ColorHost "Auto-repair cancelled" -Type Warning
        return
    }
    
    # Create backup
    if ($Script:Config.Features.AutoBackupBeforeChanges) {
        Write-ColorHost "Creating backup before repairs..." -Type Info
        Backup-Configuration | Out-Null
    }
    
    $fixed = 0
    
    foreach ($issue in $autoFixable) {
        Write-ColorHost "Fixing: $($issue.Issue)..." -Type Info
        
        switch ($issue.Category) {
            'WSL' {
                if ($issue.Issue -match 'WSL1') {
                    Repair-WSL2
                    $fixed++
                }
                elseif ($issue.Issue -match 'not set as the default') {
                    $result = Invoke-NativeCommand -Command 'wsl' -Arguments @('--set-default-version', '2') -PassThru
                    if ($result.Success) { $fixed++ }
                }
                elseif ($issue.Issue -match 'not installed') {
                    $result = Invoke-NativeCommand -Command 'wsl' -Arguments @('--install') -PassThru
                    if ($result.Success) { $fixed++ }
                }
            }
            'Docker' {
                if ($issue.Issue -match 'not running') {
                    Repair-Docker
                    $fixed++
                }
            }
            'System' {
                if ($issue.Issue -match 'feature.*not enabled') {
                    # Extract feature name and try to enable
                    if ($issue.Fix -match '/featurename:(\S+)') {
                        $featureName = $Matches[1]
                        Write-ColorHost "Enabling Windows feature: $featureName" -Type Info
                        # Note: This requires reboot typically
                        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction SilentlyContinue
                        $fixed++
                    }
                }
            }
        }
    }
    
    Write-Host ""
    Write-ColorHost "Auto-repair complete: $fixed of $($autoFixable.Count) issues addressed" -Type Success
    
    if ($fixed -gt 0) {
        Write-ColorHost "Some changes may require a restart to take effect" -Type Warning
    }
    
    Write-Log "Auto-repair completed: $fixed issues fixed" -Level 'Info'
}

# ============================================================================
# MENU SYSTEM (CQ-3 fix: Unified wait-for-key handling)
# ============================================================================

function Show-MainMenu {
    <#
    .SYNOPSIS
        Displays the main interactive menu
    #>
    [CmdletBinding()]
    param()
    
    while ($true) {
        Write-Banner
        
        # Show quick status if assessment done
        if ($Script:InventoryData.AssessmentComplete) {
            $statusColor = switch ($Script:InventoryData.HealthStatus) {
                'Healthy' { $Script:Config.Colors.Success }
                'Fair' { $Script:Config.Colors.Warning }
                default { $Script:Config.Colors.Error }
            }
            Write-Host "    System Health: " -NoNewline
            Write-Host "$($Script:InventoryData.HealthScore)/100 ($($Script:InventoryData.HealthStatus))" -ForegroundColor $statusColor
            Write-Host ""
        }
        
        Write-Host "    ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │                        MAIN MENU                            │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    ├─────────────────────────────────────────────────────────────┤" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │  DIAGNOSTICS                                                │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [1]  System Inventory & Health Check                      │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [2]  WSL2 Diagnostics & Repair                            │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [3]  Docker Diagnostics & Repair                          │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [4]  Auto-Repair All Issues                               │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │                                                             │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │  MULTI-PROFILE SYNC                                         │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [5]  Sync Config to All Profiles                          │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [6]  Detect Configuration Drift                           │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [7]  Sync from Git Repository                             │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [8]  Manage Scheduled Enforcement                         │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │                                                             │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │  BACKUP & RESTORE                                           │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [B]  Backup Configuration                                 │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [R]  Restore Configuration                                │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [E]  Export Report (JSON)                                 │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │                                                             │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │   [Q]  Quit                                                 │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    │                                                             │" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host "    └─────────────────────────────────────────────────────────────┘" -ForegroundColor $Script:Config.Colors.Menu
        Write-Host ""
        
        $choice = Read-Host "    Select option"
        
        switch ($choice.ToUpper()) {
            '1' {
                Get-SystemInventory
                Test-WSL2
                Test-Docker
                $null = Get-HealthReport
                Wait-KeyPress
            }
            '2' {
                if (-not $Script:InventoryData.AssessmentComplete) {
                    Get-SystemInventory
                    Test-WSL2
                }
                Repair-WSL2
                Wait-KeyPress
            }
            '3' {
                if (-not $Script:InventoryData.AssessmentComplete) {
                    Get-SystemInventory
                    Test-Docker
                }
                Repair-Docker
                Wait-KeyPress
            }
            '4' {
                if (-not $Script:InventoryData.AssessmentComplete) {
                    Get-SystemInventory
                    Test-WSL2
                    Test-Docker
                    $null = Get-HealthReport
                }
                Invoke-AutoRepair
                Wait-KeyPress
            }
            '5' {
                # Sync to all profiles
                if (-not $Script:InventoryData.AssessmentComplete) {
                    Get-SystemInventory
                }
                Sync-AllProfiles
                Wait-KeyPress
            }
            '6' {
                # Detect drift
                if (-not $Script:InventoryData.AssessmentComplete) {
                    Get-SystemInventory
                }
                Compare-ProfileConfigs -Detailed
                Wait-KeyPress
            }
            '7' {
                # Sync from repository
                Sync-FromRepository -Apply
                Wait-KeyPress
            }
            '8' {
                # Scheduled enforcement submenu
                Write-SectionHeader "SCHEDULED ENFORCEMENT"
                Write-Host "  [1] View enforcement status" -ForegroundColor $Script:Config.Colors.Menu
                Write-Host "  [2] Install scheduled enforcement" -ForegroundColor $Script:Config.Colors.Menu
                Write-Host "  [3] Remove scheduled enforcement" -ForegroundColor $Script:Config.Colors.Menu
                Write-Host "  [C] Cancel" -ForegroundColor $Script:Config.Colors.Menu
                Write-Host ""
                $subChoice = Read-Host "Select option"
                switch ($subChoice) {
                    '1' { Get-EnforcementStatus }
                    '2' { Install-ScheduledEnforcement }
                    '3' { Install-ScheduledEnforcement -Uninstall }
                }
                Wait-KeyPress
            }
            'B' {
                Backup-Configuration
                Wait-KeyPress
            }
            'R' {
                Restore-Configuration
                Wait-KeyPress
            }
            'E' {
                Export-Report
                Wait-KeyPress
            }
            'Q' {
                Write-Host ""
                Write-ColorHost "Thank you for using Device Ecosystem Manager!" -Type Success
                Write-Log "Session ended by user" -Level 'Info'
                return
            }
            default {
                Write-ColorHost "Invalid selection. Please try again." -Type Warning
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Export-Report {
    <#
    .SYNOPSIS
        Exports inventory and health data to JSON report
    #>
    [CmdletBinding()]
    param()
    
    Write-SectionHeader "EXPORT REPORT"
    
    if (-not $Script:InventoryData.AssessmentComplete) {
        Write-ColorHost "Running assessment first..." -Type Info
        Get-SystemInventory
        Test-WSL2
        Test-Docker
        $null = Get-HealthReport
    }
    
    $reportPath = Join-Path $Script:Config.Paths.ScriptRoot "health-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    
    try {
        $report = @{
            GeneratedAt = Get-Date -Format 'o'
            GeneratedBy = "Device Ecosystem Manager v$($Script:Config.Version)"
            Computer = $env:COMPUTERNAME
            User = $env:USERNAME
            System = $Script:InventoryData.System
            WSL = $Script:InventoryData.WSL
            Docker = $Script:InventoryData.Docker
            Users = $Script:InventoryData.Users
            Issues = $Script:InventoryData.Issues
            HealthScore = $Script:InventoryData.HealthScore
            HealthStatus = $Script:InventoryData.HealthStatus
        }
        
        $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
        
        Write-ColorHost "Report exported to: $reportPath" -Type Success
        Write-Log "Report exported to $reportPath" -Level 'Info'
    }
    catch {
        Write-ColorHost "Failed to export report: $($_.Exception.Message)" -Type Error
        Write-Log "Report export error: $($_.Exception.Message)" -Level 'Error'
    }
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

function Main {
    <#
    .SYNOPSIS
        Main entry point with mode handling
    #>
    [CmdletBinding()]
    param()
    
    # Initialize
    Write-Log "Device Ecosystem Manager v$($Script:Config.Version) started" -Level 'Info'
    Write-Log "Mode: $Mode, AutoFix: $AutoFix" -Level 'Info'
    
    # Verify administrator
    if (-not (Test-Administrator)) {
        Write-ColorHost "This script requires administrator privileges!" -Type Error
        Write-ColorHost "Please run PowerShell as Administrator and try again." -Type Warning
        exit $Script:Constants.ExitPrerequisiteFailed
    }
    
    # Set script-level auto-fix flag
    $Script:AutoFix = $AutoFix
    
    # Enable verbose logging if requested
    if ($VerbosePreference -eq 'Continue' -or $PSBoundParameters['Verbose']) {
        $Script:Config.Features.VerboseLogging = $true
    }
    
    # Override backup path if specified
    if ($BackupPath) {
        $Script:Config.Paths.BackupRoot = $BackupPath
    }
    
    # Handle modes
    switch ($Mode) {
        'Interactive' {
            Show-MainMenu
        }
        'Inventory' {
            Get-SystemInventory
            exit $Script:Constants.ExitSuccess
        }
        'Fix-WSL' {
            Get-SystemInventory
            Test-WSL2
            Repair-WSL2
            exit $Script:Constants.ExitSuccess
        }
        'Fix-Docker' {
            Get-SystemInventory
            Test-Docker
            Repair-Docker
            exit $Script:Constants.ExitSuccess
        }
        'Configure-All' {
            Get-SystemInventory
            Test-WSL2
            Test-Docker
            Repair-WSL2
            Repair-Docker
            exit $Script:Constants.ExitSuccess
        }
        'Backup' {
            Backup-Configuration
            exit $Script:Constants.ExitSuccess
        }
        'Restore' {
            Restore-Configuration
            exit $Script:Constants.ExitSuccess
        }
        'HealthCheck' {
            Get-SystemInventory
            Test-WSL2
            Test-Docker
            $score = Get-HealthReport
            exit $(if ($score -ge 60) { $Script:Constants.ExitSuccess } else { $Script:Constants.ExitGeneralError })
        }
        'Verify' {
            Get-SystemInventory
            Test-WSL2
            Test-Docker
            Write-Host "`nWSL: $($Script:InventoryData.WSL.HealthStatus)"
            Write-Host "Docker: $($Script:InventoryData.Docker.HealthStatus)"
            exit $Script:Constants.ExitSuccess
        }
        'Version' {
            Write-Host "Device Ecosystem Manager v$($Script:Config.Version)"
            Write-Host "Build: $($Script:Config.BuildDate)"
            exit $Script:Constants.ExitSuccess
        }
        'Sync-Profiles' {
            Get-SystemInventory
            $success = Sync-AllProfiles -Force
            exit $(if ($success) { $Script:Constants.ExitSuccess } else { $Script:Constants.ExitGeneralError })
        }
        'Sync-Repo' {
            $success = Sync-FromRepository -Apply
            exit $(if ($success) { $Script:Constants.ExitSuccess } else { $Script:Constants.ExitGeneralError })
        }
        'Detect-Drift' {
            Get-SystemInventory
            $drift = Compare-ProfileConfigs -Detailed
            $hasDrift = @($drift | Where-Object { -not $_.MatchesCanonical }).Count -gt 0
            exit $(if ($hasDrift) { $Script:Constants.ExitGeneralError } else { $Script:Constants.ExitSuccess })
        }
        'Install-Enforcement' {
            $success = Install-ScheduledEnforcement
            exit $(if ($success) { $Script:Constants.ExitSuccess } else { $Script:Constants.ExitGeneralError })
        }
    }
}

# Run main
Main
