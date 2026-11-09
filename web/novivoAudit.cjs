/*
 * NOVIVO AUDIT — nhật ký thao tác thống nhất cho mọi app *.novivo.net (bản chuẩn ở C:\NOVIVO-AUDIT\lib, đặc tả SPEC.md).
 * Sao chép NGUYÊN VĂN vào app (đừng sửa riêng — cần sửa thì sửa bản chuẩn rồi chép lại cho mọi app).
 *
 * Mỗi dòng JSONL = một sự kiện: ai (actor) · làm gì (type/action) · vào đâu (target) · đổi gì (changes/before/after)
 * · từ đâu (ip/country/ua) · kết quả. Dòng mang `prev` (hash dòng trước) + `hash` = sha256(prev + thân dòng chưa có hash)
 * → sửa/xoá một dòng giữa chừng là chuỗi gãy, bộ xem phát hiện được (verifyFile).
 * Tệp: <ROOT>\logs\<app>\<YYYY-MM-DD giờ VN>_<stream>_<pid>.jsonl — mỗi tiến trình một tệp nên không giành nhau.
 * Không bao giờ ném lỗi vào luồng xử lý của app: ghi hỏng thì bỏ qua + đếm (stats()).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { AsyncLocalStorage } = require('async_hooks');

const ROOT = process.env.NOVIVO_AUDIT_DIR || 'C:\\NOVIVO-AUDIT';
const SECRET_KEY = /(pass(word|wd)?|pwd|secret|token|cookie|authorization|api[-_]?key|apikey|otp|session(id)?|credential|private[-_]?key|signature|jwt|refresh|bearer|hatch_sess|cvv|card[-_]?number|totp|2fa|twofa|two_?factor|mfa|backup_?codes?|recovery_?codes?)/i;
const SECRET_VAL = /^(Bearer\s+\S{12,}|eyJ[\w-]{8,}\.[\w-]{8,}\.|sk-[\w-]{16,}|tskey-|pd_live_|ghp_|github_pat_|xox[abp]-|AKIA[0-9A-Z]{12})/;
// Chuỗi cookie trình duyệt ("sessionid=…; ttwid=…"), chuỗi kiểu query có mật khẩu, dòng proxy host:port:user:pass — dù trường tên vô hại.
const SECRET_INSIDE = /((^|[;\s])(sessionid(_ss)?|sid_tt|sid_guard|uid_tt|hatch_sess|ttwid|passport_csrf_token|odin_tt|msToken|__Secure-[\w-]+|SAPISID|APISID|HSID|SSID|SID)=[^;\s]{6,}|(^|[&?;\s])(pass(word)?|pwd|token|secret|api_?key|access_token)=[^&\s]{4,})/i;
const PROXY_LINE = /^[\w.-]+:\d{2,5}:[^:\s]+:[^:\s]+$/;
const CODE_KEY = /(^|[_-])(code|pin|passcode)$|[a-z](Code|Pin|Passcode)$/i;
// Tên có hậu tố này là mã/đếm/cờ (cookieId, tokenVersion, COOKIE_SECURE, TOKEN_TTL…) chứ không phải bí mật; riêng sessionId/session_id vẫn là bí mật.
const NOT_SECRET_SNAKE = /[_.-](id|ids|version|count|ttl|at|expires|expiry|enabled|secure|type|status|name|names|length|len|mode|source|kind|label|policy|days|hours|ms|limit|url)$/i;
const NOT_SECRET_CAMEL = /[a-z0-9](Id|Ids|Version|Count|Ttl|TTL|At|Expires|Expiry|Enabled|Secure|Type|Status|Name|Names|Length|Len|Mode|Source|Kind|Label|Policy|Days|Hours|Ms|Limit|Url)$/;
const MAX_STR = 300, SNAP_STR = 20000, MAX_KEYS = 60, MAX_ARR = 20, MAX_DEPTH = 5, MAX_LINE = 256 * 1024;
// ảnh chụp before/after (maxStr > MAX_STR) giữ gần đủ bản ghi lớn để khôi phục; phần khác giữ giới hạn gọn
const NORM_LIM = { depth: MAX_DEPTH, arr: MAX_ARR, keys: MAX_KEYS }, SNAP_LIM = { depth: 8, arr: 200, keys: 300 };
// Mật khẩu trong chuỗi kết nối / URL (postgres://user:MẬT_KHẨU@host, http://u:p@proxy) → thay bằng ***
const URL_CRED = /(\b[a-z][a-z0-9+.-]*:\/\/[^\/\s:@]+:)[^@\s\/]+@/gi;
const MUTATING = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

const als = new AsyncLocalStorage();

function vnDate(d) { return new Date(d.getTime() + 7 * 3600e3).toISOString().slice(0, 10); }

function isSecretKey(k) {
  if (!k || !SECRET_KEY.test(k)) return false;
  return /^session_?id$/i.test(k) || !(NOT_SECRET_SNAKE.test(k) || NOT_SECRET_CAMEL.test(k));
}
function secretString(s) { return SECRET_VAL.test(s) || SECRET_INSIDE.test(s) || PROXY_LINE.test(s.trim()); }

/** Che bí mật (theo tên trường + theo dạng giá trị), cắt chuỗi dài (maxStr), giới hạn độ sâu — dùng cho body/before/after. */
function redact(v, depth = 0, key = '', maxStr = MAX_STR) {
  if (isSecretKey(key)) {
    if (v == null || v === '' || typeof v === 'boolean') return v;
    // {from,to} của diff: giữ dạng để vẫn thấy "trường bí mật ĐÃ ĐỔI"
    if (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).every((x) => x === 'from' || x === 'to')) {
      return { from: v.from == null ? v.from : '[ẩn]', to: v.to == null ? v.to : '[ẩn]' };
    }
    return '[ẩn]';
  }
  // mã số (OTP/mã mở khoá/PIN) gửi dưới tên code/pin/passcode/*_code
  if (key && CODE_KEY.test(key) && (typeof v === 'number' || typeof v === 'string') && /^\s*\d{4,16}\s*$/.test(String(v))) return '[ẩn]';
  if (v == null || typeof v === 'number' || typeof v === 'boolean') return v;
  if (typeof v === 'string') {
    if (secretString(v)) return '[ẩn]';
    if (v.includes('@')) v = v.replace(URL_CRED, '$1***@');
    return v.length > maxStr ? v.slice(0, maxStr) + `…(+${v.length - maxStr})` : v;
  }
  if (typeof v === 'bigint') return String(v);
  if (v instanceof Date) return isNaN(v) ? null : v.toISOString();
  if (Buffer.isBuffer(v)) return `[buffer ${v.length}B]`;
  if (typeof v === 'function' || typeof v === 'symbol') return undefined;
  if (typeof v.toHexString === 'function') return v.toHexString(); // Mongo ObjectId
  const lim = maxStr > MAX_STR ? SNAP_LIM : NORM_LIM;
  if (depth >= lim.depth) return '[…]';
  if (Array.isArray(v)) {
    const out = v.slice(0, lim.arr).map((x) => redact(x, depth + 1, '', maxStr));
    if (v.length > lim.arr) out.push(`…(+${v.length - lim.arr})`);
    return out;
  }
  if (typeof v === 'object') {
    if (typeof v.toObject === 'function' && v.$__) v = v.toObject({ depopulate: true }); // tài liệu Mongoose
    if (v instanceof Map) v = Object.fromEntries(v);
    const keys = Object.keys(v);
    // đối tượng cookie trình duyệt {name, value, domain|path} → giá trị luôn là bí mật
    const cookieObj = 'name' in v && 'value' in v && ('domain' in v || 'path' in v);
    const out = {};
    for (let i = 0; i < keys.length; i++) {
      if (i >= lim.keys) { out['…'] = `+${keys.length - lim.keys} trường`; break; }
      const r = cookieObj && keys[i] === 'value' ? (v.value ? '[ẩn]' : v.value) : redact(v[keys[i]], depth + 1, keys[i], maxStr);
      if (r !== undefined) out[keys[i]] = r;
    }
    return out;
  }
  return String(v);
}

