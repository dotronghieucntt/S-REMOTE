<#
.SYNOPSIS
    Lists Tailscale tailnet devices and (optionally) deletes ones that have not
    been seen in the last N days (default 7).

.DESCRIPTION
    Reads TAILSCALE_API_KEY from .env in the script's directory, queries the
    Tailscale API for all devices in the tailnet, and classifies each device as
    Active or Inactive based on its "lastSeen" timestamp.

    By default this script only LISTS devices (dry run) - nothing is deleted.
    Pass -Delete to actually remove the Inactive devices, after an interactive
    confirmation prompt (unless -Force is also passed).

.PARAMETER Days
    Inactivity threshold in days. Devices last seen more than this many days
    ago are considered Inactive. Default: 7.

.PARAMETER Delete
    Actually delete the Inactive devices from the tailnet. Without this switch
    the script only prints the list (safe, read-only).

.PARAMETER Force
    Skip the interactive confirmation prompt when used together with -Delete.

.EXAMPLE
    .\Tailscale-CleanupInactiveDevices.ps1
    # Dry run: just show which devices are Active / Inactive.

.EXAMPLE
    .\Tailscale-CleanupInactiveDevices.ps1 -Delete
    # Show the list, ask for confirmation, then delete Inactive devices.
#>

param(
    [int]$Days = 7,
    [switch]$Delete,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Load TAILSCALE_API_KEY from .env ──────────────────────────────────────────
$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envPath)) {
    Write-Host "[ERROR] .env not found at $envPath" -ForegroundColor Red
    exit 1
}

$apiKey = $null
foreach ($line in Get-Content $envPath) {
    if ($line -match '^\s*TAILSCALE_API_KEY\s*=\s*(.+?)\s*$') {
        $apiKey = $Matches[1].Trim('"').Trim("'")
        break
    }
}
if (-not $apiKey) {
    Write-Host "[ERROR] TAILSCALE_API_KEY not found in .env" -ForegroundColor Red
    exit 1
}

# ── Auth header (Tailscale API uses HTTP Basic auth: apikey as username, blank password) ──
$basicToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$apiKey`:"))
$headers = @{ Authorization = "Basic $basicToken" }

# ── Fetch devices ──────────────────────────────────────────────────────────────
Write-Host "Fetching device list from Tailscale API..." -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod -Uri "https://api.tailscale.com/api/v2/tailnet/-/devices?fields=all" -Headers $headers -Method Get
} catch {
    Write-Host "[ERROR] Failed to fetch devices: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$devices = $resp.devices
if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "No devices found in tailnet." -ForegroundColor Yellow
    exit 0
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$Days)

$rows = foreach ($d in $devices) {
    $lastSeen = [datetime]::Parse($d.lastSeen, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    [PSCustomObject]@{
        Hostname = $d.hostname
        Name     = $d.name
        ID       = $d.id
        LastSeen = $lastSeen
        DaysAgo  = [math]::Round(((Get-Date).ToUniversalTime() - $lastSeen).TotalDays, 1)
        Status   = if ($lastSeen -lt $cutoff) { 'Inactive' } else { 'Active' }
    }
}

$active   = $rows | Where-Object { $_.Status -eq 'Active' }
$inactive = $rows | Where-Object { $_.Status -eq 'Inactive' }

Write-Host ""
Write-Host "=== ACTIVE (seen within last $Days days) - $($active.Count) device(s), KEPT ===" -ForegroundColor Green
$active | Sort-Object LastSeen -Descending | Format-Table Hostname, DaysAgo, LastSeen, ID -AutoSize

Write-Host ""
Write-Host "=== INACTIVE (not seen in last $Days days) - $($inactive.Count) device(s) ===" -ForegroundColor Yellow
$inactive | Sort-Object LastSeen | Format-Table Hostname, DaysAgo, LastSeen, ID -AutoSize

if (-not $Delete) {
    Write-Host ""
    Write-Host "[DRY RUN] No devices were deleted. Re-run with -Delete to remove the $($inactive.Count) Inactive device(s) above." -ForegroundColor Cyan
    exit 0
}

if ($inactive.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing to delete - all devices are active." -ForegroundColor Green
    exit 0
}

if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Type YES to permanently delete the $($inactive.Count) Inactive device(s) listed above"
    if ($confirm -ne 'YES') {
        Write-Host "Aborted. Nothing was deleted." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
foreach ($d in $inactive) {
    try {
        Invoke-RestMethod -Uri "https://api.tailscale.com/api/v2/device/$($d.ID)" -Headers $headers -Method Delete | Out-Null
        Write-Host "[DELETED] $($d.Hostname) (last seen $($d.DaysAgo) days ago)" -ForegroundColor Red
    } catch {
        Write-Host "[FAILED]  $($d.Hostname): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
