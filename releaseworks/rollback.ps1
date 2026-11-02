<#
.SYNOPSIS
    Restores the application from a backup zip created by deploy.ps1.

.EXAMPLE
    .\rollback.ps1 -BackupPath D:\Backups\SampleApi\SampleApi_20261101_200000.zip `
        -TargetPath D:\Apps\SampleApi -AppType service -AppName SampleApi
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [ValidateSet('none', 'iis', 'service', 'custom')][string]$AppType = 'none',
    [string]$AppName = '',
    [string]$StopScript = '',
    [string]$StartScript = '',
    [int]$TimeoutSeconds = 60
)

. "$PSScriptRoot\common.ps1"

if (-not (Test-Path $BackupPath -PathType Leaf)) { throw "Backup not found: $BackupPath" }

$extracted = Join-Path ([System.IO.Path]::GetTempPath()) "rollback_$([guid]::NewGuid().ToString('N'))"
try {
    Write-Step "Extracting $BackupPath"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $extracted)

    Stop-App -AppType $AppType -AppName $AppName -StopScript $StopScript -TimeoutSeconds $TimeoutSeconds

    Write-Step "Restoring $TargetPath"
    # The backup holds the full previous folder, config included, so nothing is preserved.
    Sync-Folder -Source $extracted -Target $TargetPath

    Start-App -AppType $AppType -AppName $AppName -StartScript $StartScript -TimeoutSeconds $TimeoutSeconds
} finally {
    Remove-Item $extracted -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Rollback finished'
Add-PipelineSummary "### Rollback`nRestored ``$TargetPath`` from ``$BackupPath``"
