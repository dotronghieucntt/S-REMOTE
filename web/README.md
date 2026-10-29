# REMOTE Web — remote.novivo.net

Landing page giới thiệu và phát hành **NOVIVO Remote Desktop** (app trong thư mục cha `SOURCE/REMOTE`).

## Cấu trúc

```
web/
├─ server.js                     máy chủ HTTP thuần Node (không cần npm install)
├─ public/
│  ├─ index.html                 trang chủ
│  ├─ dieu-khoan.html            Điều khoản sử dụng            (URL: /dieu-khoan)
│  ├─ mien-tru-trach-nhiem.html  Miễn trừ trách nhiệm          (URL: /mien-tru-trach-nhiem)
│  ├─ styles.css  main.js        giao diện + tương tác
│  ├─ assets/logo.png            logo 256px · logo-512.png cho OG image
│  ├─ favicon.ico  robots.txt  sitemap.xml
├─ data/stats.json               bộ đếm lượt tải (tự sinh)
└─ logs/                         log PM2 (tự sinh)
```

## Endpoint

| Đường dẫn | Việc |
|---|---|
| `/` | trang landing |
| `/dieu-khoan` · `/mien-tru-trach-nhiem` | hai trang pháp lý (URL sạch, server tự thêm `.html`) |
| `/health` | healthcheck — NMS CONTROL gọi mỗi vòng monitor |
| `/api/release` | JSON: phiên bản, dung lượng + SHA-256 của cả bản EXE và bản Full |
| `/download` (alias `/tai-ve`) | tải bản EXE gọn, hỗ trợ HTTP Range |
| `/download-full` (alias `/tai-ve-full`) | tải bản Full `.zip`, hỗ trợ HTTP Range |

## Bản phát hành được dò tự động

Server **không hardcode phiên bản**. Mỗi lần khởi động và cứ 5 phút một lần, nó quét:

1. `SOURCE/REMOTE/dist/` — bản vừa build
2. `SOURCE/REMOTE/releases/vX.Y.Z/` — các bản đã phát hành

rồi lấy **phiên bản cao nhất có file thật**, đọc dung lượng và băm SHA-256 (chỉ băm lại khi file đổi).
Chạy `Build-Release.ps1` xong là trang tự cập nhật số phiên bản, dung lượng và hash — không phải sửa code.

## Chạy

PM2 quản lý qua `SOURCE/NOVIVO/ecosystem.config.js`:

- `novivo-remote` — `node server.js`, cổng **5301**, chỉ nghe 127.0.0.1
- `novivo-tunnel-remote` — cloudflared tunnel `novivo-remote`
  (`39e85e22-7296-4a73-ae53-ef3df4174409`), config tại
  `SOURCE/NOVIVO/infra/cloudflared/novivo-remote/config.yml`

Kích hoạt lần đầu: chạy `SOURCE/REMOTE/KICH-HOAT-REMOTE.bat` **bằng tài khoản đang giữ PM2 daemon**.

Chạy thử tay khi sửa giao diện:

```bat
cd C:\Users\HOST\Desktop\NOVIVO\SOURCE\REMOTE\web
node server.js
```

rồi mở http://127.0.0.1:5301 (nhớ tắt trước khi để PM2 chiếm lại cổng 5301).

## Hộp xác nhận trước khi tải (clickwrap)

Mọi liên kết `/download` và `/download-full` bị chặn cho tới khi người dùng tick đồng ý Điều khoản +
Miễn trừ trách nhiệm — trong đó có cam kết **có quyền quản trị hợp pháp với máy sẽ cài** và
**tuân thủ giấy phép Windows**. Logic nằm trong `public/main.js`:

- `TERMS_VERSION` — sửa nội dung pháp lý xong thì tăng số này, người đã đồng ý bản cũ sẽ được hỏi lại.
- Lưu ở `localStorage['remote.novivo.terms']`, không gửi về máy chủ.
- Xem nhanh giao diện: `?consent=preview` (thêm `&checked=1` để xem trạng thái đã tick).

## Sửa nội dung

Chữ nằm trong `public/*.html` — sửa xong chỉ cần `pm2 restart novivo-remote`
(hoặc bấm 🔄 ở dòng **REMOTE Web** trong NMS CONTROL); không có bước build.

> Sửa `styles.css` / `main.js` xong nhớ tăng số `?v=` trong cả ba file HTML
> (Cloudflare cache file tĩnh ở edge — đổi query là ép tải bản mới ngay).

## Nội dung pháp lý

Hai trang pháp lý trích lược: Bộ luật Hình sự 2015 (sđbs 2017) Điều 225, 286, 288, **289**, 290;
Luật Sở hữu trí tuệ 2005 (sđbs 2009 · 2019 · 2022) Điều 20, 22, 25, 28; Nghị định 131/2013/NĐ-CP
Điều 2, 15, 18; Nghị định 15/2020/NĐ-CP (sđbs 14/2022) Điều 80; Luật An ninh mạng 2018 Điều 8;
Luật An toàn thông tin mạng 2015 Điều 7; Bộ luật Dân sự 2015 Điều 385; Luật Giao dịch điện tử 2023;
Nghị định 13/2023/NĐ-CP; Luật Bảo vệ quyền lợi người tiêu dùng 2023.

Trọng tâm khác với trang TAIWIN: ngoài bản quyền Windows còn nhấn mạnh **Điều 289 — xâm nhập trái phép**
(chỉ được cài lên máy mình có quyền) và ranh giới **đa phiên RDP cần Windows Server + RDS CAL**.
