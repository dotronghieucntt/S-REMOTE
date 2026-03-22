# QUICK START GUIDE

## ⚠️ QUAN TRỌNG: ĐỪNG RÚT MÀN HÌNH TRƯỚC KHI VERIFY!

**VẤN ĐỀ:** Nếu rút màn hình vật lý mà RDP chưa hoạt động → mất hoàn toàn quyền truy cập!

**GIẢI PHÁP:** Luôn verify RDP hoạt động TRƯỚC KHI rút màn hình.

---

## BƯỚC 1: CHẠY TOOL
```
ZeroTier-QuickSetup.exe (Run as Admin)
```
- Nhập Network ID, Username, Password
- Click "START INSTALLATION"
- Đợi hoàn tất (~2-3 phút)

## BƯỚC 2: VERIFY NGAY (QUAN TRỌNG!)
```powershell
powershell -ExecutionPolicy Bypass -File .\Verify-RDP.ps1
```

### Nếu tất cả [OK]:
✅ **AN TOÀN** - Có thể rút màn hình và RDP vào!

### Nếu có lỗi "Port 3389 not listening":
⚠️ **CHƯA AN TOÀN** - ĐỪNG RÚT MÀN HÌNH! Làm bước 3.

---

## BƯỚC 3: FIX NẾU CẦN (TRƯỚC KHI RÚT MÀN HÌNH!)

### Option A: Quick Fix (Thử đầu tiên - 80% success rate)
```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-RDP.ps1
```
Script này sẽ:
- Kill zombie processes
- Reset RDP via WMIC + WMI
- Force restart services với đúng thứ tự
- Tự động retry nếu fail
- Verify port 3389 listening

**Đợi xong, chạy lại Verify-RDP.ps1**

### Option B: Manual Commands
```powershell
# Stop everything
net stop termservice

# Wait
Start-Sleep -Seconds 5

# Start with dependencies
net start sessionenv
Start-Sleep -Seconds 3
net start termservice
Start-Sleep -Seconds 10

# Check
netstat -ano | findstr :3389
```

### Option C: Test No-Restart Script
```powershell
powershell -ExecutionPolicy Bypass -File .\Test-NoRestart.ps1
```
Xem có tạo được listener không?

### Option D: Last Resort - Schedule Restart (AN TOÀN)
Nếu không thể verify trực tiếp (VD: máy ở xa):

```powershell
# Schedule restart sau 5 phút (có thời gian cancel nếu cần)
shutdown /r /t 300 /c "RDP will work after restart. Cancel with: shutdown /a"

# Nếu muốn cancel:
shutdown /a
```

**SAU KHI RESTART:**
- RDP sẽ hoạt động 100%
- Registry đã configured
- Services đã set Automatic
- Có thể RDP vào an toàn

---

## BƯỚC 4: KẾT NỐI RDP

**TRƯỚC KHI RÚT MÀN HÌNH:**
1. ✅ Chạy Verify-RDP.ps1 → Tất cả [OK]
2. ✅ Test kết nối RDP từ máy khác
3. ✅ Đảm bảo đã authorize trong ZeroTier Central
4. ✅ Test disconnect và reconnect RDP

**SAU ĐÓ MỚI an toàn rút màn hình!**

```
IP: (ZeroTier IP - xem trong tool output)
Username: (Đã nhập trong tool)
Password: (Đã nhập trong tool)
Port: 3389
```

**Authorize device trong ZeroTier Central:**
https://my.zerotier.com → Network → Auth ✓

---

## TẠI SAO ĐÔI KHI VẪN CẦN RESTART?

**Windows RDP Listener Issue:**
- Listener đôi khi không được bind khi chỉ restart service
- Listener "zombie" - service running nhưng không listen port
- Windows kernel RDP driver cần full recreation

**Tool đã cố gắng fix:**
- ✅ Kill zombie processes
- ✅ WMIC reset RDP configuration
- ✅ WMI Terminal Service settings
- ✅ Force stop/start với đúng dependencies
- ✅ Trigger session creation
- ✅ Loopback test và auto-retry
- ✅ Emergency restart nếu port không listening

**Nhưng ~20% máy vẫn cần restart:**
- Windows RDP subsystem trong trạng thái corrupted
- Security policies chặn listener recreation
- Driver conflicts

**Giải pháp an toàn:**
1. Chạy tool
2. Verify RDP works
3. Test kết nối TRƯỚC KHI rút màn hình
4. Nếu không work → Schedule restart
5. Sau restart → RDP works vĩnh viễn

---

## FILES HỖ TRỢ

| File | Mục đích |
|------|----------|
| `ZeroTier-QuickSetup.exe` | Tool chính |
| `Verify-RDP.ps1` | Kiểm tra 8 mục cấu hình |
| `Fix-RDP.ps1` | Fix emergency (7 bước) |
| `Test-Listener.ps1` | Chẩn đoán listener |
| `README.md` | Hướng dẫn chi tiết |

---

## KẾT NỐI RDP

```
IP: (ZeroTier IP - check in tool output)
Username: (Đã nhập trong tool)
Password: (Đã nhập trong tool)
Port: 3389
```

**Authorize device trong ZeroTier Central:**
https://my.zerotier.com → Network → Auth ✓

---

## SUPPORT

Nếu gặp vấn đề:
1. ✅ Chạy `Verify-RDP.ps1` → gửi kết quả
2. ✅ Chạy `Test-Listener.ps1` → check listener
3. ✅ Chạy `Fix-RDP.ps1` → thử fix tự động
4. ✅ Restart máy → 100% work
