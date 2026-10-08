# Build & phát hành NOVIVO Remote Desktop

Đọc hết trang này trước khi build. Mọi lần build đều theo đúng một đường dưới đây.

## Build: một lệnh

```powershell
cd C:\Users\HOST\Desktop\NOVIVO\SOURCE\REMOTE
git fetch origin; git status          # repo có commit đẩy từ máy khác, kéo về trước
.\Build-Release.ps1 -SkipGitHub       # build + tự kiểm + đưa vào releases/
```

- Bỏ `-SkipGitHub` thì script còn commit "Release vX.Y.Z", gắn tag và push lên `github.com/dotronghieucntt/S-REMOTE`. Chỉ làm khi được bảo.
- **Không gọi `pyinstaller` trực tiếp.** Cũng không sửa tay `dist/` hay `releases/`.
- Script tự `Stop-Process` mọi tiến trình có tên `*NOVIVO*` để mở khoá `dist/`. Trước khi build, kiểm `Get-Process *NOVIVO*`.
- Python: script tự chọn bản Python 3 có PyInstaller. Trên máy chủ là `C:\Users\HOST\AppData\Local\Programs\Python\Python311`. Thư mục `.venv` trong repo hỏng (trỏ sang `C:\Users\HIEU`), đừng dùng.
- Cần cài sẵn: `pyinstaller customtkinter pillow packaging`. Thiếu gì thì spec báo tên module và dừng.

Sửa `NOVIVO-Backend.ps1` thì chạy `powershell -ExecutionPolicy Bypass -File Tests\Run-Scenarios.ps1` trước khi build. Bộ test này chạy các hàm thật trên máy giả lập (50 ca: OS, RDP, Tailscale, dịch vụ khởi động cùng Windows, chống sleep), **không** đụng tới máy đang build. Tuyệt đối không chạy backend thật trên máy chủ.

## Script làm gì (`Build-Release.ps1`)

| Bước | Việc | Hỏng thì |
|---|---|---|
| 0 | Tìm Python + PyInstaller | dừng |
| 1 | Đọc `version.txt`: đây là số bản **sắp** build | — |
| 2 | Xoá `build_tmp/`, `dist/` | — |
| 3 | PyInstaller với `NOVIVO-RemoteDesktop.spec` | dừng, đọc dòng `[spec] DỪNG BUILD` |
| 4 | **Self-test**: chạy chính 2 exe vừa build với `--selftest` | xoá `dist/`, dừng |
| 5 | Chép sang `releases/vX.Y.Z/` (exe + thư mục Full + zip) | — |
| 6 | Quét bí mật (`tskey-…`, token GitHub) trong exe/zip | dừng |
| 7 | Tăng `version.txt` lên +1 (patch) | — |

Build lỗi ở bước nào thì `version.txt` vẫn giữ nguyên, sửa xong chạy lại đúng lệnh cũ.

## Spec tự lo gì (`NOVIVO-RemoteDesktop.spec`)

Thêm code vào `NOVIVO-App.py` thì **không phải khai gì thêm** trong spec:

1. **Import**: đọc AST của app, lấy mọi `import` / `from … import` (kể cả import nằm trong hàm) làm hiddenimports. Phần kéo theo gián tiếp (ví dụ `urllib.request` kéo theo `email`) thì PyInstaller tự lần.
2. **Thư viện ngoài**: import nào không thuộc thư viện chuẩn thì gom trọn bằng `collect_all` (code + data + dll). Spec còn lần theo requirements trong metadata để gom luôn thư viện phụ thuộc. Hiện tại là `customtkinter`, `PIL`, `darkdetect`, `packaging`.
3. **File đi kèm**: quét các chuỗi `os.path.join(_BUNDLE, "…")` và `_asset("…")` trong app rồi bundle vào gốc. Thiếu file thì dừng build.
4. **Icon + version**: tự tạo `build_tmp/icon.ico` đủ cỡ 16→256 từ `LOGO KO CHU.png`. Tự tạo version resource (`version_info.py` → Properties → Details của exe).
5. **Self-test**: ghi `_selftest.json` (danh sách module + file cần có) vào bundle và gắn runtime hook `pyi_hooks/pyi_rth_selftest.py`.
6. **Rào chắn**: trong `EXCLUDES` mà có module thư viện chuẩn thì dừng build ngay.

Mỗi lần build, log in ra một bảng `[spec] …`: phiên bản, import, thư viện ngoài, file đi kèm, loại trừ. Đọc bảng đó để biết exe chứa gì.

### Khi nào phải sửa spec

Chỉ sửa khối **0. CẤU HÌNH** ở đầu file:

- `EXTRA_HIDDEN`: module nạp động (`importlib.import_module("x")`, `__import__`), AST không thấy được.
- `EXTRA_DATAS`: file cần đi kèm nhưng app không gọi qua `_BUNDLE`/`_asset`. Tốt hơn hết là sửa app để gọi qua `_asset("tên")`.
- `EXCLUDES`: **chỉ** ghi thư viện ngoài to mà app không dùng. Không bao giờ ghi module thư viện chuẩn (`email`, `html`, `xml`…).

### Quy ước khi viết app