const same = (a, b) => { try { return JSON.stringify(a) === JSON.stringify(b); } catch { return a === b; } };

/** {trường: {from, to}} giữa hai bản ghi (cấp 1; trường lồng so cả khối). Trường bí mật chỉ ghi "[ẩn]" — biết là ĐÃ ĐỔI. */
function diff(before, after, ignore = []) {
  const b = before || {}, a = after || {};
  const out = {};
  for (const k of new Set([...Object.keys(b), ...Object.keys(a)])) {
    if (ignore.includes(k) || same(b[k], a[k])) continue;
    out[k] = isSecretKey(k) ? { from: b[k] == null ? null : '[ẩn]', to: a[k] == null ? null : '[ẩn]' } : { from: redact(b[k], 1, k), to: redact(a[k], 1, k) };
  }
  return out;
}

/** IP thật của khách: app chỉ nghe localhost sau Cloudflare Tunnel nên tin CF-Connecting-IP. */
function ipOf(req) {
  const h = (req && req.headers) || {};
  const xf = String(h['x-forwarded-for'] || '').split(',')[0].trim();
  return String(h['cf-connecting-ip'] || xf || (req.socket && req.socket.remoteAddress) || req.ip || '').replace(/^::ffff:/, '');
}

function routeOf(req) {
  if (req.route && req.route.path) return (req.baseUrl || '') + (typeof req.route.path === 'string' ? req.route.path : String(req.route.path));
  return String(req.originalUrl || req.url || '').split('?')[0];
}

