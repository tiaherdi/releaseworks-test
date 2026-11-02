<#
.SYNOPSIS
    Backs up, stops, replaces and restarts an application on the server this script runs on.

.DESCRIPTION
    Meant to run on a self-hosted runner installed on the target server, so no remote
    credentials are needed. Steps: backup -> stop -> copy -> start.
    Sets the pipeline output "backup_path" (empty for a new app) for rollback.ps1.

.EXAMPLE
    .\deploy.ps1 -SourcePath C:\runner\_temp\app -TargetPath D:\Apps\SampleApi `
        -BackupRoot D:\Backups\SampleApi -AppType service -AppName SampleApi
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    # Empty = no backup (new app)
    [string]$BackupRoot = '',
    [ValidateSet('none', 'iis', 'service', 'custom')][string]$AppType = 'none',
    [string]$AppName = '',
    [string]$StopScript = '',
    [string]$StartScript = '',
    # Comma-separated, e.g. "appsettings.Production.json,.env"
    [string]$PreserveFiles = '',
    [string]$PreserveDirs = '',
    [int]$KeepBackups = 5,
    [int]$TimeoutSeconds = 60
)

. "$PSScriptRoot\common.ps1"

function Split-List([string]$Value) {
    @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

if (-not (Test-Path $SourcePath) -or -not (Get-ChildItem $SourcePath -Force)) {
    throw "Source path '$SourcePath' is missing or empty - nothing to deploy"
}
if (($AppType -in 'iis', 'service') -and -not $AppName) { throw "AppName is required when AppType=$AppType" }
$isNewApp = -not (Test-Path $TargetPath) -or -not (Get-ChildItem $TargetPath -Force)

if ($AppType -eq 'custom' -and -not $StartScript) { throw 'StartScript is required when AppType=custom' }
if ($AppType -eq 'custom' -and -not $StopScript -and -not $isNewApp) {
    throw "StopScript is required when AppType=custom and '$TargetPath' already has an application"
}

# 1. Backup
$backupPath = ''
if ($isNewApp) {
    Write-Step "Target '$TargetPath' is empty or missing - treating as new app, no backup"
} elseif (-not $BackupRoot) {
    Write-Warning 'BackupRoot not set - skipping backup, rollback will NOT be possible'
} else {
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = Join-Path $BackupRoot "$(Split-Path $TargetPath -Leaf)_$stamp.zip"
    Write-Step "Backing up $TargetPath to $backupPath"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Compress-Archive in PS 5.1 skips hidden files and struggles with large files.
    [System.IO.Compression.ZipFile]::CreateFromDirectory($TargetPath, $backupPath)

    Get-ChildItem $BackupRoot -Filter '*.zip' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepBackups | Remove-Item -Force
}
# Published before anything is touched so a failure below can still be rolled back.
Set-PipelineOutput 'backup_path' $backupPath

# 2. Stop
Stop-App -AppType $AppType -AppName $AppName -StopScript $StopScript -TimeoutSeconds $TimeoutSeconds

# 3. Copy
Write-Step "Copying $SourcePath to $TargetPath"
New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
Sync-Folder -Source $SourcePath -Target $TargetPath `
    -PreserveFiles (Split-List $PreserveFiles) -PreserveDirs (Split-List $PreserveDirs)

# 4. Start
Start-App -AppType $AppType -AppName $AppName -StartScript $StartScript -TimeoutSeconds $TimeoutSeconds

Write-Step 'Deployment finished'
Add-PipelineSummary @"
### Deploy
| Item | Value |
|---|---|
| Target | ``$TargetPath`` |
| App type | $AppType $AppName |
| Backup | $(if ($backupPath) { "``$backupPath``" } else { 'none (new app)' }) |
"@
