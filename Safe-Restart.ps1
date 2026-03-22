# Safe Restart Script
# Schedule restart with safety delay

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Safe Restart Scheduler" -ForegroundColor Cyan
Write-Host "   For RDP Activation" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host "`nThis script will:" -ForegroundColor Yellow
Write-Host "  1. Verify current RDP configuration" -ForegroundColor Cyan
Write-Host "  2. Schedule restart in 5 minutes" -ForegroundColor Cyan
Write-Host "  3. Give you time to cancel if needed" -ForegroundColor Cyan
Write-Host "  4. RDP will work after restart" -ForegroundColor Cyan

Write-Host "`n[1/3] Checking current RDP status..." -ForegroundColor Yellow
$portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue

if ($portCheck) {
    Write-Host "    [INFO] Port 3389 is already listening!" -ForegroundColor Green
    Write-Host "    [INFO] You may not need to restart" -ForegroundColor Green
    Write-Host ""
    $continue = Read-Host "Continue with restart anyway? (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        Write-Host "`n[CANCELLED] No restart scheduled" -ForegroundColor Yellow
        exit
    }
}
else {
    Write-Host "    [INFO] Port 3389 NOT listening - restart recommended" -ForegroundColor Yellow
}

Write-Host "`n[2/3] Verifying RDP configuration..." -ForegroundColor Yellow
$reg1 = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
$reg2 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -ErrorAction SilentlyContinue

if ($reg1.fDenyTSConnections -eq 0) {
    Write-Host "    [OK] RDP is enabled in registry" -ForegroundColor Green
}
else {
    Write-Host "    [ERROR] RDP not enabled! Run ZeroTier-QuickSetup.exe first!" -ForegroundColor Red
    exit
}

if ($reg2.LocalAccountTokenFilterPolicy -eq 1) {
    Write-Host "    [OK] Remote admin policy is enabled" -ForegroundColor Green
}
else {
    Write-Host "    [WARNING] LocalAccountTokenFilterPolicy not set (will be OK after restart)" -ForegroundColor Yellow
}

$termSvc = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
if ($termSvc.StartType -eq "Automatic") {
    Write-Host "    [OK] TermService is set to Automatic" -ForegroundColor Green
}
else {
    Write-Host "    [WARNING] TermService not set to Automatic" -ForegroundColor Yellow
}

Write-Host "`n[3/3] Scheduling restart..." -ForegroundColor Yellow
Write-Host ""
Write-Host "    Restart in: 5 minutes (300 seconds)" -ForegroundColor Cyan
Write-Host "    To cancel: shutdown /a" -ForegroundColor Magenta
Write-Host ""

# Schedule restart
$result = & shutdown /r /t 300 /c "RDP will work after restart. Registry configured. Cancel with: shutdown /a"

if ($LASTEXITCODE -eq 0) {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   RESTART SCHEDULED!" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Time until restart: 5 minutes" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To CANCEL restart:" -ForegroundColor Magenta
    Write-Host "  shutdown /a" -ForegroundColor White
    Write-Host ""
    Write-Host "After restart:" -ForegroundColor Green
    Write-Host "  - RDP will be fully functional" -ForegroundColor Cyan
    Write-Host "  - Port 3389 will be listening" -ForegroundColor Cyan
    Write-Host "  - You can connect via ZeroTier IP" -ForegroundColor Cyan
    Write-Host "  - No need to run tool again" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "ZeroTier IP: Check in ZeroTier Central" -ForegroundColor Yellow
    Write-Host "  https://my.zerotier.com" -ForegroundColor Cyan
    Write-Host ""
}
else {
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   ERROR: Could not schedule restart" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Manual restart:" -ForegroundColor Yellow
    Write-Host "  Restart-Computer" -ForegroundColor White
    Write-Host ""
}

# Show countdown
Write-Host "Countdown timer:" -ForegroundColor Yellow
for ($i = 300; $i -gt 0; $i -= 30) {
    $minutes = [math]::Floor($i / 60)
    $seconds = $i % 60
    Write-Host "  ${minutes}m ${seconds}s remaining... (Ctrl+C or 'shutdown /a' to cancel)" -ForegroundColor Cyan
    Start-Sleep -Seconds 30
    
    # Check if restart was cancelled
    $pending = & shutdown /s /t 0 /a 2>&1
    if ($pending -like "*No shutdown*") {
        Write-Host ""
        Write-Host "[INFO] Restart was cancelled" -ForegroundColor Yellow
        break
    }
}
