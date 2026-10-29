/**
 * REMOTE — máy chủ landing page cho NOVIVO Remote Desktop
 * https://remote.novivo.net
 *
 * Zero-dependency (chỉ dùng core Node). Chạy dưới PM2 cùng hệ NOVIVO,
 * cloudflared tunnel "novivo-remote" trỏ remote.novivo.net -> 127.0.0.1:5301
 *
 * Endpoint:
 *   GET /                   trang landing
 *   GET /dieu-khoan         · /mien-tru-trach-nhiem   (URL sạch, tự thêm .html)
 *   GET /health             healthcheck cho NMS CONTROL
 *   GET /api/release        thông tin bản phát hành mới nhất (quét thư mục releases/)
 *   GET /download           tải bản EXE gọn   (hỗ trợ HTTP Range)
 *   GET /download-full      tải bản Full .zip (hỗ trợ HTTP Range)
 *   POST /api/ts-key        đổi mã mở khoá lấy auth key Tailscale dùng chung (app gọi)
 */

'use strict';

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const { URL } = require('url');

// ── Cấu hình ────────────────────────────────────────────────────────────────
const PORT = Number(process.env.PORT) || 5301;
const HOST = process.env.HOST || '127.0.0.1';

const ROOT       = __dirname;
const PUBLIC_DIR = path.join(ROOT, 'public');
const DATA_DIR   = path.join(ROOT, 'data');
const STATS_FILE = path.join(DATA_DIR, 'stats.json');

// Thư mục dự án (cha của web/) — nơi chứa releases/ và version.txt
const APP_DIR      = path.dirname(ROOT);
const RELEASES_DIR = path.join(APP_DIR, 'releases');
const DIST_DIR     = path.join(APP_DIR, 'dist');

const STARTED_AT = Date.now();

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
};

// ── Trạng thái bản phát hành ────────────────────────────────────────────────
// Bản mới nhất được dò tự động: quét releases/vX.Y.Z (và dist/) rồi lấy phiên bản
// cao nhất CÓ FILE THẬT. Build xong bản mới là trang tự cập nhật, không sửa code.
let release = {
  version: null,
  exe: null,   // { filename, size, sizeText, sha256, updatedAt }
  zip: null,
  updatedAt: null,
  downloads: 0,
  source: null,
};

function fmtBytes(n) {
  if (!n) return '—';
  const u = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return n.toFixed(i === 0 ? 0 : 1) + ' ' + u[i];
}

function parseVersion(name) {
  const m = /v?(\d+)\.(\d+)\.(\d+)/.exec(name);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

function cmpVersion(a, b) {
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

function sha256File(file) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    fs.createReadStream(file)
      .on('error', reject)
      .on('data', (c) => hash.update(c))
      .on('end', () => resolve(hash.digest('hex')));
  });
}

// ── Chặn phát hành file có nhúng bí mật ─────────────────────────────────────
// Bản build v1.0.15 từng nhúng thẳng một auth key Tailscale vào EXE (và vào ZIP
// vì ZIP chứa chính EXE đó). Phát hành file như vậy là trao chìa khoá vào mạng
// riêng cho bất kỳ ai bấm tải. Quét trước khi cho tải, không tin vào trí nhớ.
const SECRET_PATTERNS = [
  { name: 'Tailscale auth key', re: /tskey-[a-zA-Z]+-[A-Za-z0-9-]{10,}/ },
  { name: 'GitHub token',       re: /gh[pousr]_[A-Za-z0-9]{20,}/ },
  { name: 'GitHub fine-grained token', re: /github_pat_[A-Za-z0-9_]{20,}/ },
];
const MAX_SCAN_BYTES = 200 * 1024 * 1024;

async function findSecrets(file, size) {
  if (size > MAX_SCAN_BYTES) return ['file quá lớn để quét'];
  let buf;
  try {
    buf = await fsp.readFile(file);
  } catch {
    return [];
  }
  const text = buf.toString('latin1');   // giữ nguyên byte, đủ để khớp ASCII
  const hits = [];
  for (const p of SECRET_PATTERNS) {
    if (p.re.test(text)) hits.push(p.name);
  }
  return hits;
}

