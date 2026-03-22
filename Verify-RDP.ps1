# Quick RDP Verification Script
# Run this after using ZeroTier-QuickSetup.exe

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   RDP Configuration Verification" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$issues = 0

# Check 1: Registry - fDenyTSConnections
Write-Host "`n[1] Checking fDenyTSConnections..." -ForegroundColor Yellow
$reg1 = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
if ($reg1.fDenyTSConnections -eq 0) {
    Write-Host "    [OK] Value: 0 (RDP Enabled)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Value: $($reg1.fDenyTSConnections) (Should be 0)" -ForegroundColor Red
    $issues++
}

# Check 2: Registry - UserAuthentication
Write-Host "`n[2] Checking UserAuthentication..." -ForegroundColor Yellow
$reg2 = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue
if ($reg2.UserAuthentication -eq 0) {
    Write-Host "    [OK] Value: 0 (NLA Disabled)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Value: $($reg2.UserAuthentication) (Should be 0)" -ForegroundColor Red
    $issues++
}

# Check 3: Registry - LocalAccountTokenFilterPolicy
Write-Host "`n[3] Checking LocalAccountTokenFilterPolicy..." -ForegroundColor Yellow
$reg3 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -ErrorAction SilentlyContinue
if ($reg3.LocalAccountTokenFilterPolicy -eq 1) {
    Write-Host "    [OK] Value: 1 (Remote Admin Enabled)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Value: $($reg3.LocalAccountTokenFilterPolicy) (Should be 1)" -ForegroundColor Red
    Write-Host "    [FIX] Run: Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Force" -ForegroundColor Magenta
    $issues++
}

# Check 4: Service - TermService
Write-Host "`n[4] Checking TermService..." -ForegroundColor Yellow
$svc = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
if ($svc.Status -eq "Running") {
    Write-Host "    [OK] Status: Running" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Status: $($svc.Status) (Should be Running)" -ForegroundColor Red
    Write-Host "    [FIX] Run: Start-Service TermService" -ForegroundColor Magenta
    $issues++
}

# Check 5: Port 3389 Listening
Write-Host "`n[5] Checking Port 3389..." -ForegroundColor Yellow
$port = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($port) {
    Write-Host "    [OK] Port 3389 is LISTENING" -ForegroundColor Green
    $port | Select-Object LocalAddress, LocalPort, State | Format-Table
} else {
    Write-Host "    [FAIL] Port 3389 is NOT listening" -ForegroundColor Red
    Write-Host "    [FIX] Restart service: net stop termservice && net start termservice" -ForegroundColor Magenta
    $issues++
}

# Check 6: Firewall Rules
Write-Host "`n[6] Checking Firewall Rules..." -ForegroundColor Yellow
try {
    $fwRules = Get-NetFirewallRule | Where-Object { 
        ($_.DisplayName -like "*Remote Desktop*" -or $_.DisplayName -like "*RDP*") -and 
        $_.Enabled -eq $true 
    } -ErrorAction SilentlyContinue
    
    if ($fwRules) {
        Write-Host "    [OK] Found $($fwRules.Count) enabled RDP firewall rules" -ForegroundColor Green
    } else {
        Write-Host "    [WARNING] No enabled RDP firewall rules found" -ForegroundColor Yellow
        Write-Host "    [FIX] Run: netsh advfirewall firewall set rule group='remote desktop' new enable=Yes" -ForegroundColor Magenta
    }
} catch {
    Write-Host "    [INFO] Cannot check firewall (need admin rights)" -ForegroundColor Cyan
}

# Check 7: ZeroTier IP
Write-Host "`n[7] Checking ZeroTier IP..." -ForegroundColor Yellow
$ztCliPath = "C:\Program Files (x86)\ZeroTier\One\zerotier-one_x64.exe"
if (-not (Test-Path $ztCliPath)) {
    $ztCliPath = "C:\ProgramData\ZeroTier\One\zerotier-one_x64.exe"
}

if (Test-Path $ztCliPath) {
    try {
        $listResult = & $ztCliPath "-q" "listnetworks" 2>&1 | Out-String
        if ($listResult -match "(\d+\.\d+\.\d+\.\d+)") {
            $ztIP = $Matches[1]
            Write-Host "    [OK] ZeroTier IP: $ztIP" -ForegroundColor Green
            
            # Test RDP connectivity on ZeroTier IP
            Write-Host "`n[8] Testing RDP on ZeroTier IP..." -ForegroundColor Yellow
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $asyncResult = $tcpClient.BeginConnect($ztIP, 3389, $null, $null)
                $wait = $asyncResult.AsyncWaitHandle.WaitOne(3000, $false)
                
                if ($wait) {
                    $tcpClient.EndConnect($asyncResult)
                    $tcpClient.Close()
                    Write-Host "    [OK] RDP port 3389 is accessible on $ztIP" -ForegroundColor Green
                } else {
                    Write-Host "    [FAIL] Cannot connect to port 3389 on $ztIP" -ForegroundColor Red
                    $tcpClient.Close()
                    $issues++
                }
            } catch {
                Write-Host "    [FAIL] Connection error: $($_.Exception.Message)" -ForegroundColor Red
                $issues++
            }
        } else {
            Write-Host "    [WARNING] No ZeroTier IP detected" -ForegroundColor Yellow
            Write-Host "    [INFO] Make sure device is authorized in ZeroTier Central" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "    [WARNING] Cannot query ZeroTier: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "    [WARNING] ZeroTier not installed" -ForegroundColor Yellow
}

# Summary
Write-Host "`n=============================================" -ForegroundColor Cyan
if ($issues -eq 0) {
    Write-Host "   RESULT: ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "   RDP should be working properly." -ForegroundColor Green
} else {
    Write-Host "   RESULT: $issues ISSUES FOUND" -ForegroundColor Red
    Write-Host "   Please fix the issues above." -ForegroundColor Yellow
}
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
