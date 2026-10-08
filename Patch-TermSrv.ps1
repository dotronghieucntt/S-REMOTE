# Patch-TermSrv.ps1 - manual RDP host enabler for Windows Home.
#
# Removes the single-session limit by patching termsrv.dll directly, as a
# standalone alternative to RDP Wrapper. Admin required.
#
# Safety: the session-limit check has ONE known signature per architecture and
# it appears exactly once in an unpatched DLL. This script patches only that
# single match; on 0 or 2+ matches it refuses and changes nothing, rather than
# corrupting the DLL by rewriting every look-alike byte sequence (which the
# earlier "patch up to 3 matches" version did).
#
# This is the same patch the NOVIVO app applies automatically via the generated
# ProgramData\NOVIVO\Repair-NovivoRdp.ps1; run this only for manual repair.

$ErrorActionPreference = 'Stop'
$src = "$env:SystemRoot\System32\termsrv.dll"
$bak = "$env:SystemRoot\System32\termsrv.dll.novivo.bak"

# x64 Win10/11 session-limit check:
#   39 81 3C 06 00 00   cmp dword ptr [rcx+63Ch], eax
#   0F 84 xx xx xx xx   je  <reject the connection>
# Replaced (same 12-byte length, so nothing downstream shifts) with:
#   B8 00 01 00 00      mov eax, 100h
#   89 81 38 06 00 00   mov dword ptr [rcx+638h], eax
#   90                  nop
$sigHex   = '39813C0600000F84'
$newBytes = [byte[]](0xB8,0x00,0x01,0x00,0x00,0x89,0x81,0x38,0x06,0x00,0x00,0x90)

if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host "[ERROR] Only 64-bit Windows is supported by this patch." -ForegroundColor Red
    pause; exit 1
}

# Step 1: stop services and restore the real termsrv.dll as ServiceDll
Write-Host "[1/6] Stopping services and restoring original ServiceDll..." -ForegroundColor Yellow
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Stop-Service SessionEnv  -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\services\TermService\Parameters" `
    -Name "ServiceDll" -Value "%SystemRoot%\System32\termsrv.dll" -Type ExpandString -Force
Write-Host "  ServiceDll points at termsrv.dll" -ForegroundColor Green

# Step 2: locate the signature - refuse unless it occurs exactly once
Write-Host "[2/6] Locating the session-limit signature..." -ForegroundColor Yellow
$bytes = [System.IO.File]::ReadAllBytes($src)
$build = (Get-Item $src).VersionInfo.FileVersion
Write-Host "  termsrv.dll $build, size $($bytes.Length)"

# Hex-string search: a byte-by-byte managed scan over ~1 MB is far too slow.
$hex  = [System.BitConverter]::ToString($bytes) -replace '-', ''
$hits = @()
$pos  = $hex.IndexOf($sigHex)
while ($pos -ge 0) {
    if ($pos % 2 -eq 0) { $hits += ($pos / 2) }   # odd index = not a byte boundary
    $pos = $hex.IndexOf($sigHex, $pos + 1)
}
if ($hits.Count -ne 1) {
    Write-Host "  Signature matched $($hits.Count) time(s) - REFUSING to patch." -ForegroundColor Red
    Write-Host "  This build is not supported by this signature. Nothing was changed." -ForegroundColor Red
    Write-Host "  Use RDP Wrapper (Install-RDPWrap.ps1) instead." -ForegroundColor Yellow
    Start-Service TermService -ErrorAction SilentlyContinue
    pause; exit 2
}
$off = $hits[0]
Write-Host "  Signature found at offset 0x$('{0:X}' -f $off)" -ForegroundColor Green

# Step 3: backup (pristine, since the signature only exists pre-patch)
Write-Host "[3/6] Backing up termsrv.dll..." -ForegroundColor Yellow
Copy-Item $src $bak -Force
Write-Host "  Backup at $bak" -ForegroundColor Green

# Step 4: take ownership and write the patch
Write-Host "[4/6] Patching termsrv.dll..." -ForegroundColor Yellow
& takeown.exe /f $src /a | Out-Null
& icacls.exe $src /grant "*S-1-5-32-544:F" | Out-Null
for ($k = 0; $k -lt $newBytes.Length; $k++) { $bytes[$off + $k] = $newBytes[$k] }
try {
    [System.IO.File]::WriteAllBytes($src, $bytes)
} catch {
    # File still mapped: swap it out under a different name and write fresh.
    $stale = "$src.old"
    if (Test-Path $stale) { Remove-Item $stale -Force -ErrorAction SilentlyContinue }
    Rename-Item -Path $src -NewName 'termsrv.dll.old' -Force
    [System.IO.File]::WriteAllBytes($src, $bytes)
}
& icacls.exe $src /setowner "NT SERVICE\TrustedInstaller" | Out-Null
Write-Host "  Patch written" -ForegroundColor Green

# Step 5: RDP registry + firewall
Write-Host "[5/6] Enabling RDP settings..." -ForegroundColor Yellow
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fSingleSessionPerUser" -Value 0 -Force
Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force
& netsh advfirewall firewall set rule group="remote desktop" new enable=Yes 2>&1 | Out-Null
& netsh advfirewall firewall add rule name="RDP-Allow" dir=in action=allow protocol=TCP localport=3389 2>&1 | Out-Null
Write-Host "  Registry + firewall configured" -ForegroundColor Green

# Step 6: start TermService and verify - roll back if the listener stays down
Write-Host "[6/6] Starting TermService..." -ForegroundColor Yellow
Start-Service SessionEnv -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service TermService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8

$svc  = (Get-Service TermService).Status
$port = netstat -an 2>$null | Select-String ":3389.*LISTEN"
if ($port) {
    Write-Host ""
    Write-Host "=== SUCCESS - port 3389 is LISTENING ===" -ForegroundColor Green
    $port | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host ""
    Write-Host "Port 3389 is not listening (TermService: $svc) - rolling back the patch." -ForegroundColor Red
    Stop-Service TermService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    try { Copy-Item $bak $src -Force; Write-Host "  Original termsrv.dll restored from backup." -ForegroundColor Yellow }
    catch { Write-Host "  ROLLBACK FAILED - restore manually from $bak" -ForegroundColor Red }
    Start-Service TermService -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "IPs to connect to:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize
Write-Host "Username: $env:USERNAME"
pause