function bodyOf(req) {
  const b = req.body;
  if (b == null) return undefined;
  if (Buffer.isBuffer(b)) return `[buffer ${b.length}B]`;
  if (typeof b === 'string') return b.length ? redact(b) : undefined;
  if (typeof b === 'object' && !Object.keys(b).length) return undefined;
  return redact(b);
}

function fromReq(req) {
  if (!req || !req.headers) return {};
  return { ip: ipOf(req), country: req.headers['cf-ipcountry'] || undefined, ua: String(req.headers['user-agent'] || '').slice(0, 200) || undefined };
}

/**
 * createAudit({ app, stream }) → { log, auth, admin, data, security, express, setActor, current, redact, diff, ipOf, stats, flushSync }
 * app: tên ngắn cố định (videos, novivo, adsend, viral, pooldesk, cpm, clone, genesis, game, tdad, remote, taiwin)
 * stream: tiến trình nào của app (web, worker, api…)
 */
function createAudit({ app, stream = 'web', dir } = {}) {
  if (!app || !/^[a-z0-9-]+$/.test(app)) throw new Error('novivo-audit: app phải là chữ thường, vd "videos"');
  const base = path.join(dir || ROOT, 'logs', app);
  let day = '', file = '', prev = 'GENESIS', seq = 0, fd = null;
  const st = { written: 0, dropped: 0, errors: 0, lastError: null, file: null };
  try { fs.mkdirSync(base, { recursive: true }); } catch (e) { st.errors++; st.lastError = e.message; }

  function target(now) {
    const d = vnDate(now);
    if (d !== day) {
      if (fd !== null) { try { fs.closeSync(fd); } catch {} fd = null; }
      day = d; file = path.join(base, `${d}_${stream}_${process.pid}.jsonl`); seq = 0; st.file = file;
    }
    return file;
  }

  // Ghi ĐỒNG BỘ qua một fd giữ mở (không mở/đóng mỗi dòng → Defender không quét lại; ~vài chục µs/dòng):
  // thứ tự dòng luôn đúng như thứ tự gọi → chuỗi hash không bao giờ đảo, kể cả lúc tiến trình thoát.
  function writeLine(f, line) {
    try {
      if (fd === null) fd = fs.openSync(f, 'a');
      fs.writeSync(fd, line, null, 'utf8');
      st.written++;
      return true;
    } catch (e) {
      st.errors++; st.lastError = e.message;
      if (fd !== null) { try { fs.closeSync(fd); } catch {} fd = null; }
      return false;
    }
  }

  function flushSync() { if (fd !== null) { try { fs.fsyncSync(fd); } catch {} } }

  /** Ghi một sự kiện. ev: { type, action, actor, target, changes, before, after, outcome, note, req:{…}, ip, country, ua, meta } */
  function log(ev) {
    try {
      const now = new Date();
      const f = target(now);
      const ctx = als.getStore();
      const e = { ...ev };
      if (e.actor === undefined && ctx) e.actor = ctx.actor || (ctx.getActor ? safe(() => ctx.getActor(ctx.req)) : null) || null;
      if (e.actor === undefined) e.actor = { via: 'system', name: `${stream}:${path.basename(process.argv[1] || 'node')}` };
      if (!e.ip && ctx && ctx.req) { const r = fromReq(ctx.req); for (const k of Object.keys(r)) if (e[k] == null) e[k] = r[k]; }
      const obj = { v: 1, ts: now.toISOString(), app, stream, pid: process.pid, seq: seq + 1, ...redactEvent(e), prev };
      let body = dumps(obj);
      if (body.length > MAX_LINE) { // quá lớn: hạ ảnh chụp về 300 ký tự/chuỗi trước, vẫn quá thì mới bỏ
        obj.truncated = true;
        for (const k of ['before', 'after']) if (e[k] !== undefined) obj[k] = redact(e[k], 0, k, MAX_STR);
        body = dumps(obj);
      }
      if (body.length > MAX_LINE) {
        delete obj.before; delete obj.after;
        if (obj.changes) obj.changes = '[quá lớn]';
        if (obj.req) delete obj.req.body;
        body = dumps(obj);
      }
      const hash = crypto.createHash('sha256').update(prev + body, 'utf8').digest('hex');
      // chỉ nối chuỗi khi dòng đã ghi thật — ghi hỏng thì dòng sau vẫn nối vào dòng cuối CÓ trên đĩa
      if (writeLine(f, body.slice(0, -1) + ',"hash":"' + hash + '"}\n')) { seq++; prev = hash; } else st.dropped++;
    } catch (err) { st.errors++; st.lastError = err.message; }
  }

  function redactEvent(e) {
    const out = {};
    for (const [k, v] of Object.entries(e)) {
      if (v === undefined) continue;
      // ảnh chụp before/after giữ chuỗi dài hơn (để khôi phục nguyên bài/ghi chú), phần khác cắt 300
      const r = redact(v, 0, k, k === 'before' || k === 'after' ? SNAP_STR : MAX_STR);
      if (r !== undefined) out[k] = r;
    }
    return out;
  }

  const kind = (type) => (action, fields = {}) => log({ type, action, ...fields });

  /**
   * Middleware Express: ghi mọi yêu cầu POST/PUT/PATCH/DELETE (+ GET khớp alsoLog) khi phản hồi xong,
   * và mở ngữ cảnh AsyncLocalStorage để log()/data() ở tầng dưới tự biết ai đang thao tác.
   * opts.getActor(req) → actor (đọc req.user sau khi middleware đăng nhập chạy) · opts.skip(req) → true = không ghi (máy phụ, nhịp tim…)
   */
  function expressMw(opts = {}) {
    const { getActor = null, skip = null, alsoLog = null, captureBody = true } = opts;
    return function novivoAudit(req, res, next) {
      const store = { req, actor: null, getActor };
      const t0 = Date.now();
      const p = String(req.originalUrl || req.url || '').split('?')[0];
      const want = (MUTATING.has(req.method) || (alsoLog && alsoLog.test(p))) && !(skip && safe(() => skip(req)));
      if (want) {
        let done = false;
        const fin = () => {
          if (done) return;
          done = true;
          const status = res.statusCode;
          const aborted = !res.writableFinished;
          log({
            type: 'http', action: `${req.method} ${routeOf(req)}`,
            actor: store.actor || (getActor ? safe(() => getActor(req)) : null) || null,
            ...fromReq(req),
            req: { method: req.method, path: p, status, ms: Date.now() - t0, query: req.query && Object.keys(req.query).length ? req.query : undefined, body: captureBody ? bodyOf(req) : undefined },
            outcome: aborted ? 'aborted' : status < 400 ? 'ok' : status === 401 || status === 403 || status === 429 ? 'denied' : 'error',
          });
        };
        res.once('finish', fin);
        res.once('close', fin);
      }
      als.run(store, next);
    };
  }

  return {
    log,
    auth: kind('auth'), admin: kind('admin'), security: kind('security'),
    /** Thay đổi dữ liệu: data('update', { target:{kind,id,label}, changes }) · data('delete', { target, before }) · data('create', { target, after }) */
    data: (op, fields = {}) => log({ type: 'data', action: op, ...fields }),
    express: expressMw,
    /** Gọi trong middleware đăng nhập khi đã biết người dùng. */
    setActor(actor) { const s = als.getStore(); if (s) s.actor = actor; },
    current: () => als.getStore() || null,
    run: (store, fn) => als.run(store, fn),
    redact, diff, ipOf, fromReq,
    stats: () => ({ ...st, seq, day }),
    flushSync,
  };
}