async function describeFile(dir, filename, previous) {
  const full = path.join(dir, filename);
  const st = await fsp.stat(full);
  const updatedAt = st.mtime.toISOString();
  // Băm lại chỉ khi file đổi — file 20 MB nên không băm mỗi lần quét
  const unchanged = previous && previous.filename === filename &&
                    previous.size === st.size && previous.updatedAt === updatedAt;
  if (unchanged) {
    return Object.assign({}, previous, { path: full });
  }

  const secrets = await findSecrets(full, st.size);
  if (secrets.length) {
    console.error('[remote] CHAN PHAT HANH "' + filename + '" — file có nhúng: ' + secrets.join(', '));
  }

  return {
    filename,
    path: full,
    size: st.size,
    sizeText: fmtBytes(st.size),
    updatedAt,
    sha256: await sha256File(full),
    secrets,
  };
}

async function scanDir(dir, previous) {
  let names;
  try {
    names = await fsp.readdir(dir);
  } catch {
    return null;
  }
  const exeName = names.find((n) => n.toLowerCase().endsWith('.exe'));
  const zipName = names.find((n) => n.toLowerCase().endsWith('.zip'));
  if (!exeName && !zipName) return null;

  const out = {
    exe: exeName ? await describeFile(dir, exeName, previous && previous.exe) : null,
    zip: zipName ? await describeFile(dir, zipName, previous && previous.zip) : null,
  };

  // Bí mật nằm trong EXE thì bản ZIP cũng bẩn — nó gói chính EXE đó, chỉ khác là
  // đã nén nên chuỗi không lộ ra khi quét thô. Một file bẩn thì chặn cả bản build.
  const dirty = [out.exe, out.zip].filter((f) => f && f.secrets && f.secrets.length);
  if (dirty.length) {
    const reasons = Array.from(new Set(dirty.flatMap((f) => f.secrets)));
    for (const f of [out.exe, out.zip]) {
      if (f && !(f.secrets && f.secrets.length)) {
        f.secrets = ['cùng bản build với file có nhúng: ' + reasons.join(', ')];
        console.error('[remote] CHAN PHAT HANH "' + f.filename + '" — ' + f.secrets[0]);
      }
    }
  }

  return out;
}

async function refreshRelease() {
  const candidates = [];

  // 1. dist/ — bản vừa build, ưu tiên nếu phiên bản cao hơn
  try {
    const distNames = await fsp.readdir(DIST_DIR);
    const withVer = distNames.find((n) => parseVersion(n) && /\.(exe|zip)$/i.test(n));
    if (withVer) candidates.push({ dir: DIST_DIR, version: parseVersion(withVer), label: 'dist' });
  } catch { /* chưa build lần nào */ }

  // 2. releases/vX.Y.Z
  try {
    for (const name of await fsp.readdir(RELEASES_DIR)) {
      const v = parseVersion(name);
      if (v) candidates.push({ dir: path.join(RELEASES_DIR, name), version: v, label: 'releases/' + name });
    }
  } catch { /* chưa có thư mục releases */ }

  candidates.sort((a, b) => cmpVersion(b.version, a.version));

  // Trung phien ban (dist/ vua build vs releases/vX.Y.Z da dong goi): uu tien
  // thu muc co DU ca .exe lan .zip, dung de nut "Ban Full" chet vi dist thieu zip.
  for (let i = 0; i + 1 < candidates.length; i++) {
    const a = candidates[i], b = candidates[i + 1];
    if (cmpVersion(a.version, b.version) !== 0) continue;
    const count = async (c) => {
      try {
        const n = await fsp.readdir(c.dir);
        return (n.some((x) => /\.exe$/i.test(x)) ? 1 : 0) + (n.some((x) => /\.zip$/i.test(x)) ? 1 : 0);
      } catch { return 0; }
    };
    // eslint-disable-next-line no-await-in-loop
    if (await count(b) > await count(a)) { candidates[i] = b; candidates[i + 1] = a; }
  }

  for (const c of candidates) {
    const found = await scanDir(c.dir, release);
    if (!found) continue;                       // thư mục rỗng -> thử bản kế tiếp
    const changed = !release.version || release.source !== c.label;
    release.version = 'v' + c.version.join('.');
    release.exe = found.exe;
    release.zip = found.zip;
    release.source = c.label;
    release.updatedAt = (found.exe || found.zip).updatedAt;
    if (changed) {
      console.log('[remote] bản phát hành: ' + release.version + ' (' + c.label + ')');
    }
    return;
  }

  release.version = null;
  release.exe = null;
  release.zip = null;
  console.warn('[remote] chưa tìm thấy bản build nào trong ' + RELEASES_DIR);
}
setInterval(refreshRelease, 5 * 60000).unref();