- File đi kèm (`.ps1`, ảnh, txt) phải được gọi qua `os.path.join(_BUNDLE, "tên")` hoặc `_asset("tên")`. Viết kiểu khác thì spec không thấy.
- File người dùng sửa được (`servers.json`) đặt ở `BASE_DIR`, cạnh exe, không bundle.
- Không bao giờ để key/token trong source. Bước 6 sẽ chặn, và trang tải về cũng tự chặn.

## Self-test chạy tay

```powershell
$env:__COMPAT_LAYER = 'RunAsInvoker'      # bỏ qua hộp UAC (manifest đòi admin)
& ".\releases\v1.0.19\NOVIVO Remote Desktop v1.0.19.exe" --selftest "$env:TEMP\st.json"
$env:__COMPAT_LAYER = $null
Get-Content "$env:TEMP\st.json"           # {"ok": true/false, "errors": [...], "checked": {...}}
```

Self-test kiểm: import đủ module, có đủ file đi kèm, Tcl/Tk khởi tạo được, SSL tạo được context. App không chạy, không cần admin. Mở thử giao diện thật thì vẫn phải bấm UAC.

## Phát hành lên remote.novivo.net

- Máy chủ landing `web/server.js` (PM2 `novivo-remote`, cổng 5301) tự quét `releases/vX.Y.Z/` và `dist/`, rồi phát bản **cao nhất có file**. Quét lại mỗi 5 phút, hoặc ngay khi có người bấm tải. Build xong không cần restart.
- Làm mới ngay: `Invoke-WebRequest -Method Head http://127.0.0.1:5301/download` (gọi HEAD không cộng lượt tải). Xem bản đang phát ở `https://remote.novivo.net/api/release`.
- **Gỡ bản hỏng**: chuyển `releases/vX.Y.Z/` **và** `dist/` sang `backupfiles/…`, xoá exe cùng tên ở gốc repo, rồi gọi HEAD `/download`. Trang sẽ lùi về bản trước.
- Chỉ phải restart `novivo-remote` khi sửa `web/server.js`. Restart cần UAC: `pm2 restart novivo-remote` qua `Start-Process -Verb RunAs`, không gõ `pm2` thẳng trong session.

## Key Tailscale dùng chung (mã mở khoá)

- Gõ mã (6–12 chữ số; dấu cách, chấm, gạch đều bỏ qua) vào ô key ở chế độ Tailscale. Mã bị che `•` trong lúc gõ. Ngừng tay 0,9 giây là app tự gọi `POST https://remote.novivo.net/api/ts-key`. Enter, rời ô hoặc bấm START cũng gửi; bấm START thì mở khoá xong sẽ tự chạy tiếp.
- Thành công: ô hiện `••••` xanh, dòng chữ xanh hiện ngay dưới danh sách server. Key chỉ nằm trong RAM, không ghi `servers.json`. Mã cũng không bao giờ được lưu hay bị dùng như key.
- Thất bại: dòng chữ đỏ ngay dưới danh sách, chia 3 loại: sai mã (sửa lại mã), bị khoá (số phút phải chờ), lỗi mạng/máy chủ (bấm Enter để thử lại). Lỗi cũng ghi vào INSTALLATION LOG. Không có popup.
- HTTPS dùng kho chứng chỉ Windows **cộng thêm certifi**. Chứng chỉ của remote.novivo.net do Let's Encrypt YE1 cấp, máy Windows mới cài có thể chưa có chứng chỉ gốc của nó. Self-test gọi thử `/health` chỉ bằng certifi để chắc chắn đường này chạy được.
- Key + mã nằm ở `web/.env` (`TS_SHARED_AUTHKEY`, `TS_UNLOCK_CODE`), git bỏ qua. Đổi xong không cần restart.
- Sửa gì ở phần này thì chạy lại `Tests/unlock_flow_test.py` (27 ca, hướng dẫn ở đầu file) trước khi build.
- Chống dò: sai 5 lần thì khoá IP đó 15 phút (IPv6 tính theo dải /64); cả máy chủ sai 30 lần/giờ thì khoá hết 1 giờ. Mã **sai độ dài** (app gửi khi người gõ dừng giữa chừng) vẫn trả "Sai mã." nhưng không tính lượt.

## Lỗi từng gặp (đừng lặp lại)

| Bản | Lỗi | Gốc | Đã chặn bằng |
|---|---|---|---|
| ≤ v1.0.15 | key Tailscale nằm trong exe | hardcode trong source | bước 6 + máy chủ chặn phát |
| v1.0.18 (lần 1) | mở lên chết: `No module named 'email'` | spec cũ `excludes=["email",…]`, `urllib.request` cần `email` | rào chắn EXCLUDES + self-test |
| ≤ v1.0.18 | exe không có version resource | bước tạo version chạy trước bước xoá `build_tmp/` | spec tự tạo |
| ≤ v1.0.18 | icon mờ, chỉ có cỡ 16px | lưu ICO từ ảnh 16px nên Pillow bỏ hết cỡ to hơn | spec tạo từ logo 1024px |
| (test) | self-test báo Tcl/Tk lỗi giả | hook tự viết chạy trước hook Tk của PyInstaller | hook tự dò `init.tcl` |

Test logic app từ mã nguồn (`python NOVIVO-App.py`) **không thay được** self-test: Python đầy đủ thì không lộ module bị thiếu trong exe.
