# Diagnostic script for machines that require restart
# Use this to understand why some machines need restart

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   Windows RDP Listener Diagnostics" -ForegroundColor Cyan
Write-Host "   Why does this machine need restart?" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Test 1: Check Windows Version
Write-Host "`n[1] Windows Version:" -ForegroundColor Yellow
$winVer = Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsHardwareAbstractionLayer
Write-Host "    OS: $($winVer.WindowsProductName)" -ForegroundColor Cyan
Write-Host "    Version: $($winVer.WindowsVersion)" -ForegroundColor Cyan
Write-Host "    HAL: $($winVer.OsHardwareAbstractionLayer)" -ForegroundColor Cyan

# Test 2: Check if Start-Service supports -Force
Write-Host "`n[2] Testing Start-Service -Force support:" -ForegroundColor Yellow
try {
    $testService = Get-Service -Name "Spooler"
    $cmd = Get-Command Start-Service
    $hasForce = $cmd.Parameters.ContainsKey("Force")
    if ($hasForce) {
        Write-Host "    [OK] -Force parameter is SUPPORTED" -ForegroundColor Green
    }
    else {
        Write-Host "    [ISSUE] -Force parameter NOT supported (old Windows version)" -ForegroundColor Red
        Write-Host "    This may cause service restart issues" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    [ERROR] Cannot test parameter: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Check Terminal Services WMI
Write-Host "`n[3] Terminal Services WMI availability:" -ForegroundColor Yellow
try {
    $tsWmi = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root\CIMV2\TerminalServices -ErrorAction Stop
    if ($tsWmi) {
        Write-Host "    [OK] WMI TerminalServices namespace available" -ForegroundColor Green
        Write-Host "    AllowTSConnections: $($tsWmi.AllowTSConnections)" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "    [ISSUE] WMI TerminalServices NOT available" -ForegroundColor Red
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    This may prevent WMIC reset from working" -ForegroundColor Yellow
}

# Test 4: Check RDP Listener DLL
Write-Host "`n[4] RDP Listener DLL status:" -ForegroundColor Yellow
$termsrvDll = "C:\Windows\System32\termsrv.dll"
if (Test-Path $termsrvDll) {
    $dllInfo = Get-Item $termsrvDll
    Write-Host "    [OK] termsrv.dll exists" -ForegroundColor Green
    Write-Host "    Version: $($dllInfo.VersionInfo.FileVersion)" -ForegroundColor Cyan
    Write-Host "    Modified: $($dllInfo.LastWriteTime)" -ForegroundColor Cyan
    
    # Check if DLL is locked
    try {
        $stream = [System.IO.File]::Open($termsrvDll, 'Open', 'Read', 'None')
        $stream.Close()
        Write-Host "    [OK] DLL is not locked" -ForegroundColor Green
    }
    catch {
        Write-Host "    [INFO] DLL is locked (normal when service is running)" -ForegroundColor Cyan
    }
}
else {
    Write-Host "    [ERROR] termsrv.dll NOT FOUND!" -ForegroundColor Red
}

# Test 5: Check if services can be restarted
Write-Host "`n[5] Testing service restart capability:" -ForegroundColor Yellow
Write-Host "    Testing with Print Spooler (safe to restart)..." -ForegroundColor Cyan
try {
    $beforeStatus = (Get-Service -Name "Spooler").Status
    Stop-Service -Name "Spooler" -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Start-Service -Name "Spooler" -ErrorAction Stop
    Start-Sleep -Seconds 2
    $afterStatus = (Get-Service -Name "Spooler").Status
    
    if ($beforeStatus -eq $afterStatus) {
        Write-Host "    [OK] Service restart works (Before: $beforeStatus, After: $afterStatus)" -ForegroundColor Green
    }
    else {
        Write-Host "    [WARNING] Service state changed unexpectedly" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    [ERROR] Service restart failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Check Windows Firewall status
Write-Host "`n[6] Windows Firewall status:" -ForegroundColor Yellow
try {
    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
    foreach ($profile in $fwProfiles) {
        $status = if ($profile.Enabled) { "[ON]" } else { "[OFF]" }
        $color = if ($profile.Enabled) { "Yellow" } else { "Green" }
        Write-Host "    $status $($profile.Name) Profile" -ForegroundColor $color
    }
}
catch {
    Write-Host "    [ERROR] Cannot query firewall: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 7: Check Security Policies
Write-Host "`n[7] Security Policies:" -ForegroundColor Yellow
$uacEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA
if ($uacEnabled -eq 1) {
    Write-Host "    [INFO] UAC is enabled (may affect remote admin)" -ForegroundColor Yellow
}
else {
    Write-Host "    [OK] UAC is disabled" -ForegroundColor Green
}

# Test 8: Check current RDP listener state
Write-Host "`n[8] Current RDP Listener State:" -ForegroundColor Yellow
$port3389 = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($port3389) {
    Write-Host "    [OK] Port 3389 is currently LISTENING" -ForegroundColor Green
    $port3389 | Select-Object LocalAddress, LocalPort, State, OwningProcess | Format-Table
}
else {
    Write-Host "    [ISSUE] Port 3389 is NOT listening" -ForegroundColor Red
    Write-Host "    This is why RDP doesn't work!" -ForegroundColor Yellow
}

# Test 9: Check Event Logs for errors
Write-Host "`n[9] Recent TermService errors:" -ForegroundColor Yellow
try {
    $errors = Get-EventLog -LogName System -Source TermService -EntryType Error -Newest 3 -ErrorAction SilentlyContinue
    if ($errors) {
        foreach ($err in $errors) {
            Write-Host "    [ERROR] EventID $($err.EventID): $($err.Message.Substring(0, [Math]::Min(100, $err.Message.Length)))..." -ForegroundColor Red
        }
    }
    else {
        Write-Host "    [OK] No recent TermService errors" -ForegroundColor Green
    }
}
catch {
    Write-Host "    [INFO] Cannot read event log" -ForegroundColor Cyan
}

# Summary
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   DIAGNOSIS SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$needsRestart = $false
$reasons = @()

if (-not $port3389) {
    $needsRestart = $true
    $reasons += "Port 3389 not listening"
}

if (-not $hasForce) {
    $reasons += "Old Windows version (no -Force support)"
}

if ($reasons.Count -gt 0) {
    Write-Host "This machine MAY need restart because:" -ForegroundColor Yellow
    foreach ($reason in $reasons) {
        Write-Host "  - $reason" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Solutions:" -ForegroundColor Yellow
    Write-Host "  1. Run: .\Fix-RDP.ps1" -ForegroundColor Cyan
    Write-Host "  2. If still fails: .\Safe-Restart.ps1" -ForegroundColor Cyan
}
else {
    Write-Host "No obvious issues detected!" -ForegroundColor Green
}
Write-Host ""