function safe(fn) { try { return fn(); } catch { return null; } }

// U+2028/U+2029 hợp lệ trong JSON nhưng regex "." / splitlines() coi là xuống dòng -> luôn escape (bản Python làm y hệt).
const LS = String.fromCharCode(0x2028), PS = String.fromCharCode(0x2029);
function dumps(obj) { return JSON.stringify(obj).split(LS).join('\\u2028').split(PS).join('\\u2029'); }

/** Kiểm một tệp: chuỗi hash có liền không. → { ok, lines, badAt, reason, lastHash, firstPrev } */
function verifyFile(file) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split('\n').filter((l) => l.length);
  let prev = null, firstPrev = null;
  for (let i = 0; i < lines.length; i++) {
    const m = /^([\s\S]*),"hash":"([0-9a-f]{64})"\}$/.exec(lines[i]);
    if (!m) return { ok: false, lines: lines.length, badAt: i + 1, reason: 'dòng không đúng dạng', lastHash: prev, firstPrev };
    const body = m[1] + '}';
    let obj; try { obj = JSON.parse(body); } catch { return { ok: false, lines: lines.length, badAt: i + 1, reason: 'JSON hỏng', lastHash: prev, firstPrev }; }
    if (i === 0) firstPrev = obj.prev;
    if (prev !== null && obj.prev !== prev) return { ok: false, lines: lines.length, badAt: i + 1, reason: 'mất/chèn dòng (prev không khớp)', lastHash: prev, firstPrev };
    const h = crypto.createHash('sha256').update(String(obj.prev) + body, 'utf8').digest('hex');
    if (h !== m[2]) return { ok: false, lines: lines.length, badAt: i + 1, reason: 'nội dung dòng bị sửa (hash sai)', lastHash: prev, firstPrev };
    prev = m[2];
  }
  return { ok: true, lines: lines.length, badAt: null, reason: null, lastHash: prev, firstPrev };
}

