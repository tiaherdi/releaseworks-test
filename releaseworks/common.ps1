# Shared helpers for deploy.ps1 / verify.ps1 / rollback.ps1.
# Compatible with Windows PowerShell 5.1 (default on Windows Server).

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Passes a value to later steps/jobs. Written without BOM: PowerShell 5.1's
# Add-Content -Encoding utf8 would prepend one and corrupt the first key.
#   GitHub: step output "<name>"
#   GitLab: variable "<NAME>" in pipeline.env (publish it as artifacts:reports:dotenv)
function Set-PipelineOutput([string]$Name, [string]$Value) {
    if ($env:GITHUB_OUTPUT) {
        [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, "$Name=$Value`n")
    }
    if ($env:GITLAB_CI) {
        [System.IO.File]::AppendAllText((Join-Path (Get-Location) 'pipeline.env'), "$($Name.ToUpper())=$Value`n")
    }
}

function Add-PipelineSummary([string]$Markdown) {
    if ($env:GITHUB_STEP_SUMMARY) {
        [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, "$Markdown`n")
    }
}

function Invoke-UserScript([string]$Path, [string]$Purpose) {
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "$Purpose script not found: $Path"
    }
    Write-Step "Running $Purpose script $Path"
    $global:LASTEXITCODE = 0
    & $Path
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$Purpose script exited with code $LASTEXITCODE"
    }
}

# AppType:
#   none    - nothing to stop/start (new app, or static files)
#   iis     - AppName is the IIS application pool
#   service - AppName is the Windows Service (also covers Node apps wrapped by NSSM/WinSW)
#   custom  - StopScript / StartScript are .ps1 files supplied by the user
function Stop-App {
    param(
        [string]$AppType, [string]$AppName, [string]$StopScript, [int]$TimeoutSeconds = 60
    )
    switch ($AppType) {
        'none' { Write-Step 'AppType=none, nothing to stop' }
        'custom' {
            if ($StopScript) { Invoke-UserScript $StopScript 'stop' }
            else { Write-Warning 'No stop script (new app?), skipping stop' }
        }
        'iis' {
            Import-Module WebAdministration
            if (-not (Test-Path "IIS:\AppPools\$AppName")) {
                Write-Warning "App pool '$AppName' does not exist yet (new app?), skipping stop"
                return
            }
            if ((Get-WebAppPoolState -Name $AppName).Value -ne 'Stopped') {
                Write-Step "Stopping IIS app pool $AppName"
                Stop-WebAppPool -Name $AppName
            }
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-WebAppPoolState -Name $AppName).Value -ne 'Stopped') {
                if ((Get-Date) -gt $deadline) { throw "App pool '$AppName' did not stop within $TimeoutSeconds s" }
                Start-Sleep -Seconds 2
            }
        }
        'service' {
            $svc = Get-Service -Name $AppName -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Warning "Service '$AppName' does not exist yet (new app?), skipping stop"
                return
            }
            if ($svc.Status -ne 'Stopped') {
                Write-Step "Stopping service $AppName"
                Stop-Service -Name $AppName -Force
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($TimeoutSeconds))
            }
        }
        default { throw "Unknown AppType '$AppType'" }
    }
}

function Start-App {
    param(
        [string]$AppType, [string]$AppName, [string]$StartScript, [int]$TimeoutSeconds = 60
    )
    switch ($AppType) {
        'none' { Write-Step 'AppType=none, nothing to start' }
        'custom' { Invoke-UserScript $StartScript 'start' }
        'iis' {
            Import-Module WebAdministration
            Write-Step "Starting IIS app pool $AppName"
            Start-WebAppPool -Name $AppName
        }
        'service' {
            Write-Step "Starting service $AppName"
            Start-Service -Name $AppName
            (Get-Service -Name $AppName).WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSeconds))
        }
        default { throw "Unknown AppType '$AppType'" }
    }
}

# Mirrors Source into Target. Files/dirs listed in Preserve* are neither copied nor
# deleted, so server-specific config (appsettings.Production.json, .env, logs) survives.
function Sync-Folder {
    param(
        [string]$Source, [string]$Target, [string[]]$PreserveFiles = @(), [string[]]$PreserveDirs = @()
    )
    $roboArgs = @($Source, $Target, '/MIR', '/R:3', '/W:5', '/NP', '/NFL', '/NDL')
    if ($PreserveFiles.Count) { $roboArgs += '/XF'; $roboArgs += $PreserveFiles }
    if ($PreserveDirs.Count) { $roboArgs += '/XD'; $roboArgs += $PreserveDirs }

    & robocopy @roboArgs | Out-Host
    # robocopy: 0-7 = success (with or without changes), 8+ = failure
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    $global:LASTEXITCODE = 0
}
