# Test RDP Listener Status
# Check if RDP listener is properly configured

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   RDP Listener Diagnostic" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Check 1: Query Terminal Services Configuration
Write-Host "`n[1] Terminal Services Configuration:" -ForegroundColor Yellow
try {
    $tsConfig = & qwinsta 2>&1
    Write-Host $tsConfig
}
catch {
    Write-Host "    [ERROR] Cannot query terminal services" -ForegroundColor Red
}

# Check 2: Check RDP-Tcp Listener
Write-Host "`n[2] RDP-Tcp Listener Status:" -ForegroundColor Yellow
try {
    $listener = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Host "    PortNumber: $($listener.PortNumber)" -ForegroundColor Green
        Write-Host "    fEnableWinStation: $($listener.fEnableWinStation)" -ForegroundColor Green
        Write-Host "    LanAdapter: $($listener.LanAdapter)" -ForegroundColor Green
    }
    else {
        Write-Host "    [ERROR] RDP-Tcp listener not found!" -ForegroundColor Red
    }
}
catch {
    Write-Host "    [ERROR] Cannot read listener config" -ForegroundColor Red
}

# Check 3: WMI Terminal Service Settings
Write-Host "`n[3] WMI Terminal Service Settings:" -ForegroundColor Yellow
try {
    $tsSettings = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root\CIMV2\TerminalServices -ErrorAction SilentlyContinue
    if ($tsSettings) {
        Write-Host "    AllowTSConnections: $($tsSettings.AllowTSConnections)" -ForegroundColor Green
        Write-Host "    TerminalServerMode: $($tsSettings.TerminalServerMode)" -ForegroundColor Green
    }
    else {
        Write-Host "    [WARNING] WMI TerminalServices not available" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "    [ERROR] WMI query failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check 4: Netstat for port 3389
Write-Host "`n[4] Network Listeners on Port 3389:" -ForegroundColor Yellow
$netstat = & netstat -ano | Select-String ":3389"
if ($netstat) {
    Write-Host $netstat -ForegroundColor Green
}
else {
    Write-Host "    [ERROR] NO LISTENER on port 3389!" -ForegroundColor Red
    Write-Host "    This is why RDP doesn't work!" -ForegroundColor Red
}

# Check 5: Service Dependencies
Write-Host "`n[5] Service Dependencies:" -ForegroundColor Yellow
$termSvc = Get-Service -Name "TermService"
Write-Host "    TermService: $($termSvc.Status) / $($termSvc.StartType)" -ForegroundColor $(if($termSvc.Status -eq 'Running'){'Green'}else{'Red'})

$sessionEnv = Get-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
if ($sessionEnv) {
    Write-Host "    SessionEnv: $($sessionEnv.Status) / $($sessionEnv.StartType)" -ForegroundColor $(if($sessionEnv.Status -eq 'Running'){'Green'}else{'Yellow'})
}

$umRdp = Get-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
if ($umRdp) {
    Write-Host "    UmRdpService: $($umRdp.Status) / $($umRdp.StartType)" -ForegroundColor $(if($umRdp.Status -eq 'Running'){'Green'}else{'Yellow'})
}

# Check 6: Recent Event Logs
Write-Host "`n[6] Recent TermService Events (Last 5):" -ForegroundColor Yellow
try {
    $events = Get-EventLog -LogName System -Source TermService -Newest 5 -ErrorAction SilentlyContinue
    if ($events) {
        $events | ForEach-Object {
            $color = if ($_.EntryType -eq 'Error') { 'Red' } elseif ($_.EntryType -eq 'Warning') { 'Yellow' } else { 'Green' }
            Write-Host "    [$($_.EntryType)] $($_.Message.Substring(0, [Math]::Min(80, $_.Message.Length)))..." -ForegroundColor $color
        }
    }
    else {
        Write-Host "    [INFO] No recent TermService events" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "    [WARNING] Cannot read event log" -ForegroundColor Yellow
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "   DIAGNOSIS COMPLETE" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If NO LISTENER on port 3389:" -ForegroundColor Yellow
Write-Host "  1. Run: .\Fix-RDP.ps1" -ForegroundColor Cyan
Write-Host "  2. Check Event Viewer for errors" -ForegroundColor Cyan
Write-Host "  3. Last resort: Restart-Computer" -ForegroundColor Magenta
Write-Host ""