/*
 * Thu hồi tập trung: NOVIVO ghi <ROOT>\control\revocations.json khi admin bấm "Khoá" / "Đăng xuất mọi nơi".
 * App SSO gọi checkRevoked(novivoUserId, issuedAtGiây) trong middleware đăng nhập → { blocked, reason }.
 * { v:1, updatedAt, users: { "<novivoUserId>": { revokedAt: ISO, locked: bool, reason, by } } }
 */
let revCache = { at: 0, mtime: 0, data: null };
function readRevocations() {
  const now = Date.now();
  if (now - revCache.at < 3000 && revCache.data) return revCache.data;
  revCache.at = now;
  try {
    const f = path.join(ROOT, 'control', 'revocations.json');
    const m = fs.statSync(f).mtimeMs;
    if (m !== revCache.mtime || !revCache.data) {
      const d = JSON.parse(fs.readFileSync(f, 'utf8'));
      revCache.data = d && typeof d === 'object' && d.users && typeof d.users === 'object' ? d : { users: {} };
      revCache.mtime = m;
    }
  } catch { if (!revCache.data) revCache.data = { users: {} }; }
  return revCache.data;
}
function checkRevoked(novivoUserId, issuedAtSec) {
  if (!novivoUserId) return { blocked: false };
  const u = ((readRevocations() || {}).users || {})[String(novivoUserId)];
  if (!u || typeof u !== 'object') return { blocked: false };
  if (u.locked) return { blocked: true, reason: 'Tài khoản đã bị khoá' + (u.reason ? ': ' + u.reason : '') };
  const rv = Date.parse(u.revokedAt || '') / 1000;
  if (rv && (!issuedAtSec || Number(issuedAtSec) < rv)) return { blocked: true, reason: 'Phiên đã bị thu hồi — đăng nhập lại' };
  return { blocked: false };
}

module.exports = { createAudit, verifyFile, checkRevoked, readRevocations, redact, diff, ipOf, ROOT };
