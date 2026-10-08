"""
Test luồng mở khoá key Tailscale dùng chung trong NOVIVO-App.py (không cần admin,
không mở cửa sổ, không đụng máy chủ thật). 27 ca: tự mở khoá khi ngừng gõ, gõ dở,
sai mã, sửa giữa chừng, START tự chạy tiếp, Cloudflare chặn, mất mạng, bị khoá,
ZeroTier, key dán tay, không lưu mã/key vào servers.json.

Chạy (từ thư mục REMOTE, PowerShell):
    1. Máy chủ tạm (cửa sổ riêng):  $env:PORT=5399; node web/server.js
    2. Test:                        python Tests/unlock_flow_test.py
Test đọc mã từ TS_UNLOCK_CODE trong web/.env lúc chạy (repo công khai: KHÔNG ghi mã
vào file này). Ca 9 (mất mạng) mất ~6s.
"""
import os
import sys
import ctypes, time, types, threading, http.server, socketserver
ctypes.windll.shell32.IsUserAnAdmin = lambda: 1
P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "NOVIVO-App.py")
mod = types.ModuleType("novivo_app"); mod.__file__ = P
exec(compile(open(P, encoding="utf-8").read(), P, "exec"), mod.__dict__)
GOOD_URL = "http://127.0.0.1:5399/api/ts-key"; mod.UNLOCK_URL = GOOD_URL
_env = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", ".env")
CODE = next(l.split("=", 1)[1].strip() for l in open(_env, encoding="utf-8")
            if l.startswith("TS_UNLOCK_CODE="))
WRONG = "".join(str((int(c) + 1) % 10) for c in CODE)          # same length, every digit off
OTHER = CODE[:-1] + str((int(CODE[-1]) + 1) % 10)              # used where the server is fake
PART, REST = CODE[:6], CODE[6:]
SPACED = f"{CODE[:4]} {CODE[4:7]}-{CODE[7:]}"
mod.messagebox.showwarning = lambda *a: (_ for _ in ()).throw(AssertionError("popup!"))
# fake Cloudflare: HTML 403 + a slow endpoint
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/slow": time.sleep(1.5)
        if self.path == "/slow":
            b = b'{"ok":true,"key":"tskey-auth-SLOWSLOWSLOW"}'; self.send_response(200)
        else:
            b = b"<html>Attention Required! | Cloudflare</html>"; self.send_response(403)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
