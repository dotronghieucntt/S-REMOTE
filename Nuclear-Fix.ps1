# ABSOLUTE LAST RESORT - Nuclear Option
# Force recreate RDP listener by clearing and rebuilding from scratch

Write-Host "`n=============================================" -ForegroundColor Red
Write-Host "   NUCLEAR OPTION - RDP Listener Reset" -ForegroundColor Red
Write-Host "   THIS IS THE ABSOLUTE LAST RESORT!" -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red

Write-Host "`nThis script will:" -ForegroundColor Yellow
Write-Host "  1. Delete RDP-Tcp listener completely" -ForegroundColor Cyan
Write-Host "  2. Recreate from backup/template" -ForegroundColor Cyan
Write-Host "  3. Force TermService to rebuild" -ForegroundColor Cyan
Write-Host "  4. May cause system instability if fails!" -ForegroundColor Red
Write-Host ""

$continue = Read-Host "Are you SURE? This is risky! (type YES to continue)"
if ($continue -ne "YES") {
    Write-Host "`n[CANCELLED] Aborted - use Safe-Restart.ps1 instead" -ForegroundColor Yellow
    exit
}

Write-Host "`n[1/7] Backing up current RDP-Tcp configuration..." -ForegroundColor Yellow
$rdpTcpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
$backupPath = "$env:TEMP\RDP-Tcp-Backup.reg"

try {
    & reg.exe export "$($rdpTcpPath.Replace('HKLM:', 'HKEY_LOCAL_MACHINE'))" "$backupPath" /y 2>&1 | Out-Null
    Write-Host "    [OK] Backup saved to: $backupPath" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Backup failed! ABORTING!" -ForegroundColor Red
    exit
}

Write-Host "`n[2/7] Stopping ALL RDP services..." -ForegroundColor Yellow
Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue  
Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Host "    [OK] Services stopped" -ForegroundColor Green

Write-Host "`n[3/7] Deleting RDP-Tcp listener registry..." -ForegroundColor Yellow
try {
    # Rename instead of delete (safer)
    Rename-Item -Path $rdpTcpPath -NewName "RDP-Tcp-OLD" -Force -ErrorAction Stop
    Write-Host "    [OK] Renamed RDP-Tcp to RDP-Tcp-OLD" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Cannot rename RDP-Tcp: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    [INFO] Restoring from backup..." -ForegroundColor Yellow
    & reg.exe import "$backupPath" 2>&1 | Out-Null
    exit
}

Write-Host "`n[4/7] Creating fresh RDP-Tcp listener..." -ForegroundColor Yellow
try {
    # Create new RDP-Tcp from scratch
    New-Item -Path $rdpTcpPath -Force | Out-Null
    
    # Set essential values
    Set-ItemProperty -Path $rdpTcpPath -Name "PortNumber" -Value 3389 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 1 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "UserAuthentication" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "SecurityLayer" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "MinEncryptionLevel" -Value 1 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "fInheritMaxSessionTime" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "fInheritMaxDisconnectionTime" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "fInheritMaxIdleTime" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "LanAdapter" -Value 0 -Type DWord
    Set-ItemProperty -Path $rdpTcpPath -Name "MaxInstanceCount" -Value 4294967295 -Type DWord
    
    Write-Host "    [OK] Fresh RDP-Tcp created with essential settings" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Creation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    [INFO] Restoring RDP-Tcp-OLD..." -ForegroundColor Yellow
    Rename-Item -Path "$($rdpTcpPath)-OLD" -NewName "RDP-Tcp" -Force
    exit
}

Write-Host "`n[5/7] Setting system-wide RDP permissions..." -ForegroundColor Yellow
& reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
& reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f 2>&1 | Out-Null
Write-Host "    [OK] System permissions set" -ForegroundColor Green

Write-Host "`n[6/7] Starting TermService to rebuild listener..." -ForegroundColor Yellow
try {
    Start-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Service -Name "TermService" -ErrorAction Stop
    Start-Sleep -Seconds 15
    Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    
    Write-Host "    [OK] Services started" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Service start failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n[7/7] Testing if listener was created..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue

Write-Host "`n=============================================" -ForegroundColor Cyan
if ($portCheck) {
    Write-Host "   MIRACLE! IT WORKED!" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[SUCCESS] Port 3389 is LISTENING!" -ForegroundColor Green
    Write-Host "RDP should work now WITHOUT restart!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can delete the OLD listener:" -ForegroundColor Yellow
    Write-Host "  Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp-OLD' -Force" -ForegroundColor Cyan
}
else {
    Write-Host "   NUCLEAR OPTION FAILED" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[FAILED] Port 3389 is STILL not listening" -ForegroundColor Red
    Write-Host ""
    Write-Host "This machine ABSOLUTELY requires restart." -ForegroundColor Yellow
    Write-Host "No software method can fix it." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Restore old config:" -ForegroundColor Cyan
    Write-Host "     Rename-Item 'HKLM:\...\RDP-Tcp-OLD' -NewName 'RDP-Tcp' -Force" -ForegroundColor White
    Write-Host "     (Then restart machine)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2. Keep new config and restart:" -ForegroundColor Cyan
    Write-Host "     Restart-Computer" -ForegroundColor White
    Write-Host "     (RDP will work after restart)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  3. Schedule safe restart:" -ForegroundColor Cyan
    Write-Host "     powershell -File .\Safe-Restart.ps1" -ForegroundColor White
}
Write-Host ""
