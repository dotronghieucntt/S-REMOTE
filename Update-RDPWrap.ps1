# Update rdpwrap.ini and restart RDP service
# Must run as Administrator

$iniPath = "C:\Program Files\RDP Wrapper\rdpwrap.ini"
$build = (Get-Item "C:\Windows\System32\termsrv.dll").VersionInfo.FilePrivatePart

Write-Host "termsrv.dll build: 10.0.19041.$build" -ForegroundColor Cyan

# Download updated ini
Write-Host "Downloading updated rdpwrap.ini..." -ForegroundColor Yellow
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
try {
    $data = $wc.DownloadString("https://raw.githubusercontent.com/asmtron/rdpwrap/master/res/rdpwrap.ini")
    Write-Host "Downloaded $($data.Length) chars" -ForegroundColor Green
    
    # Check if current build is in the ini
    $buildStr = "19041.$build"
    if ($data -match [regex]::Escape($buildStr)) {
        Write-Host "Build $buildStr FOUND in ini!" -ForegroundColor Green
    } else {
        Write-Host "Build $buildStr NOT found, but applying anyway..." -ForegroundColor Yellow
    }
    
    # Save
    $data | Set-Content $iniPath -Encoding ASCII -Force
    Write-Host "Saved to $iniPath" -ForegroundColor Green
} catch {
    Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Trying fallback..." -ForegroundColor Yellow
    try {
        $wc2 = New-Object System.Net.WebClient
        $data2 = $wc2.DownloadString("https://raw.githubusercontent.com/stascorp/rdpwrap/master/res/rdpwrap.ini")
        $data2 | Set-Content $iniPath -Encoding ASCII -Force
        Write-Host "Fallback ini saved" -ForegroundColor Yellow
    } catch {
        Write-Host "Both downloads failed. Continuing with existing ini." -ForegroundColor Red
    }
}

# Enable RDP firewall rules
Write-Host "Configuring firewall..." -ForegroundColor Yellow
& netsh advfirewall firewall set rule group="remote desktop" new enable=Yes 2>&1 | Out-Null
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Write-Host "Firewall configured" -ForegroundColor Green

# Restart services
Write-Host "Restarting TermService..." -ForegroundColor Yellow
Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Start-Service -Name "TermService"
Start-Sleep -Seconds 5
Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue

# Check
Write-Host ""
$listen = netstat -an 2>$null | Select-String ":3389"
if ($listen) {
    Write-Host "=== THANH CONG! Port 3389 LISTEN ===" -ForegroundColor Green
    $listen | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
} else {
    Write-Host "Port 3389 chua listen. Co the can restart may." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "IPs de ket noi qua RDP:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -ne "WellKnown" } |
    Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize

Write-Host "Username de login: $env:USERNAME" -ForegroundColor Cyan
pause
