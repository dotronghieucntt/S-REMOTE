# NOVIVO Remote Desktop

Build hoặc phát hành exe: **đọc `BUILD.md` trước** rồi làm đúng theo đó.

- Build chỉ bằng `.\Build-Release.ps1 -SkipGitHub`. Không gọi `pyinstaller` trực tiếp.
- Đóng gói (import, thư viện, file đi kèm, icon, version) do `NOVIVO-RemoteDesktop.spec` tự dò. Chỉ sửa khối `0. CẤU HÌNH` của spec.
- Không ghi module thư viện chuẩn vào `EXCLUDES`.
- Build đỏ ở bước self-test là bản đó hỏng thật. Sửa nguyên nhân, đừng bỏ bước.
- Trước khi sửa code: `git fetch` (repo `S-REMOTE` có commit đẩy từ máy khác).
- Không để key/token trong source. Key Tailscale dùng chung nằm ở `web/.env`.
