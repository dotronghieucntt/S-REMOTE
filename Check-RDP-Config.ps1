# Script kiểm tra cấu hình Remote Desktop
# Chạy script này để verify xem RDP đã được cấu hình đúng chưa

Write-Host "=== KIỂM TRA CẤU HÌNH REMOTE DESKTOP ===" -ForegroundColor Cyan
Write-Host ""

# Check 1: Registry Settings
Write-Host "[1] Kiểm tra Registry Settings..." -ForegroundColor Yellow
$fDenyTS = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections").fDenyTSConnections
$allowTS = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "AllowTSConnections" -ErrorAction SilentlyContinue).AllowTSConnections
$userAuth = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication").UserAuthentication
$secLayer = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer").SecurityLayer

if ($fDenyTS -eq 0) {
    Write-Host "   [OK] fDenyTSConnections = 0 (RDP enabled)" -ForegroundColor Green
} else {
    Write-Host "   [X] fDenyTSConnections = $fDenyTS (RDP disabled!)" -ForegroundColor Red
}

if ($allowTS -eq 1) {
    Write-Host "   [OK] AllowTSConnections = 1 (Connections allowed)" -ForegroundColor Green
} else {
    Write-Host "   [X] AllowTSConnections = $allowTS" -ForegroundColor Red
}

if ($userAuth -eq 0) {
    Write-Host "   [OK] UserAuthentication = 0 (NLA disabled)" -ForegroundColor Green
} else {
    Write-Host "   [X] UserAuthentication = $userAuth (NLA enabled!)" -ForegroundColor Red
}

if ($secLayer -eq 0) {
    Write-Host "   [OK] SecurityLayer = 0 (No SSL required)" -ForegroundColor Green
} else {
    Write-Host "   [!] SecurityLayer = $secLayer" -ForegroundColor Yellow
}

Write-Host ""

# Check 2: Services
Write-Host "[2] Kiểm tra Services..." -ForegroundColor Yellow
$termService = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
$umRdpService = Get-Service -Name "UmRdpService" -ErrorAction SilentlyContinue

if ($termService.Status -eq "Running") {
    Write-Host "   [OK] TermService is Running" -ForegroundColor Green
} else {
    Write-Host "   [X] TermService is $($termService.Status)" -ForegroundColor Red
}

if ($umRdpService.Status -eq "Running") {
    Write-Host "   [OK] UmRdpService is Running" -ForegroundColor Green
} else {
    Write-Host "   [!] UmRdpService is $($umRdpService.Status)" -ForegroundColor Yellow
}

Write-Host ""

# Check 3: Firewall Rules
Write-Host "[3] Kiểm tra Firewall Rules..." -ForegroundColor Yellow
$rdpRules = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
$enabledRules = $rdpRules | Where-Object {$_.Enabled -eq $true}
Write-Host "   [OK] Remote Desktop rules: $($enabledRules.Count) enabled / $($rdpRules.Count) total" -ForegroundColor Green

$ztRules = Get-NetFirewallRule -DisplayName "ZeroTier-RDP-*" -ErrorAction SilentlyContinue
if ($ztRules) {
    Write-Host "   [OK] ZeroTier RDP rules created: $($ztRules.Count)" -ForegroundColor Green
} else {
    Write-Host "   [!] No ZeroTier RDP rules found" -ForegroundColor Yellow
}

Write-Host ""

# Check 4: Firewall Status
Write-Host "[4] Kiểm tra Windows Firewall Status..." -ForegroundColor Yellow
$fwProfiles = Get-NetFirewallProfile
foreach ($profile in $fwProfiles) {
    if ($profile.Enabled -eq $false) {
        Write-Host "   [OK] $($profile.Name) Firewall: DISABLED (allow all)" -ForegroundColor Green
    } else {
        Write-Host "   [!] $($profile.Name) Firewall: ENABLED" -ForegroundColor Yellow
    }
}

Write-Host ""

# Check 5: Port 3389
Write-Host "[5] Kiểm tra Port 3389..." -ForegroundColor Yellow
$listening = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "   [OK] Port 3389 is LISTENING" -ForegroundColor Green
    Write-Host "   Listen on: $($listening.LocalAddress)" -ForegroundColor Gray
} else {
    Write-Host "   [X] Port 3389 is NOT listening!" -ForegroundColor Red
}

Write-Host ""

# Check 6: ZeroTier
Write-Host "[6] Kiểm tra ZeroTier..." -ForegroundColor Yellow
$ztService = Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
if ($ztService) {
    if ($ztService.Status -eq "Running") {
        Write-Host "   [OK] ZeroTier Service is Running" -ForegroundColor Green
    } else {
        Write-Host "   [X] ZeroTier Service is $($ztService.Status)" -ForegroundColor Red
    }
    
    # Get ZeroTier IP
    $ztCli = "C:\ProgramData\ZeroTier\One\zerotier-one_x64.exe"
    if (-not (Test-Path $ztCli)) {
        $ztCli = "C:\Program Files (x86)\ZeroTier\One\zerotier-one_x64.exe"
    }
    
    if (Test-Path $ztCli) {
        $networks = & $ztCli -q listnetworks 2>$null
        if ($networks) {
            Write-Host "   Networks:" -ForegroundColor Gray
            $networks | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        }
    }
} else {
    Write-Host "   [X] ZeroTier not installed!" -ForegroundColor Red
}

Write-Host ""

# Check 7: Current User
Write-Host "[7] Kiểm tra User Configuration..." -ForegroundColor Yellow
$currentUser = $env:USERNAME
$user = Get-LocalUser -Name $currentUser -ErrorAction SilentlyContinue

if ($user) {
    Write-Host "   [OK] User: $currentUser" -ForegroundColor Green
    Write-Host "   Enabled: $($user.Enabled)" -ForegroundColor Gray
    Write-Host "   PasswordNeverExpires: $($user.PasswordExpires -eq $null)" -ForegroundColor Gray
    
    # Check groups
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "   [OK] User is Administrator" -ForegroundColor Green
    } else {
        Write-Host "   [!] User is NOT Administrator" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== TỔNG KẾT ===" -ForegroundColor Cyan

$issues = 0
if ($fDenyTS -ne 0) { $issues++ }
if ($allowTS -ne 1) { $issues++ }
if ($userAuth -ne 0) { $issues++ }
if ($termService.Status -ne "Running") { $issues++ }
if (-not $listening) { $issues++ }

if ($issues -eq 0) {
    Write-Host "✓ Remote Desktop đã được cấu hình HOÀN TOÀN!" -ForegroundColor Green
    Write-Host "✓ Bạn có thể kết nối từ máy khác!" -ForegroundColor Green
} else {
    Write-Host "✗ Tìm thấy $issues vấn đề!" -ForegroundColor Red
    Write-Host "! Vui lòng chạy lại ZeroTier-QuickSetup.exe" -ForegroundColor Yellow
}

Write-Host ""
pause