// ── Bộ đếm lượt tải ─────────────────────────────────────────────────────────
async function loadStats() {
  try {
    const raw = JSON.parse(await fsp.readFile(STATS_FILE, 'utf8'));
    if (Number.isFinite(raw.downloads)) release.downloads = raw.downloads;
  } catch { /* lần chạy đầu chưa có file */ }
}

let statsDirty = false;
async function saveStats() {
  if (!statsDirty) return;
  statsDirty = false;
  try {
    await fsp.mkdir(DATA_DIR, { recursive: true });
    await fsp.writeFile(STATS_FILE, JSON.stringify({ downloads: release.downloads }, null, 2));
  } catch (err) {
    console.error('[remote] không ghi được stats:', err.message);
  }
}
setInterval(saveStats, 30000).unref();

// ── Mở khoá key Tailscale dùng chung ────────────────────────────────────────
// Key KHÔNG được nằm trong EXE (xem SECRET_PATTERNS). App gửi mã người dùng gõ vào
// ô key; đúng mã thì máy chủ trả key về. Mã + key để ở web/.env (git bỏ qua), đọc
// lại mỗi lần gọi nên đổi key/mã không cần restart.
//   TS_UNLOCK_CODE=...        mã mở khoá
//   TS_SHARED_AUTHKEY=tskey-… key Tailscale (nên là key Reusable)
// Chống dò mã: sai 5 lần thì khoá IP đó 15 phút; cả máy chủ sai 30 lần trong 1 giờ
// thì khoá mọi IP 1 giờ (dò từ nhiều IP cũng không lọt). IPv6 tính theo dải /64
// (một máy tự đổi được cả dải). Mã SAI ĐỘ DÀI vẫn trả "Sai mã." nhưng không tính
// lượt: app tự gửi mã mỗi khi người gõ dừng tay, gõ dở chừng không được làm khoá.
const ENV_FILE = path.join(ROOT, '.env');
const UNLOCK_IP_MAX_FAILS     = 5;
const UNLOCK_IP_LOCK_MS       = 15 * 60000;
const UNLOCK_GLOBAL_MAX_FAILS = 30;
const UNLOCK_GLOBAL_WINDOW_MS = 60 * 60000;

const unlockFails = new Map();   // ip -> { count, lockedUntil, last }
let globalFails = [];            // mốc thời gian các lần sai
let globalLockedUntil = 0;

setInterval(() => {
  const now = Date.now();
  for (const [ip, rec] of unlockFails) {
    if (rec.lockedUntil < now && now - rec.last > UNLOCK_IP_LOCK_MS) unlockFails.delete(ip);
  }
}, 10 * 60000).unref();

