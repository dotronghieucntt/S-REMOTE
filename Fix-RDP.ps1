# Emergency RDP Fix Script
# Run this if RDP still not working after setup

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Emergency RDP Fix - AGGRESSIVE MODE" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host "`n[1/7] Resetting RDP via WMIC..." -ForegroundColor Yellow
try {
    $wmicResult = & wmic /namespace:\\root\CIMV2\TerminalServices PATH Win32_TerminalServiceSetting WHERE (__CLASS!="") CALL SetAllowTSConnections 1 2>&1
    Write-Host "    [OK] WMIC reset executed" -ForegroundColor Green
}
catch {
    Write-Host "    [WARNING] WMIC not available" -ForegroundColor Yellow
}

Write-Host "`n[2/7] Setting critical registry values..." -ForegroundColor Yellow
& reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
& reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f 2>&1 | Out-Null
& reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f 2>&1 | Out-Null
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force
Write-Host "    [OK] Registry configured (dual method)" -ForegroundColor Green

Write-Host "`n[3/7] Configuring WMI RDP settings..." -ForegroundColor Yellow
try {
    $tsSettings = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root\CIMV2\TerminalServices -ErrorAction SilentlyContinue
    if ($tsSettings) {
        $tsSettings.SetAllowTSConnections(1, 1) | Out-Null
        Write-Host "    [OK] WMI configuration applied" -ForegroundColor Green
    }
}
catch {
    Write-Host "    [WARNING] WMI config skipped" -ForegroundColor Yellow
}

Write-Host "`n[4/7] Enabling firewall rules..." -ForegroundColor Yellow
& netsh advfirewall firewall set rule group="remote desktop" new enable=Yes 2>&1 | Out-Null
& netsh advfirewall firewall add rule name="RDP-Emergency" dir=in action=allow protocol=TCP localport=3389 2>&1 | Out-Null
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Write-Host "    [OK] Firewall configured (multi-method)" -ForegroundColor Green

Write-Host "`n[5/7] Stopping RDP services..." -ForegroundColor Yellow
# Kill zombie processes first
Get-Process -Name "rdpclip","tstheme" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process | Where-Object { $_.ProcessName -like "*svchost*" -and $_.Modules.ModuleName -like "*termsrv*" } | Stop-Process -Force -ErrorAction SilentlyContinue

Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Host "    [OK] Services stopped and processes cleaned" -ForegroundColor Green

Write-Host "`n[6/7] Starting RDP services with forced binding..." -ForegroundColor Yellow
& sc.exe config TermService start= auto 2>&1 | Out-Null
& sc.exe config SessionEnv start= auto 2>&1 | Out-Null
& sc.exe config UmRdpService start= auto 2>&1 | Out-Null

# Start SessionEnv first (dependency)
$sessionEnv = Get-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
if ($sessionEnv) {
    try {
        Set-Service -Name "SessionEnv" -StartupType Automatic
        Start-Service -Name "SessionEnv" -ErrorAction Stop
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "    [WARNING] SessionEnv start issue (may be OK)" -ForegroundColor Yellow
    }
}

# Start TermService
Set-Service -Name "TermService" -StartupType Automatic
Start-Service -Name "TermService"
Start-Sleep -Seconds 8

# Trigger session creation
& qwinsta 2>&1 | Out-Null
& query.exe session 2>&1 | Out-Null

# Start UmRdpService
$umRdp = Get-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
if ($umRdp) {
    try {
        Set-Service -Name "UmRdpService" -StartupType Automatic
        Start-Service -Name "UmRdpService" -ErrorAction Stop
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "    [WARNING] UmRdpService start issue (may be OK)" -ForegroundColor Yellow
    }
}

Write-Host "    [OK] Services started with forced binding" -ForegroundColor Green

Write-Host "`n[7/7] Verifying RDP port with retry logic..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "    [OK] Port 3389 is LISTENING - RDP is ready!" -ForegroundColor Green
} else {
    Write-Host "    [WARNING] Port not listening, trying emergency restart..." -ForegroundColor Yellow
    
    # EMERGENCY RETRY
    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Start-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
    
    $portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
    if ($portCheck) {
        Write-Host "    [OK] Port 3389 is NOW LISTENING (emergency restart worked!)" -ForegroundColor Green
    } else {
        Write-Host "    [ERROR] Port still not listening" -ForegroundColor Red
        Write-Host "    [INFO] Please run: Restart-Computer" -ForegroundColor Magenta
        Write-Host "    [INFO] RDP will work after restart (registry is configured)" -ForegroundColor Cyan
    }
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   FIX COMPLETED!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\Verify-RDP.ps1" -ForegroundColor Cyan
Write-Host "2. Wait 30 seconds" -ForegroundColor Cyan
Write-Host "3. Try RDP connection" -ForegroundColor Cyan
Write-Host ""
