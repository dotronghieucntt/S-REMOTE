# Test RDP-Tcp Listener Rebuild Logic
# This script tests the fEnableWinStation toggle method

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Test RDP-Tcp Listener Rebuild" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host "`n[1] Current RDP-Tcp configuration:" -ForegroundColor Yellow
$rdpTcpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
$currentConfig = Get-ItemProperty -Path $rdpTcpPath -ErrorAction SilentlyContinue

if ($currentConfig) {
    Write-Host "    PortNumber: $($currentConfig.PortNumber)" -ForegroundColor Cyan
    Write-Host "    fEnableWinStation: $($currentConfig.fEnableWinStation)" -ForegroundColor Cyan
    Write-Host "    LanAdapter: $($currentConfig.LanAdapter)" -ForegroundColor Cyan
    Write-Host "    UserAuthentication: $($currentConfig.UserAuthentication)" -ForegroundColor Cyan
}
else {
    Write-Host "    [ERROR] RDP-Tcp configuration not found!" -ForegroundColor Red
    exit
}

Write-Host "`n[2] Current port 3389 status:" -ForegroundColor Yellow
$portBefore = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($portBefore) {
    Write-Host "    [OK] Port 3389 is LISTENING" -ForegroundColor Green
}
else {
    Write-Host "    [NOT LISTENING] Port 3389 is NOT listening" -ForegroundColor Red
}

Write-Host "`n[3] Testing listener rebuild method..." -ForegroundColor Yellow
Write-Host "    This will:" -ForegroundColor Cyan
Write-Host "    - Disable RDP-Tcp WinStation (fEnableWinStation = 0)" -ForegroundColor Cyan
Write-Host "    - Wait 2 seconds" -ForegroundColor Cyan
Write-Host "    - Re-enable RDP-Tcp WinStation (fEnableWinStation = 1)" -ForegroundColor Cyan
Write-Host "    - Restart TermService" -ForegroundColor Cyan
Write-Host "    - Wait 10 seconds" -ForegroundColor Cyan
Write-Host "    - Check if port 3389 is listening" -ForegroundColor Cyan
Write-Host ""

$continue = Read-Host "Continue with test? (y/N)"
if ($continue -ne "y" -and $continue -ne "Y") {
    Write-Host "`n[CANCELLED] Test aborted" -ForegroundColor Yellow
    exit
}

Write-Host "`n[4] Disabling RDP-Tcp WinStation..." -ForegroundColor Yellow
Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 0 -Force
Write-Host "    [OK] fEnableWinStation = 0" -ForegroundColor Green
Start-Sleep -Seconds 2

Write-Host "`n[5] Re-enabling RDP-Tcp WinStation..." -ForegroundColor Yellow
Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 1 -Force
Write-Host "    [OK] fEnableWinStation = 1" -ForegroundColor Green

Write-Host "`n[6] Restarting TermService..." -ForegroundColor Yellow
try {
    Restart-Service -Name "TermService" -Force -ErrorAction Stop
    Write-Host "    [OK] TermService restarted" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Restart failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Trying manual stop/start..." -ForegroundColor Yellow
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
}

Write-Host "`n[7] Waiting 10 seconds for listener to initialize..." -ForegroundColor Yellow
for ($i = 10; $i -gt 0; $i--) {
    Write-Host "    $i..." -NoNewline -ForegroundColor Cyan
    Start-Sleep -Seconds 1
}
Write-Host ""

Write-Host "`n[8] Checking port 3389 status..." -ForegroundColor Yellow
$portAfter = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   RESULT" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if ($portAfter) {
    Write-Host "[SUCCESS] Port 3389 is NOW LISTENING!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Listener rebuild method WORKS on this machine!" -ForegroundColor Green
    Write-Host "The tool will be able to fix RDP without restart." -ForegroundColor Green
}
else {
    Write-Host "[FAILED] Port 3389 is STILL NOT listening" -ForegroundColor Red
    Write-Host ""
    Write-Host "This machine REQUIRES restart for RDP listener." -ForegroundColor Yellow
    Write-Host "Even the advanced rebuild method doesn't work." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Recommendation:" -ForegroundColor Yellow
    Write-Host "  Use Safe-Restart.ps1 to schedule restart" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Verification:" -ForegroundColor Yellow
Write-Host "  Before test: $(if($portBefore){'Listening'}else{'Not listening'})" -ForegroundColor Cyan
Write-Host "  After test:  $(if($portAfter){'Listening'}else{'Not listening'})" -ForegroundColor Cyan
Write-Host ""
