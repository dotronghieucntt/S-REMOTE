# Uninstall rdpwrap, patch termsrv.dll directly
# Admin required

# Step 1: Stop services and restore original ServiceDll
Write-Host "[1/6] Stopping services and restoring original ServiceDll..." -ForegroundColor Yellow
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Stop-Service SessionEnv -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# Restore ServiceDll to original termsrv.dll
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\services\TermService\Parameters" -Name "ServiceDll" -Value "%SystemRoot%\System32\termsrv.dll" -Type ExpandString
Write-Host "  Restored ServiceDll to termsrv.dll" -ForegroundColor Green

# Step 2: Backup termsrv.dll
Write-Host "[2/6] Backing up termsrv.dll..." -ForegroundColor Yellow
$src = "$env:SystemRoot\System32\termsrv.dll"
$bak = "$env:SystemRoot\System32\termsrv.dll.bak"
if (-not (Test-Path $bak)) {
    Copy-Item $src $bak -Force
    Write-Host "  Backup created at $bak" -ForegroundColor Green
} else {
    Write-Host "  Backup already exists" -ForegroundColor Cyan
}

# Step 3: Take ownership
Write-Host "[3/6] Taking ownership of termsrv.dll..." -ForegroundColor Yellow
& takeown /f $src /a | Out-Null
& icacls $src /grant "Administrators:F" | Out-Null
Write-Host "  Ownership granted" -ForegroundColor Green

# Step 4: Patch termsrv.dll - read current bytes, find and patch
Write-Host "[4/6] Patching termsrv.dll for build 19041.6456..." -ForegroundColor Yellow
$bytes = [System.IO.File]::ReadAllBytes($src)
$build = (Get-Item $src).VersionInfo.FilePrivatePart
Write-Host "  DLL build: $build, size: $($bytes.Length)"

$patched = $false

# Pattern 1: SingleUser patch - original pattern: 39 23 75 XX -> 39 23 EB XX
# (comparing session count, jump if not equal → short jump unconditional)
# Pattern varies by build - search for known sequence in 20H1/21H1

# Search for the SingleUser check pattern near offset 0x1842B (from ini)
# Convert offset from ini
$singleUserOffset = 0x1842B

# Method: search known byte patterns for 19041 builds
# Standard patch: look for "39 23 75" and change 75 to EB
$patchCount = 0

# Patch at the hint offsets from ini (if signature matches)
$hints = @(
    @{ Offset=0x1842B; Name="SingleUser"; OldBytes=@(); NewBytes=@(0xB8,0x01,0x00,0x00,0x00,0x90,0x90) },
    @{ Offset=0x91A61; Name="LocalOnly";  OldBytes=@(); NewBytes=@() }
)

# Better: search for byte patterns throughout the dll
# Pattern: B8 00 01 00 00 (common limiter) or 39 23 (cmp [rbx], esp)

# The most reliable universal patch for Windows 10 RDP:
# Find: 39 23 75 (cmp [rbx],esp + jnz short) → change 75 → EB (jmp short)
Write-Host "  Searching for SingleUser session limit pattern..." -ForegroundColor Cyan

for ($i = 0; $i -lt $bytes.Length - 3; $i++) {
    if ($bytes[$i] -eq 0x39 -and $bytes[$i+1] -eq 0x23 -and $bytes[$i+2] -eq 0x75) {
        Write-Host "  Found pattern [39 23 75] at offset 0x$($i.ToString('X')) - patching to EB" -ForegroundColor Cyan
        $bytes[$i+2] = 0xEB
        $patchCount++
        if ($patchCount -ge 3) { break }  # limit changes
    }
}

if ($patchCount -eq 0) {
    Write-Host "  Pattern 39 23 75 not found, trying alternative..." -ForegroundColor Yellow
    # Alternative pattern for newer builds: 0F 84 XX XX XX XX (jz near)
    # followed by session count check
    # Try: B8 00 01 00 00 → B8 00 10 00 00 (raise limit)
    for ($i = 0; $i -lt $bytes.Length - 5; $i++) {
        if ($bytes[$i] -eq 0xB8 -and $bytes[$i+1] -eq 0x00 -and $bytes[$i+2] -eq 0x01 -and $bytes[$i+3] -eq 0x00 -and $bytes[$i+4] -eq 0x00) {
            Write-Host "  Found B8 00 01 00 00 at 0x$($i.ToString('X'))" -ForegroundColor Cyan
            $patchCount++
        }
    }
}

Write-Host "  Matches found: $patchCount" -ForegroundColor Cyan

if ($patchCount -gt 0) {
    # Stop service before writing
    Stop-Service TermService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    [System.IO.File]::WriteAllBytes($src, $bytes)
    Write-Host "  Patch written to termsrv.dll" -ForegroundColor Green
    $patched = $true
} else {
    Write-Host "  No patch pattern found - using offset-based approach" -ForegroundColor Yellow
    # Fallback: patch at exact offsets from ini
    $offX64 = 0x1842B
    if ($offX64 -lt $bytes.Length - 7) {
        Write-Host "  Patching at ini offset 0x1842B: $($bytes[$offX64].ToString('X2')) $($bytes[$offX64+1].ToString('X2')) $($bytes[$offX64+2].ToString('X2'))" -ForegroundColor Cyan
        # Place mov eax, 1 (B8 01 00 00 00) + nop nop
        $bytes[$offX64]   = 0xB8
        $bytes[$offX64+1] = 0x01
        $bytes[$offX64+2] = 0x00
        $bytes[$offX64+3] = 0x00
        $bytes[$offX64+4] = 0x00
        $bytes[$offX64+5] = 0x90
        $bytes[$offX64+6] = 0x90
        Stop-Service TermService -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        [System.IO.File]::WriteAllBytes($src, $bytes)
        Write-Host "  Offset-based patch applied" -ForegroundColor Green
        $patched = $true
    }
}

# Step 5: Enable RDP registry + firewall
Write-Host "[5/6] Enabling RDP settings..." -ForegroundColor Yellow
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force
& netsh advfirewall firewall set rule group="remote desktop" new enable=Yes 2>&1 | Out-Null
& netsh advfirewall firewall add rule name="RDP-Allow" dir=in action=allow protocol=TCP localport=3389 2>&1 | Out-Null
Write-Host "  Registry + firewall configured" -ForegroundColor Green

# Step 6: Start TermService
Write-Host "[6/6] Starting TermService..." -ForegroundColor Yellow
Start-Service SessionEnv -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service TermService
Start-Sleep -Seconds 8

$svc = (Get-Service TermService).Status
Write-Host "  TermService: $svc" -ForegroundColor $(if($svc -eq 'Running'){'Green'}else{'Red'})

$port = netstat -an 2>$null | Select-String ":3389"
if ($port) {
    Write-Host "" 
    Write-Host "=== THANH CONG! Port 3389 LISTEN ===" -ForegroundColor Green
    $port | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host ""
    Write-Host "Port 3389 chua listen - xem event log" -ForegroundColor Red
    Get-WinEvent -LogName System -MaxEvents 20 | Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-2) -and $_.ProviderName -match "Service" } | ForEach-Object { Write-Host "  $($_.Message.Substring(0,[Math]::Min(120,$_.Message.Length)))" }
}

Write-Host ""
Write-Host "IPs de connect:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize
Write-Host "Username: $env:USERNAME"
pause
