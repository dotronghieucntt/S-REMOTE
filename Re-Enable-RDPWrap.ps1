# Re-enable rdpwrap with updated ini
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4

# Restore termsrv.dll from backup (undo any bad patches)
$src = "C:\Windows\System32\termsrv.dll"
$bak = "C:\Windows\System32\termsrv.dll.bak"
if (Test-Path $bak) {
    Copy-Item $bak $src -Force
    Write-Host "[OK] Restored original termsrv.dll from backup" -ForegroundColor Green
}

# Set ServiceDll to rdpwrap.dll
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\services\TermService\Parameters" `
    -Name "ServiceDll" -Value "C:\Program Files\RDP Wrapper\rdpwrap.dll" -Type String
Write-Host "[OK] ServiceDll -> rdpwrap.dll" -ForegroundColor Green

# Confirm ini is up to date
$iniSize = (Get-Item "C:\Program Files\RDP Wrapper\rdpwrap.ini").Length
Write-Host "[OK] rdpwrap.ini size: $iniSize bytes (should be ~497175)" -ForegroundColor Cyan

# Start services
Write-Host "Starting services..." -ForegroundColor Yellow
Start-Service SessionEnv -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service TermService
Start-Sleep -Seconds 8

$svc = (Get-Service TermService).Status
Write-Host "TermService: $svc" -ForegroundColor $(if($svc -eq 'Running'){'Green'}else{'Red'})
Start-Sleep -Seconds 3

# Check if it crashed
$crashes = Get-WinEvent -LogName System -MaxEvents 20 |
    Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-3) -and $_.Message -like "*Remote Desktop*terminated*" }
if ($crashes) {
    Write-Host "CRASH DETECTED after restart:" -ForegroundColor Red
    $crashes | ForEach-Object { Write-Host "  $($_.Message.Substring(0,120))" }
} else {
    Write-Host "No crashes detected - service stable!" -ForegroundColor Green
}

# Check port
$port = netstat -an 2>$null | Select-String ":3389"
if ($port) {
    Write-Host ""
    Write-Host "=== THANH CONG! Port 3389 LISTEN ===" -ForegroundColor Green
    $port
} else {
    Write-Host "Port 3389 not listening yet" -ForegroundColor Yellow
}

Get-Service TermService | Select-Object Status