srv = socketserver.ThreadingTCPServer(("127.0.0.1", 5398), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
import tkinter as tk
handlers = {}; _ob = tk.Entry.bind
def spy(self, seq=None, func=None, add=None):
    if func: handlers.setdefault(id(self), {})[seq] = func
    return _ob(self, seq, func, add)
tk.Entry.bind = spy
root = tk.Tk(); root.withdraw()
var = tk.StringVar(value="tailscale"); status, logs = [], []
sl = mod.ServerList(root, var, status_cb=status.append, log_cb=logs.append); sl.pack()
sl.add_row(name="A", key="", is_active=True)
r = sl._rows[0]; e = r["ke"]; H_ = handlers[id(e)]
class Ev:
    def __init__(s, char="", keysym="", state=0): s.char, s.keysym, s.state = char, keysym, state
def pump(sec):
    end = time.time() + sec
    while time.time() < end: root.update(); time.sleep(0.01)
def until(cond, timeout):
    """Pump the Tk loop until cond() is true (or timeout) — no fixed sleeps."""
    end = time.time() + timeout
    while time.time() < end and not cond(): root.update(); time.sleep(0.01)
    return cond()
def type_(text, gap=0.05):
    for c in text:
        H_["<Key>"](Ev(c, c)); e.insert("insert", c); H_["<KeyRelease>"](Ev(c, c)); pump(gap)
def clear():
    e.delete(0, "end"); H_["<KeyRelease>"](Ev("", "BackSpace"))
def focus_in(): H_["<FocusIn>"](None)
def msg(): return sl._msg.cget("text")
M = lambda s: "tskey-<AN>" if (s or "").startswith("tskey-") else repr(s)
res = []
def check(name, cond, extra=""):
    res.append(bool(cond)); print("PASS" if cond else "FAIL", name, extra)

focus_in()
type_(CODE); check("0 dang go: ma bi che", e.cget("show") == "•")
pump(0.5); check("1a chua du 900ms thi chua gui", not r["busy"][0] and not r["vault"][0])
until(lambda: r["vault"][0], 6); check("1b ngung tay -> TU mo khoa, khong can Enter", r["vault"][0] and e.get() == sl._MASK and e.cget("show") == "", msg())
check("1c servers.json khong luu key", sl.get_all()[0]["key"] == "", M(sl.get_active_key()))
check("1d log co dong OK", any("[OK]" in l for l in logs))
H_["<Key>"](Ev("x", "x")); e.insert("insert", "x"); H_["<KeyRelease>"](Ev("x", "x"))
check("2 go de len key -> bo key", r["vault"][0] is None and e.get() == "x" and e.cget("show") == "")
clear(); type_(PART, 0.05); until(lambda: r["failed"][0], 6)
check("3a go do + dung tay -> bao sai, KHONG popup, giu nguyen chu", r["failed"][0] == PART and e.get() == PART and "Sai" in msg(), msg())
type_(REST, 0.05)
check("3b go tiep -> xoa bao do", r["failed"][0] is None and msg() == "" or r["busy"][0])
until(lambda: r["vault"][0], 6); check("3c go xong -> tu mo khoa", r["vault"][0], msg())
H_["<Key>"](Ev("", "BackSpace")); clear()
type_(WRONG); H_["<Return>"](None); until(lambda: r["failed"][0], 6)
check("4a sai ma + Enter -> bao do + goi y sua ma", "sửa lại mã" in msg() and r["failed"][0] == WRONG and str(e.cget("fg")).lower() == mod.C["danger"].lower(), msg())
check("4b ma sai khong thanh key, khong luu", sl.get_active_key() == "" and sl.get_all()[0]["key"] == "")
pump(1.2); check("4c khong tu gui lai ma da sai", not r["busy"][0])
clear(); type_(SPACED); until(lambda: r["vault"][0], 6)
check("5 ma co dau cach/gach van nhan", r["vault"][0], msg())
H_["<Key>"](Ev("", "BackSpace")); clear()
mod.UNLOCK_URL = "http://127.0.0.1:5398/slow"
type_(CODE); until(lambda: r["busy"][0], 6); check("6a dang gui (cham)", r["busy"][0])
type_("9"); check("6b sua trong luc gui -> bo yeu cau cu", not r["busy"][0] or r["sent"][0] != CODE)
pump(2.0); check("6c ket qua cu bi bo qua", r["vault"][0] is None, f"vault={M(r['vault'][0])}")
mod.UNLOCK_URL = GOOD_URL; clear(); pump(1.2)
type_(CODE); called = []
check("7a bam START khi ma con trong o -> cho mo khoa", sl.unlock_active(then=lambda: called.append(1)))
until(lambda: called, 6); check("7b mo xong -> START tu chay tiep", r["vault"][0] and called == [1])
H_["<Key>"](Ev("", "BackSpace")); clear()
mod.UNLOCK_URL = "http://127.0.0.1:5398/cf"; type_(CODE); until(lambda: r["failed"][0], 6)
check("8 Cloudflare chan (HTML 403) -> bao ro + Enter thu lai", "HTTP 403" in msg() and "Enter" in msg(), msg())
mod.UNLOCK_URL = "http://127.0.0.1:1/x"; clear(); type_(OTHER); until(lambda: r["failed"][0], 15)
check("9 mat mang -> bao khong ket noi", "Không kết nối" in msg(), msg())
H_["<Return>"](None); check("9b Enter thu lai ma cung ma da loi", r["busy"][0]); until(lambda: not r["busy"][0], 15)
class H429(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        b = '{"ok":false,"message":"Nhập sai quá nhiều lần, thử lại sau 15 phút."}'.encode(); self.send_response(429)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s429 = socketserver.ThreadingTCPServer(("127.0.0.1", 5397), H429); threading.Thread(target=s429.serve_forever, daemon=True).start()
mod.UNLOCK_URL = "http://127.0.0.1:5397/x"; clear(); type_(CODE); until(lambda: r["failed"][0], 6)
check("9c bi khoa (429) -> bao so phut, khong goi y thu lai", "15 phút" in msg() and "Enter" not in msg(), msg())
mod.UNLOCK_URL = GOOD_URL; clear(); type_(CODE)
sl.add_row(name="B", key="", is_active=False); sl._active_idx.set(0); sl.remove_active(); pump(1.5)
check("10 xoa dong khi dang hen gio -> khong loi", len(sl._rows) == 1)
r = sl._rows[0]; e = r["ke"]; H_ = handlers[id(e)]; focus_in(); type_(CODE); until(lambda: r["vault"][0], 6)
var.set("zerotier"); sl.update_key_placeholders()
check("11a doi ZeroTier -> bo key, hien placeholder", r["vault"][0] is None and e.get() == "network ID…" and msg() == "")
focus_in(); type_("1234567890"); pump(1.5)
check("11b ZeroTier: so khong bi che, khong gui", e.cget("show") == "" and not r["busy"][0] and sl.get_active_key() == "1234567890")
var.set("tailscale"); sl.update_key_placeholders(); clear(); type_("tskey-auth-abcdefg"); pump(1.2)
check("12 key tskey dan tay: hien ro, dung nguyen", e.cget("show") == "" and sl.get_active_key() == "tskey-auth-abcdefg" and sl.get_all()[0]["key"] == "tskey-auth-abcdefg")
clear(); H_["<FocusOut>"](None)
check("13 de trong roi roi o -> placeholder", r["k_is_ph"][0] and e.get() == "tskey-auth-…")
print(f"\n{sum(res)}/{len(res)} PASS")
root.destroy(); srv.shutdown()
sys.exit(0 if all(res) else 1)
