# ============================================
# HƯỚNG DẪN SỬ DỤNG ZEROTIER QUICKSETUP TOOL
# ============================================

## TÍNH NĂNG TỰ ĐỘNG:

Tool sẽ TỰ ĐỘNG thực hiện TẤT CẢ các bước sau:

### 1. CÀI ĐẶT ZEROTIER:
   ✓ Tải ZeroTier One MSI installer
   ✓ Cài đặt ZeroTier tự động (silent install)
   ✓ Join vào network của bạn

### 2. BẬT REMOTE DESKTOP HOÀN TOÀN:
   ✓ Enable Remote Desktop Service
   ✓ Set fDenyTSConnections = 0 (cho phép kết nối)
   ✓ Set AllowTSConnections = 1 (allow connections)
   ✓ TẮT NLA (Network Level Authentication)
   ✓ Set SecurityLayer = 0 (không yêu cầu SSL/TLS)
   ✓ Set MinEncryptionLevel = 1 (compatible với mọi client)
   ✓ Enable multiple sessions
   ✓ Khởi động Terminal Services (TermService)
   ✓ Khởi động UmRdpService

### 3. CẤU HÌNH FIREWALL:
   ✓ Enable tất cả rules trong group "Remote Desktop"
   ✓ Tạo rule riêng cho ZeroTier (port 3389, TCP, Any profile)
   ✓ Cho phép kết nối từ mọi mạng (Public, Private, Domain)

### 4. CẤU HÌNH USER:
   ✓ Tạo user mới (nếu chưa có)
   ✓ Set password cho user
   ✓ Thêm user vào group "Administrators"
   ✓ Thêm user vào group "Remote Desktop Users" (QUAN TRỌNG!)
   ✓ Enable user account
   ✓ Set password không bao giờ hết hạn

### 5. HIỂN THỊ THÔNG TIN:
   ✓ ZeroTier IP address
   ✓ Username
   ✓ Password
   ✓ Tự động copy thông tin vào clipboard


## CÁCH SỬ DỤNG:

### Bước 1: Chạy Tool
   - Double-click file: ZeroTier-QuickSetup.exe
   - Cho phép quyền Administrator khi được hỏi

### Bước 2: Nhập Thông Tin
   - Network ID: network ID của bạn (lấy tại https://my.zerotier.com)
   - Username: (mặc định là user hiện tại)
   - Password: Nhập hoặc bấm "Tạo Password Ngẫu Nhiên"

### Bước 3: Cài Đặt
   - Bấm nút "🚀 BẮT ĐẦU CÀI ĐẶT & SETUP"
   - Đợi khoảng 30-60 giây

### Bước 4: Authorize trên ZeroTier Central
   - Vào https://my.zerotier.com
   - Vào network của bạn
   - Tìm thiết bị mới join
   - CHECK vào ô "Auth?" để authorize

### Bước 5: Kết Nối Remote Desktop
   - Mở Remote Desktop Connection (mstsc.exe)
   - Nhập IP ZeroTier (đã hiển thị trong tool)
   - Nhập Username và Password
   - Kết nối!


## CHECKLIST - ĐẢM BẢO REMOTE DESKTOP HOẠT ĐỘNG:

□ ZeroTier đã cài đặt và join network thành công
□ Thiết bị đã được AUTHORIZE trên ZeroTier Central
□ Đã có ZeroTier IP (không phải "Chưa có IP")
□ Remote Desktop Service đang chạy (TermService)
□ User đã được thêm vào "Remote Desktop Users" group
□ User đã được thêm vào "Administrators" group
□ Password đã được set
□ Firewall đã allow port 3389
□ NLA đã được tắt (UserAuthentication = 0)
□ fDenyTSConnections = 0
□ AllowTSConnections = 1


## REGISTRY KEYS ĐÃ CẤU HÌNH:

HKLM:\System\CurrentControlSet\Control\Terminal Server
├─ fDenyTSConnections = 0 (cho phép RDP)
├─ AllowTSConnections = 1 (allow connections)
└─ fSingleSessionPerUser = 0 (cho phép nhiều session)

HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
├─ UserAuthentication = 0 (tắt NLA)
├─ SecurityLayer = 0 (không yêu cầu SSL)
└─ MinEncryptionLevel = 1 (low encryption, compatible)


## SERVICES ĐÃ KHỞI ĐỘNG:

- TermService (Terminal Services) - Automatic startup
- UmRdpService (Remote Desktop UserMode Port Redirector) - Automatic startup


## FIREWALL RULES ĐÃ TẠO:

- Remote Desktop - User Mode (TCP-In)
- Remote Desktop - Shadow (TCP-In)
- ZeroTier Remote Desktop (TCP 3389, Any profile)


## TROUBLESHOOTING:

### Lỗi: "Không kết nối được"
→ Kiểm tra thiết bị đã được AUTHORIZE trên ZeroTier Central chưa
→ Kiểm tra ZeroTier IP đã có chưa (ping thử)
→ Kiểm tra Firewall trên máy client

### Lỗi: "User hoặc password sai"
→ Kiểm tra Username chính xác (phân biệt hoa thường)
→ Kiểm tra Password đã nhập đúng
→ Thử reset password bằng tool lần nữa

### Lỗi: "Remote Desktop không được bật"
→ Chạy lại tool với quyền Administrator
→ Kiểm tra Windows version (Home edition không hỗ trợ RDP)

### Không thấy IP ZeroTier
→ Đợi 10-30 giây sau khi join network
→ Kiểm tra đã AUTHORIZE trên ZeroTier Central
→ Restart ZeroTier service: 
   net stop "ZeroTierOneService"
   net start "ZeroTierOneService"


## YÊU CẦU HỆ THỐNG:

- Windows 10/11 Pro, Enterprise, Education (Home KHÔNG hỗ trợ RDP)
- Windows Server 2016/2019/2022
- Quyền Administrator
- Kết nối Internet (để tải ZeroTier)


## LƯU Ý QUAN TRỌNG:

⚠️ Tool cần chạy với quyền ADMINISTRATOR
⚠️ Nhớ AUTHORIZE thiết bị trên ZeroTier Central
⚠️ Windows Home Edition KHÔNG hỗ trợ Remote Desktop
⚠️ Firewall của máy client cũng cần allow RDP
⚠️ Password nên mạnh và bảo mật


## HỖ TRỢ:

Nếu gặp vấn đề, kiểm tra:
1. Event Viewer → Windows Logs → Application
2. Services → Terminal Services đang chạy?
3. ZeroTier → Service đang online?
4. Registry keys đã được set đúng chưa?
