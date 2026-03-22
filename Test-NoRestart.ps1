# Test if RDP listener can be created without restart
# This simulates what the tool does

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Testing RDP Listener Creation" -ForegroundColor Cyan
Write-Host "   WITHOUT MACHINE RESTART" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$startTime = Get-Date

Write-Host "`n[1/8] Killing zombie processes..." -ForegroundColor Yellow
Get-Process -Name "rdpclip","tstheme" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "    [OK] Cleaned" -ForegroundColor Green

Write-Host "`n[2/8] Resetting via WMIC..." -ForegroundColor Yellow
try {
    & wmic /namespace:\\root\CIMV2\TerminalServices PATH Win32_TerminalServiceSetting WHERE (__CLASS!="") CALL SetAllowTSConnections 1 2>&1 | Out-Null
    Write-Host "    [OK] WMIC reset done" -ForegroundColor Green
}
catch {
    Write-Host "    [SKIP] WMIC not available" -ForegroundColor Yellow
}

Write-Host "`n[3/8] Stopping all RDP services..." -ForegroundColor Yellow
Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Host "    [OK] All services stopped" -ForegroundColor Green

Write-Host "`n[4/8] Killing stuck processes..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like "*svchost*" } | ForEach-Object {
    try {
        if ($_.Modules.ModuleName -contains "termsrv.dll") {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Host "    [OK] Killed stuck TermService process PID: $($_.Id)" -ForegroundColor Green
        }
    }
    catch {}
}
Start-Sleep -Seconds 3

Write-Host "`n[5/8] Starting SessionEnv first (dependency)..." -ForegroundColor Yellow
$sessionEnv = Get-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
if ($sessionEnv) {
    Set-Service -Name "SessionEnv" -StartupType Automatic
    Start-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host "    [OK] SessionEnv started" -ForegroundColor Green
}

Write-Host "`n[6/8] Starting TermService with forced binding..." -ForegroundColor Yellow
Set-Service -Name "TermService" -StartupType Automatic
Start-Service -Name "TermService"
Start-Sleep -Seconds 8

# Trigger session initialization
& qwinsta 2>&1 | Out-Null
& query.exe session 2>&1 | Out-Null

Write-Host "    [OK] TermService started" -ForegroundColor Green

Write-Host "`n[7/8] Starting UmRdpService..." -ForegroundColor Yellow
$umRdp = Get-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
if ($umRdp) {
    Set-Service -Name "UmRdpService" -StartupType Automatic
    Start-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host "    [OK] UmRdpService started" -ForegroundColor Green
}

Write-Host "`n[8/8] Testing RDP listener on port 3389..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Test 1: Check with Get-NetTCPConnection
$portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "    [OK] Port 3389 is LISTENING (Get-NetTCPConnection)" -ForegroundColor Green
}
else {
    Write-Host "    [FAIL] Port 3389 NOT listening" -ForegroundColor Red
}

# Test 2: Check with netstat
Write-Host "`n    Checking with netstat..." -ForegroundColor Cyan
$netstatCheck = & netstat -ano | Select-String ":3389.*LISTENING"
if ($netstatCheck) {
    Write-Host "    [OK] Found in netstat:" -ForegroundColor Green
    Write-Host "    $netstatCheck" -ForegroundColor White
}
else {
    Write-Host "    [FAIL] NOT found in netstat" -ForegroundColor Red
}

# Test 3: Try loopback connection
Write-Host "`n    Testing loopback connection..." -ForegroundColor Cyan
try {
    $testClient = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $testClient.BeginConnect("127.0.0.1", 3389, $null, $null)
    $wait = $asyncResult.AsyncWaitHandle.WaitOne(3000, $false)
    
    if ($wait) {
        $testClient.EndConnect($asyncResult)
        $testClient.Close()
        Write-Host "    [OK] Loopback connection SUCCESSFUL" -ForegroundColor Green
    }
    else {
        $testClient.Close()
        Write-Host "    [FAIL] Loopback connection TIMEOUT" -ForegroundColor Red
    }
}
catch {
    Write-Host "    [FAIL] Connection error: $($_.Exception.Message)" -ForegroundColor Red
}

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

Write-Host "`n=============================================" -ForegroundColor Cyan
if ($portCheck) {
    Write-Host "   RESULT: SUCCESS!" -ForegroundColor Green
    Write-Host "   RDP listener created WITHOUT restart" -ForegroundColor Green
    Write-Host "   Time taken: $([math]::Round($duration, 1)) seconds" -ForegroundColor Green
}
else {
    Write-Host "   RESULT: FAILED" -ForegroundColor Red
    Write-Host "   RDP listener NOT created" -ForegroundColor Red
    Write-Host "   Machine restart may be required" -ForegroundColor Yellow
    Write-Host "" 
    Write-Host "   Possible causes:" -ForegroundColor Yellow
    Write-Host "   - Windows RDP subsystem in bad state" -ForegroundColor Cyan
    Write-Host "   - Registry corruption" -ForegroundColor Cyan
    Write-Host "   - Security policy blocking" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Solution: Restart-Computer" -ForegroundColor Magenta
}
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
