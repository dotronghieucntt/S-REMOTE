# ZeroTier Quick Setup Tool

## Vấn đề đã Fix

### Version mới này fix các lỗi:
1. ✅ **LocalAccountTokenFilterPolicy** - Thiết lập đúng để cho phép remote admin
2. ✅ **Firewall** - 3 phương pháp cấu hình (PowerShell + netsh backup)
3. ✅ **Service Restart** - Đúng thứ tự: Stop all → Start TermService → Start SessionEnv → Start UmRdpService
4. ✅ **Port Verification** - Kiểm tra port 3389 đang listening sau khi restart service

## Cách Dùng

### 1. Chạy Tool (Run as Administrator)
```powershell
.\ZeroTier-QuickSetup.exe
```

**Nhập:**
- Network ID: `743993800f9dac1e` (hoặc network ID của bạn)
- Username: tên user để login RDP
- Password: mật khẩu (hoặc click "Random")

Click **START INSTALLATION** và đợi hoàn tất.

### 2. Verify Cấu Hình
Sau khi cài xong, chạy script verify:
```powershell
powershell -ExecutionPolicy Bypass -File .\Verify-RDP.ps1
```

Script sẽ kiểm tra:
- ✓ Registry settings
- ✓ TermService status
- ✓ Port 3389 listening
- ✓ Firewall rules
- ✓ ZeroTier IP
- ✓ RDP connectivity

### 3. Nếu Vẫn Không Connect Được

#### Option A: Chạy Emergency Fix
```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-RDP.ps1
```

#### Option B: Manual Fix Commands
```powershell
# Fix registry
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Force

# Restart service
net stop termservice
net start termservice

# Check port
Get-NetTCPConnection -LocalPort 3389
```

## Các Vấn Đề Thường Gặp

### ⚠️ Vẫn Phải Restart Máy Mới Kết Nối Được

**Nguyên nhân:** RDP listener chưa được tạo/bind đúng cách

**Solution 1 - Chạy Fix Script:**
```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-RDP.ps1
```
Script này sẽ:
- Reset RDP configuration via WMIC
- Apply WMI Terminal Service settings
- Force recreate RDP listener
- Restart services với đúng thứ tự
- Verify port 3389 listening

**Solution 2 - Check Listener:**
```powershell
powershell -ExecutionPolicy Bypass -File .\Test-Listener.ps1
```
Xem có message "NO LISTENER on port 3389" không?

**Solution 3 - Manual Commands:**
```powershell
# Reset RDP via WMIC
wmic /namespace:\\root\CIMV2\TerminalServices PATH Win32_TerminalServiceSetting WHERE (__CLASS!="") CALL SetAllowTSConnections 1

# Restart services
net stop termservice
net start termservice

# Check listener
netstat -ano | findstr :3389
```

**Last Resort - Nếu vẫn không được:**
```powershell
Restart-Computer
```
Sau khi restart, RDP sẽ hoạt động vì registry đã được set đúng.

### Lỗi: "Port 3389 not listening"
**Nguyên nhân:** Service chưa khởi động hoàn toàn

**Fix:**
```powershell
.\Fix-RDP.ps1
# Hoặc
net stop termservice && net start termservice
```

### Lỗi: "Cannot connect from remote machine"
**Nguyên nhân:** LocalAccountTokenFilterPolicy chưa được set

**Fix:**
```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Force
Restart-Service TermService
```

### Lỗi: "No ZeroTier IP"
**Nguyên nhân:** Device chưa được authorize trong ZeroTier Central

**Fix:**
1. Vào https://my.zerotier.com
2. Chọn network: `743993800f9dac1e`
3. Tìm device mới và check ✓ vào "Auth"
4. Đợi 10-30 giây để nhận IP

## Thông Tin Kỹ Thuật

### Registry Keys Modified
```
HKLM:\System\CurrentControlSet\Control\Terminal Server
  - fDenyTSConnections = 0
  - AllowTSConnections = 1

HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
  - UserAuthentication = 0
  - SecurityLayer = 0
  - PortNumber = 3389

HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
  - LocalAccountTokenFilterPolicy = 1  ← CRITICAL!
```

### Services Modified
- **TermService** - Remote Desktop Services (MUST be Running)
- **SessionEnv** - Remote Desktop Configuration
- **UmRdpService** - Remote Desktop Services UserMode Port Redirector

### Firewall Rules
- Built-in "Remote Desktop" group enabled
- Custom rule "RDP-Custom-3389" (PowerShell)
- Custom rule "RDP-Netsh-3389" (netsh backup)

## Files Included

- `ZeroTier-QuickSetup.exe` - Main tool
- `Verify-RDP.ps1` - Verification script (8 checks)
- `Fix-RDP.ps1` - Emergency fix script
- `Build-EXE.bat` - Rebuild tool from source
- `Rebuild.bat` - Force rebuild (kills + deletes old EXE)
- `icon.ico` - Custom icon

## Yêu Cầu

- Windows 10/11 hoặc Windows Server 2016+
- PowerShell 5.1+
- Admin rights
- Internet connection (để download ZeroTier)

## Không Cần Restart Máy!

Tool này **KHÔNG yêu cầu restart máy**. 

Nếu RDP không hoạt động ngay:
1. Đợi 30 giây cho services khởi động
2. Chạy `.\Verify-RDP.ps1` để check
3. Nếu vẫn lỗi, chạy `.\Fix-RDP.ps1`

## Support

Nếu vẫn gặp vấn đề:
1. Chạy `.\Verify-RDP.ps1` và gửi kết quả
2. Check Event Viewer → Windows Logs → System (lọc TermService)
3. Run: `Get-Service TermService | Select-Object *`
