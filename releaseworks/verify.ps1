<#
.SYNOPSIS
    Checks that a freshly deployed application is up. Exits non-zero on failure so the
    pipeline can trigger rollback.

.EXAMPLE
    .\verify.ps1 -HealthUrl http://localhost:5080/health -AppType service -AppName SampleApi
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HealthUrl,
    [int]$ExpectedStatus = 200,
    # Optional text the response body must contain, e.g. "Healthy"
    [string]$ExpectedContent = '',
    [ValidateSet('none', 'iis', 'service', 'custom')][string]$AppType = 'none',
    [string]$AppName = '',
    [int]$Retries = 10,
    [int]$DelaySeconds = 6
)

. "$PSScriptRoot\common.ps1"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$results = New-Object System.Collections.Generic.List[string]

# 1. Service / app pool status
if ($AppType -eq 'service') {
    $status = (Get-Service -Name $AppName).Status
    $results.Add("| Service ``$AppName`` | $status |")
    if ($status -ne 'Running') { throw "Service '$AppName' is $status" }
} elseif ($AppType -eq 'iis') {
    Import-Module WebAdministration
    $status = (Get-WebAppPoolState -Name $AppName).Value
    $results.Add("| App pool ``$AppName`` | $status |")
    if ($status -ne 'Started') { throw "App pool '$AppName' is $status" }
}

# 2. Health check (the app may need a few seconds to warm up)
$ok = $false
$lastError = ''
for ($i = 1; $i -le $Retries; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -ne $ExpectedStatus) {
            $lastError = "HTTP $($response.StatusCode)"
        } elseif ($ExpectedContent -and $response.Content -notlike "*$ExpectedContent*") {
            $lastError = "response does not contain '$ExpectedContent'"
        } else {
            $ok = $true
            break
        }
    } catch {
        $lastError = $_.Exception.Message
    }
    Write-Host "Attempt $i/$Retries failed: $lastError"
    Start-Sleep -Seconds $DelaySeconds
}

$results.Add("| Health ``$HealthUrl`` | $(if ($ok) { 'OK' } else { "FAILED: $lastError" }) |")
Add-PipelineSummary ("### Verify`n| Check | Result |`n|---|---|`n" + ($results -join "`n"))

if (-not $ok) { throw "Health check failed after $Retries attempts: $lastError" }
Write-Step "Health check passed: $HealthUrl"