function loadEnvFile(file) {
  const out = {};
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch {
    return out;
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

function clientIp(req) {
  // Qua cloudflared thì IP thật nằm ở cf-connecting-ip (Cloudflare tự ghi đè)
  return String(req.headers['cf-connecting-ip'] || req.socket.remoteAddress || '?');
}

// Khoá chống dò: IPv4 theo từng IP, IPv6 theo dải /64
function rateKey(ip) {
  if (!ip.includes(':')) return ip;                          // IPv4
  if (/^::ffff:/i.test(ip)) return ip.slice(7);              // IPv4 viết dạng IPv6
  const [h, t] = ip.split('::');
  const head = h ? h.split(':') : [];
  const tail = t === undefined ? [] : (t ? t.split(':') : []);
  const full = t === undefined
    ? head
    : head.concat(Array(Math.max(0, 8 - head.length - tail.length)).fill('0'), tail);
  const net = full.slice(0, 4).map((g) => parseInt(g, 16));
  if (net.length < 4 || net.some(Number.isNaN)) return ip;
  return net.map((n) => n.toString(16)).join(':') + '::/64';
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new Error('body quá lớn'));
        req.destroy();
      } else {
        chunks.push(c);
      }
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

async function serveTsKey(req, res) {
  if (req.method !== 'POST') {
    res.writeHead(405, { 'Allow': 'POST' });
    return res.end();
  }

  const now = Date.now();
  const ip = clientIp(req);
  const key = rateKey(ip);
  const rec = unlockFails.get(key);
  const lockedUntil = Math.max(rec ? rec.lockedUntil : 0, globalLockedUntil);
  if (lockedUntil > now) {
    const minutes = Math.ceil((lockedUntil - now) / 60000);
    res.setHeader('Retry-After', String(minutes * 60));
    return sendJSON(res, 429, {
      ok: false,
      message: 'Nhập sai quá nhiều lần, thử lại sau ' + minutes + ' phút.',
      retryAfterMinutes: minutes,
    });
  }

  let code = '';
  try {
    code = String(JSON.parse(await readBody(req, 1024)).code || '').trim();
  } catch {
    return sendJSON(res, 400, { ok: false, message: 'Yêu cầu không hợp lệ.' });
  }

  const env = loadEnvFile(ENV_FILE);
  if (!env.TS_UNLOCK_CODE || !env.TS_SHARED_AUTHKEY) {
    return sendJSON(res, 503, { ok: false, message: 'Máy chủ chưa cấu hình key dùng chung.' });
  }

  const digest = (s) => crypto.createHash('sha256').update(s).digest();
  if (code && crypto.timingSafeEqual(digest(code), digest(env.TS_UNLOCK_CODE))) {
    unlockFails.delete(key);
    console.log('[remote] mở khoá key Tailscale: ĐÚNG mã, IP ' + ip);
    return sendJSON(res, 200, { ok: true, key: env.TS_SHARED_AUTHKEY });
  }

  if (code.length !== env.TS_UNLOCK_CODE.length) {
    // gõ dở / gõ thừa: không tính lượt (xem ghi chú đầu khối)
    return sendJSON(res, 403, { ok: false, message: 'Sai mã.' });
  }

  const r = rec || { count: 0, lockedUntil: 0, last: 0 };
  r.count += 1;
  r.last = now;
  if (r.count >= UNLOCK_IP_MAX_FAILS) {
    r.lockedUntil = now + UNLOCK_IP_LOCK_MS;
    r.count = 0;
  }
  unlockFails.set(key, r);

  globalFails = globalFails.filter((t) => now - t < UNLOCK_GLOBAL_WINDOW_MS);
  globalFails.push(now);
  if (globalFails.length >= UNLOCK_GLOBAL_MAX_FAILS) {
    globalLockedUntil = now + UNLOCK_GLOBAL_WINDOW_MS;
    globalFails = [];
    console.error('[remote] mở khoá key Tailscale: sai ' + UNLOCK_GLOBAL_MAX_FAILS + ' lần/giờ — KHOÁ TOÀN BỘ 1 giờ');
  }
  console.warn('[remote] mở khoá key Tailscale: SAI mã, IP ' + ip + (r.lockedUntil > now ? ' — khoá IP 15 phút' : ''));
  return sendJSON(res, 403, { ok: false, message: 'Sai mã.' });
}

// ── Helper HTTP ─────────────────────────────────────────────────────────────
function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function notFound(res) {
  const body = '404 — không tìm thấy trang. Về trang chủ: https://remote.novivo.net';
  res.writeHead(404, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function publicRelease() {
  const strip = (f) => f && {
    filename: f.filename,
    size: f.size,
    sizeText: f.sizeText,
    sha256: f.sha256,
    updatedAt: f.updatedAt,
    blocked: !!(f.secrets && f.secrets.length),
  };
  return {
    version: release.version,
    available: !!(release.exe || release.zip),
    exe: strip(release.exe),
    zip: strip(release.zip),
    updatedAt: release.updatedAt,
    downloads: release.downloads,
  };
}

async function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath);
  if (rel === '/' || rel === '') rel = '/index.html';

  const filePath = path.resolve(PUBLIC_DIR, '.' + rel);
  if (filePath !== PUBLIC_DIR && !filePath.startsWith(PUBLIC_DIR + path.sep)) {
    return notFound(res);
  }

  let st;
  let target = filePath;
  try {
    st = await fsp.stat(target);
    if (st.isDirectory()) return notFound(res);
  } catch {
    // URL sạch: /dieu-khoan -> dieu-khoan.html
    if (!path.extname(target)) {
      try {
        st = await fsp.stat(target + '.html');
        target = target + '.html';
      } catch {
        return notFound(res);
      }
    } else {
      return notFound(res);
    }
  }

  const ext = path.extname(target).toLowerCase();
  const etag = 'W/"' + st.size + '-' + st.mtimeMs.toString(16) + '"';
  if (req.headers['if-none-match'] === etag) {
    res.writeHead(304).end();
    return;
  }

  res.writeHead(200, {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Content-Length': st.size,
    'ETag': etag,
    'Last-Modified': st.mtime.toUTCString(),
    'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=600',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
  });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(target).on('error', () => res.destroy()).pipe(res);
}

async function serveDownload(req, res, kind) {
  await refreshRelease();
  const file = kind === 'zip' ? release.zip : release.exe;
  if (!file) {
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end('Bản cài đặt đang được cập nhật, vui lòng quay lại sau ít phút.');
  }
  if (file.secrets && file.secrets.length) {
    res.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end(
      'Bản phát hành này đã bị gỡ vì lý do an toàn: gói cài đặt có chứa thông tin bí mật ' +
      'không được phép phát hành. Bản sạch sẽ được đăng lại sau khi build lại.'
    );
  }

  const total = file.size;
  const headers = {
    'Content-Type': kind === 'zip'
      ? 'application/zip'
      : 'application/vnd.microsoft.portable-executable',
    'Content-Disposition': 'attachment; filename="' + file.filename.replace(/[^\x20-\x7e]/g, '_') + '"',
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'no-cache',
    'X-Checksum-Sha256': file.sha256 || '',
  };

  // Tải tiếp giữa chừng (HTTP Range) — không tính thêm lượt tải
  const range = req.headers.range;
  const m = range && /^bytes=(\d*)-(\d*)$/.exec(range.trim());
  if (m) {
    const start = m[1] ? parseInt(m[1], 10) : 0;
    const end = m[2] ? parseInt(m[2], 10) : total - 1;
    if (Number.isNaN(start) || Number.isNaN(end) || start > end || end >= total) {
      res.writeHead(416, { 'Content-Range': 'bytes */' + total });
      return res.end();
    }
    headers['Content-Range'] = 'bytes ' + start + '-' + end + '/' + total;
    headers['Content-Length'] = end - start + 1;
    res.writeHead(206, headers);
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(file.path, { start, end })
      .on('error', () => res.destroy())
      .pipe(res);
  }

  headers['Content-Length'] = total;
  res.writeHead(200, headers);
  if (req.method === 'HEAD') return res.end();

  release.downloads += 1;
  statsDirty = true;
  fs.createReadStream(file.path).on('error', () => res.destroy()).pipe(res);
}

// ── Server ──────────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://' + (req.headers.host || 'remote.novivo.net'));
  const pathname = url.pathname.replace(/\/+$/, '') || '/';

  if (pathname === '/api/ts-key') {
    try {
      return await serveTsKey(req, res);
    } catch (err) {
      console.error('[remote] lỗi mở khoá key', err);
      if (!res.headersSent) return sendJSON(res, 500, { ok: false, message: 'Lỗi máy chủ.' });
      return res.end();
    }
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Allow': 'GET, HEAD' });
    return res.end();
  }

  try {
    switch (pathname) {
      case '/health':
        return sendJSON(res, 200, {
          status: 'ok',
          service: 'novivo-remote',
          version: release.version,
          uptime: Math.floor((Date.now() - STARTED_AT) / 1000),
          release: release.exe || release.zip ? 'ready' : 'missing',
        });

      case '/api/release':
        return sendJSON(res, 200, publicRelease());

      case '/download':
      case '/tai-ve':
        return await serveDownload(req, res, 'exe');

      case '/download-full':
      case '/tai-ve-full':
        return await serveDownload(req, res, 'zip');

      default:
        return await serveStatic(req, res, pathname);
    }
  } catch (err) {
    console.error('[remote] lỗi xử lý', pathname, err);
    if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('500 — lỗi máy chủ');
  }
});

process.on('SIGINT', () => saveStats().finally(() => process.exit(0)));
process.on('SIGTERM', () => saveStats().finally(() => process.exit(0)));

(async () => {
  await loadStats();
  await refreshRelease();
  server.listen(PORT, HOST, () => {
    console.log('[remote] landing page chạy tại http://' + HOST + ':' + PORT + '  →  https://remote.novivo.net');
  });
})();
