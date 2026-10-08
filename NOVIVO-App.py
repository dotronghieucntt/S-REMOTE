"""
NOVIVO Remote Desktop Setup Tool
CustomTkinter UI  ·  Backend: NOVIVO-Backend.ps1
"""

import sys
import os
import subprocess
import json
import threading
import ctypes
import random
import re
import socket
import ssl
import string
import time
import tkinter as tk
import urllib.error
import urllib.request

import certifi
import customtkinter as ctk
from tkinter import messagebox, ttk
from PIL import Image, ImageTk

# ─── Re-launch as admin if needed ───────────────────────────────────────────
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

if not is_admin():
    script = os.path.abspath(__file__)
    ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, f'"{script}"', None, 1)
    sys.exit()

# ─── Paths ───────────────────────────────────────────────────────────────────
# PyInstaller --onefile: EXE sits at sys.executable, bundled files in sys._MEIPASS.
# User-writable files (servers.json) always go next to the EXE / script.
if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
    BASE_DIR = os.path.dirname(sys.executable)   # folder containing .exe
    _BUNDLE  = sys._MEIPASS                       # temp extraction dir
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    _BUNDLE  = BASE_DIR

BACKEND      = os.path.join(_BUNDLE,  "NOVIVO-Backend.ps1")  # bundled resource
ALWAYS_ADMIN = os.path.join(_BUNDLE,  "NOVIVO-AlwaysAdmin.ps1")  # bundled resource
SERVERS_FILE = os.path.join(BASE_DIR, "servers.json")         # user-writable, next to EXE
LOGO_ICO     = os.path.join(_BUNDLE,  "LOGO KO CHU.png")      # hexagon logo (no text)

def _asset(name):
    """Bundled copy wins: it is built with the binary and always matches it.
    A file next to the EXE is only a fallback (and is the same path when running
    from source, where BASE_DIR == _BUNDLE)."""
    for base in (_BUNDLE, BASE_DIR):
        p = os.path.join(base, name)
        if os.path.exists(p):
            return p
    return os.path.join(_BUNDLE, name)


# Read version from version.txt, fallback to "1.0.0"
_ver_file = _asset("version.txt")
try:
    with open(_ver_file, encoding="utf-8") as _vf:
        APP_VERSION = _vf.read().strip() or "1.0.0"
except OSError:
    APP_VERSION = "1.0.0"

# ─── CustomTkinter config ────────────────────────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

# ══════════════════════════════════════════════════════════════════════════════
#  COLOUR PALETTE
# ══════════════════════════════════════════════════════════════════════════════
C = {
    "bg":         "#0D0F1A",   # window background
    "panel":      "#12152A",   # panel/card
    "panel2":     "#0E1120",   # slightly darker panel
    "border":     "#1E2548",   # border/divider
    "accent":     "#4A7CFF",   # primary blue
    "accent_hov": "#6090FF",   # hovered accent
    "success":    "#00C480",   # green
    "danger":     "#E03C46",   # red
    "warn":       "#FFB428",   # amber
    "purple":     "#7A4FD6",   # purple
    "text_hi":    "#E2EAFF",   # primary text
    "text_lo":    "#5B6A98",   # muted text
    "input_bg":   "#171C38",   # input field
    "grid_head":  "#141832",   # table header
    "log_bg":     "#060810",   # log background
    "log_fg":     "#00D77D",   # log text  (green)
    "status_bg":  "#080A16",   # status bar
    "btn_dim":    "#1E2444",   # dim button
    "btn_hov":    "#1A2040",   # hover tint for outlined buttons
    "header_bg":  "#0A0C1C",   # top header strip
}

FONT_BRAND   = ("Segoe UI", 28, "bold")
FONT_TITLE   = ("Segoe UI", 10, "bold")
FONT_LABEL   = ("Segoe UI", 9)
FONT_LABELB  = ("Segoe UI", 9, "bold")
FONT_BTN     = ("Segoe UI", 10, "bold")
FONT_BTN_LG  = ("Segoe UI", 12, "bold")
FONT_INPUT   = ("Consolas", 10)
FONT_LOG     = ("Consolas", 9)
FONT_SMALL   = ("Segoe UI", 8)

# Held as a constant because the button label is restored after every run
BTN_ALWAYS_ADMIN = "🛡  ALWAYS RUN AS ADMINISTRATOR"

# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════
def _bind_mousewheel(canvas):
    """Wheel-scroll a canvas while the pointer is over it."""
    def _scroll(e):
        canvas.yview_scroll(int(-1 * (e.delta / 120)), "units")
    canvas.bind("<Enter>", lambda e: canvas.bind_all("<MouseWheel>", _scroll))
    canvas.bind("<Leave>", lambda e: canvas.unbind_all("<MouseWheel>"))


class ScrollFrame(tk.Frame):
    """Vertically scrollable container. Pack content into `.body`."""

    def __init__(self, master, **kw):
        super().__init__(master, bg=C["panel"], **kw)
        self._canvas = tk.Canvas(self, bg=C["panel"], highlightthickness=0)
        self._sbar = ttk.Scrollbar(self, orient="vertical",
                                   command=self._canvas.yview,
                                   style="Dark.Vertical.TScrollbar")
        self._canvas.configure(yscrollcommand=self._sbar.set)
        self._sbar.pack(side="right", fill="y")
        self._canvas.pack(side="left", fill="both", expand=True)
        self.body = tk.Frame(self._canvas, bg=C["panel"])
        self._win = self._canvas.create_window((0, 0), window=self.body, anchor="nw")
        self.body.bind("<Configure>", lambda e: self._canvas.configure(
            scrollregion=self._canvas.bbox("all")))
        self._canvas.bind("<Configure>", lambda e:
            self._canvas.itemconfig(self._win, width=e.width))
        _bind_mousewheel(self._canvas)


def random_password(length=12):
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(random.choice(chars) for _ in range(length))


# ─── Shared Tailscale key (unlock code) ──────────────────────────────────────
# The shared key is never built into the EXE (the release secret scan blocks
# that). Typing the unlock code into a Tailscale key box trades it with the
# landing server for the key; the server holds both and rate-limits guesses.
UNLOCK_URL       = "https://remote.novivo.net/api/ts-key"
UNLOCK_CODE_RE   = re.compile(r"[0-9]{6,12}")   # keys start "tskey-", ZT IDs are 16 hex
UNLOCK_SEP_RE    = re.compile(r"[\s.\-]+")      # "0963 090 141" is still the code
UNLOCK_CODEISH   = re.compile(r"[0-9\s.\-]+")   # what is masked while being typed
UNLOCK_AUTO_MS   = 900                          # pause after typing -> unlock by itself
UNLOCK_TIMEOUT_S = 15


def normalize_code(text: str):
    """The unlock code in `text`, or None when `text` is not a code."""
    code = UNLOCK_SEP_RE.sub("", text or "")
    return code if UNLOCK_CODE_RE.fullmatch(code) else None


def _unlock_ssl_context():
    # Windows store first, plus certifi's Mozilla roots: a freshly installed
    # Windows can lack the newer Let's Encrypt roots remote.novivo.net chains to,
    # and Python (unlike browsers) never downloads missing roots by itself.
    ctx = ssl.create_default_context()
    try:
        ctx.load_verify_locations(certifi.where())
    except OSError:
        pass
    return ctx


def fetch_shared_key(code: str):
    """(True, key, "ok") or (False, message, kind) where kind is "wrong" (bad
    code), "locked" (too many bad codes) or "error" (network/server)."""
    req = urllib.request.Request(
        UNLOCK_URL,
        data=json.dumps({"code": code}).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "User-Agent": f"NOVIVO-Remote-Desktop/{APP_VERSION}"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=UNLOCK_TIMEOUT_S,
                                    context=_unlock_ssl_context()) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read().decode("utf-8"))
        except Exception:
            body = None
        # Our server always answers JSON; anything else is Cloudflare/a proxy
        msg = body.get("message") if isinstance(body, dict) else None
        if msg and exc.code == 403:
            return False, msg, "wrong"
        if msg and exc.code == 429:
            return False, msg, "locked"
        return False, msg or f"Máy chủ từ chối (HTTP {exc.code}).", "error"
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, ssl.SSLCertVerificationError):
            return False, ("Lỗi chứng chỉ SSL khi gọi remote.novivo.net — kiểm tra "
                           "ngày giờ của máy tính."), "error"
        if isinstance(exc.reason, (TimeoutError, socket.timeout)):
            return False, f"remote.novivo.net không phản hồi (quá {UNLOCK_TIMEOUT_S} giây).", "error"
        return False, f"Không kết nối được remote.novivo.net: {exc.reason}", "error"
    except (TimeoutError, socket.timeout):
        return False, f"remote.novivo.net không phản hồi (quá {UNLOCK_TIMEOUT_S} giây).", "error"
    except Exception as exc:
        return False, f"Lỗi khi mở khoá key: {type(exc).__name__}: {exc}", "error"
    if not isinstance(body, dict):
        return False, "Máy chủ trả dữ liệu không đúng dạng.", "error"
    key = body.get("key")
    if body.get("ok") and isinstance(key, str) and key.startswith("tskey-"):
        return True, key, "ok"
    return False, "Máy chủ không trả về key.", "error"


# ══════════════════════════════════════════════════════════════════════════════
#  SERVER LIST  (multi-server manager with radio select, save, set-default)
# ══════════════════════════════════════════════════════════════════════════════
class ServerList(tk.Frame):
    """One row per server: [radio] [name entry] [key entry]"""
    _NAME_W   = 14
    _KEY_W    = 26
    _PH_FG    = "#3A4470"
    _PH_NAME  = "Server name…"
    _PH_KEY_TS = "tskey-auth-…"
    _PH_KEY_ZT = "network ID…"
    _MASK     = "•" * 24        # shown in place of an unlocked shared key

    def __init__(self, master, vpn_method_var: tk.StringVar,
                 status_cb=None, log_cb=None, **kw):
        super().__init__(master, bg=C["panel"], **kw)
        self._rows: list[dict] = []
        self._active_idx = tk.IntVar(value=0)
        self._vpn_var = vpn_method_var
        self._status = status_cb or (lambda text: None)
        self._log = log_cb or (lambda text: None)
        self._build_header()
        # Rows grow the frame; the surrounding ScrollFrame scrolls if needed.
        self._inner = tk.Frame(self, bg=C["panel"])
        self._inner.pack(fill="x")
        # Unlock feedback right under the rows (the status bar is easy to miss)
        self._msg = tk.Label(self, text="", bg=C["panel"], fg=C["text_lo"],
                             font=FONT_SMALL, anchor="w", justify="left")

    def _build_header(self):
        hdr = tk.Frame(self, bg=C["grid_head"], height=26)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        tk.Label(hdr, text=" ●", bg=C["grid_head"], fg=C["text_lo"],
                 font=FONT_SMALL, width=3).pack(side="left")
        tk.Label(hdr, text="NAME", bg=C["grid_head"], fg=C["text_lo"],
                 font=FONT_LABELB, anchor="w", padx=4,
                 width=self._NAME_W).pack(side="left")
        self._key_col_lbl = tk.Label(
            hdr, text="TAILSCALE AUTH KEY", bg=C["grid_head"],
            fg=C["text_lo"], font=FONT_LABELB, anchor="w", padx=4)
        self._key_col_lbl.pack(side="left")

    def _ph_key(self):
        return self._PH_KEY_TS if self._vpn_var.get() == "tailscale" else self._PH_KEY_ZT

    def _auto_name(self, idx: int) -> str:
        return f"Server {idx + 1}"

    def add_row(self, name="", key="", is_active=False):
        idx      = len(self._rows)
        # Use numbered default "Server N" — real editable value, not a placeholder
        auto_nm  = self._auto_name(idx)
        disp_name = name if name else auto_nm
        row     = tk.Frame(self._inner, bg=C["input_bg"], height=28)
        row.pack(fill="x", pady=1)
        row.pack_propagate(False)
        n_is_ph = [False]          # name always has a real value (numbered default)
        k_is_ph = [not bool(key)]
        vault   = [None]           # unlocked shared key - memory only, never shown or saved

        rb = tk.Radiobutton(
            row, variable=self._active_idx, value=idx,
            bg=C["input_bg"], activebackground=C["input_bg"],
            selectcolor=C["panel"], fg=C["accent"],
            relief="flat", bd=0, cursor="hand2")
        rb.pack(side="left", padx=(6, 2))
        if is_active:
            self._active_idx.set(idx)

        n_entry = tk.Entry(row, bg="#14183A",
                           fg=C["text_hi"],
                           insertbackground=C["text_hi"], relief="flat",
                           font=FONT_INPUT, width=self._NAME_W)
        n_entry.pack(side="left", ipady=3, padx=(2, 2))
        n_entry.insert(0, disp_name)

        k_entry = tk.Entry(row, bg="#130E28",
                           fg=self._PH_FG if k_is_ph[0] else C["text_hi"],
                           insertbackground=C["text_hi"], relief="flat",
                           font=FONT_INPUT, width=self._KEY_W)
        k_entry.pack(side="left", ipady=3, padx=(0, 2), fill="x", expand=True)
        k_entry.insert(0, key if key else self._ph_key())

        def n_fo(e, _idx=idx, _nm=auto_nm):
            # If user clears the name field, restore the numbered default
            if not n_entry.get().strip():
                n_entry.delete(0, "end"); n_entry.insert(0, _nm)
        def k_fi(e):
            if k_is_ph[0]:
                k_entry.delete(0, "end"); k_entry.config(fg=C["text_hi"]); k_is_ph[0] = False
        def k_fo(e):
            if rec["busy"][0]:
                return
            if not k_entry.get().strip():
                self._cancel_auto(rec)
                k_entry.delete(0, "end"); k_entry.insert(0, self._ph_key())
                k_entry.config(fg=self._PH_FG, show=""); k_is_ph[0] = True
            else:
                self._try_unlock(rec)
        def drop_vault(e=None):
            # Typing or pasting over an unlocked key replaces it entirely. Widget
            # bindings run before the Entry class inserts the character.
            if vault[0]:
                vault[0] = None
                k_entry.delete(0, "end")
        def k_key(e):
            # <Key> outranks <<Paste>> on the widget tag, so Ctrl+V/X land here too
            ctrl_edit = (e.state & 0x4) and e.keysym.lower() in ("v", "x")
            if ((e.char and e.char.isprintable()) or ctrl_edit
                    or e.keysym in ("BackSpace", "Delete")):
                drop_vault()
        def k_typed(e):
            if k_is_ph[0] or vault[0]:
                return
            code = self._row_code(rec)
            if rec["busy"][0]:
                if code == rec["sent"][0]:
                    return                      # nothing changed (Shift, arrows…)
                self._abandon(rec)              # edited mid-request: result is stale
            if rec["failed"][0] and code != rec["failed"][0]:
                rec["failed"][0] = None
                self._show_msg("", C["text_lo"])
            k_entry.config(fg=C["danger"] if code and code == rec["failed"][0]
                           else C["text_hi"])
            self._mask_code(rec)
            self._schedule_auto(rec)

        n_entry.bind("<FocusOut>", n_fo)
        k_entry.bind("<FocusIn>",  k_fi); k_entry.bind("<FocusOut>", k_fo)
        k_entry.bind("<Key>", k_key)
        k_entry.bind("<KeyRelease>", k_typed)
        k_entry.bind("<<Paste>>", drop_vault)
        k_entry.bind("<Return>",   lambda e: self._try_unlock(rec))
        k_entry.bind("<KP_Enter>", lambda e: self._try_unlock(rec))

        rec = {"idx": idx, "frame": row, "radio": rb,
               "ne": n_entry, "ke": k_entry,
               "n_is_ph": n_is_ph, "k_is_ph": k_is_ph,
               "vault": vault, "busy": [False],
               "auto": [None],        # pending after() id of the auto unlock
               "req": [None],         # token of the request in flight
               "sent": [None],        # code of the request in flight
               "failed": [None],      # last code the server rejected
               "then": [None]}        # run after a successful unlock (START)
        self._rows.append(rec)
        if key:
            self._mask_code(rec)

    # ── Unlock code -> shared Tailscale key ──────────────────────────────────
    # Triggers: a pause after typing (auto), Enter, leaving the box, START.
    # The code never stays usable as a "key": get_active_key() never returns it
    # and get_all() never saves it, so a failed unlock can stay in the box.
    def _row_code(self, rec):
        if (self._vpn_var.get() != "tailscale" or rec["k_is_ph"][0]
                or rec["vault"][0]):
            return None
        return normalize_code(rec["ke"].get())

    def _mask_code(self, rec):
        """Hide a code while it is typed; keys and ZeroTier IDs stay visible."""
        text = rec["ke"].get()
        hide = (self._vpn_var.get() == "tailscale" and not rec["k_is_ph"][0]
                and not rec["vault"][0] and bool(UNLOCK_CODEISH.fullmatch(text)))
        rec["ke"].config(show="•" if hide else "")

    def _cancel_auto(self, rec):
        if rec["auto"][0]:
            try:
                self.after_cancel(rec["auto"][0])
            except tk.TclError:
                pass
            rec["auto"][0] = None

    def _schedule_auto(self, rec):
        self._cancel_auto(rec)
        if self._row_code(rec):
            rec["auto"][0] = self.after(UNLOCK_AUTO_MS,
                                        lambda: self._try_unlock(rec, auto=True))

    def _show_msg(self, text, color):
        self._msg.config(text=text, fg=color)
        if text:
            self._msg.pack(fill="x", padx=6, pady=(3, 0))
        else:
            self._msg.pack_forget()

    def _try_unlock(self, rec, auto=False):
        """Start unlocking `rec`. True when a request is (now) in flight."""
        if auto:
            rec["auto"][0] = None
        else:
            self._cancel_auto(rec)
        if rec["busy"][0]:
            return True
        code = self._row_code(rec)
        if not code:
            return False
        if auto and code == rec["failed"][0]:
            return False            # already rejected; Enter/START retries on purpose
        rec["busy"][0] = True
        rec["sent"][0] = code
        token = object()
        rec["req"][0] = token
        self._show_msg("⏳  Đang mở khoá key Tailscale…", C["warn"])
        self._status("Unlocking shared Tailscale key…")

        # The box stays editable (an auto unlock fires mid-typing); editing it
        # abandons this request. The worker never touches Tk, the UI thread
        # polls; the deadline covers what urlopen's timeout doesn't (stuck DNS).
        result = []
        threading.Thread(target=lambda: result.append(fetch_shared_key(code)),
                         daemon=True).start()
        deadline = time.monotonic() + UNLOCK_TIMEOUT_S + 10

        def poll():
            if rec["req"][0] is not token:
                return                              # abandoned
            if result:
                self._unlock_done(rec, code, *result[0])
            elif time.monotonic() > deadline:
                self._unlock_done(rec, code, False,
                                  "remote.novivo.net không phản hồi.", "error")
            else:
                self.after(100, poll)
        self.after(100, poll)
        return True

    def _forget_row(self, rec):
        """Before a row is destroyed: no timer or reply may touch it after."""
        self._cancel_auto(rec)
        if rec["busy"][0]:
            self._abandon(rec)

    def _abandon(self, rec):
        rec["busy"][0] = False
        rec["req"][0] = None
        rec["sent"][0] = None
        rec["then"][0] = None
        self._show_msg("", C["text_lo"])

    def _unlock_done(self, rec, code, ok, payload, kind):
        then = rec["then"][0]
        self._abandon(rec)
        e = rec["ke"]
        try:
            if not e.winfo_exists():
                return                              # row removed meanwhile
        except tk.TclError:
            return
        if self._vpn_var.get() != "tailscale" or normalize_code(e.get()) != code:
            return                                  # switched to ZeroTier / box edited
        if ok:
            rec["vault"][0] = payload
            rec["failed"][0] = None
            e.delete(0, "end")
            e.insert(0, self._MASK)
            e.config(fg=C["success"], show="")
            self._show_msg("🔒  Đã mở khoá key Tailscale dùng chung — key được ẩn, "
                           "không lưu vào máy.", C["success"])
            self._status("Shared Tailscale key unlocked (hidden).")
            self._log("[OK] Đã mở khoá key Tailscale dùng chung (key được ẩn).")
            if then:
                self.after(50, then)
            return
        rec["failed"][0] = code
        e.config(fg=C["danger"])
        hint = {"wrong": "  — sửa lại mã", "locked": "",
                "error": "  — bấm Enter để thử lại"}.get(kind, "")
        self._show_msg(f"✖  {payload}{hint}", C["danger"])
        self._status(f"Key unlock failed: {payload}")
        self._log(f"[ERROR] Mở khoá key Tailscale thất bại: {payload}")

    def unlock_active(self, then=None) -> bool:
        """If the active row holds an unlock code, unlock it and run `then`
        afterwards; True means the caller must wait for that."""
        if not self._rows:
            return False
        idx = self._active_idx.get()
        rec = self._rows[idx if idx < len(self._rows) else 0]
        if not rec["busy"][0] and not self._row_code(rec):
            return False
        rec["then"][0] = then
        if rec["busy"][0]:
            self._show_msg("⏳  Đang mở khoá key Tailscale… (xong sẽ tự chạy tiếp)",
                           C["warn"])
            return True
        return self._try_unlock(rec)

    def remove_active(self):
        if len(self._rows) <= 1:
            return
        idx = self._active_idx.get()
        if idx >= len(self._rows):
            idx = 0
        self._forget_row(self._rows[idx])
        self._rows[idx]["frame"].destroy()
        self._rows.pop(idx)
        for i, r in enumerate(self._rows):
            r["idx"] = i; r["radio"].config(value=i)
        self._active_idx.set(min(idx, len(self._rows) - 1))

    def set_default(self):
        """Move active row to top and keep selected."""
        idx = self._active_idx.get()
        if idx <= 0:
            return
        sel = self._rows.pop(idx)
        self._rows.insert(0, sel)
        for r in self._rows:
            r["frame"].pack_forget()
        for r in self._rows:
            r["frame"].pack(fill="x", pady=1)
        for i, r in enumerate(self._rows):
            r["idx"] = i; r["radio"].config(value=i)
        self._active_idx.set(0)

    def get_active_key(self) -> str:
        if not self._rows:
            return ""
        idx = self._active_idx.get()
        if idx >= len(self._rows):
            idx = 0
        r = self._rows[idx]
        if r["vault"][0]:
            return r["vault"][0]
        if r["k_is_ph"][0] or self._row_code(r):
            return ""                       # an unlock code is never a key
        return r["ke"].get().strip()

    def _saved_key(self, r) -> str:
        # Neither the unlocked shared key nor an unlock code goes to servers.json
        if r["k_is_ph"][0] or r["vault"][0]:
            return ""
        text = r["ke"].get().strip()
        return "" if normalize_code(text) else text

    def get_all(self) -> list[dict]:
        active = self._active_idx.get()
        return [{"name":   r["ne"].get().strip() or self._auto_name(i),
                 "key":    self._saved_key(r),
                 "active": i == active}
                for i, r in enumerate(self._rows)]

    def load_all(self, servers: list[dict]):
        # servers.json is user-editable - keep only well-formed rows
        servers = [s for s in servers if isinstance(s, dict)] if isinstance(servers, list) else []
        for r in self._rows:
            self._forget_row(r)
            r["frame"].destroy()
        self._rows.clear()
        for i, srv in enumerate(servers):
            self.add_row(name=srv.get("name", ""),
                         key=srv.get("key", ""),
                         is_active=srv.get("active", i == 0))
        if not self._rows:
            self.add_row()

    def update_key_placeholders(self):
        is_ts = self._vpn_var.get() == "tailscale"
        ph = self._ph_key()
        # Update column header
        self._key_col_lbl.config(
            text="TAILSCALE AUTH KEY" if is_ts else "ZEROTIER NETWORK ID")
        # Update placeholder text in empty key rows
        for r in self._rows:
            if not is_ts:                           # shared key is Tailscale-only
                self._cancel_auto(r)
                r["then"][0] = None
                if r["vault"][0]:
                    r["vault"][0] = None
                    r["k_is_ph"][0] = True
                    r["ke"].config(fg=self._PH_FG)
            if r["k_is_ph"][0]:
                r["ke"].delete(0, "end")
                r["ke"].insert(0, ph)
            self._mask_code(r)
        if not is_ts:
            self._show_msg("", C["text_lo"])


# ══════════════════════════════════════════════════════════════════════════════
#  USER TABLE  (pure tkinter – CTk has no DataGrid)
# ══════════════════════════════════════════════════════════════════════════════
class UserTable(tk.Frame):
    COL_W = (200, 230)

    def __init__(self, master, **kw):
        super().__init__(master, bg=C["panel"], **kw)
        self._show_pass = False
        self._rows: list[dict] = []   # [{user, pass, vars…}]
        self._build_header()
        # Rows grow the frame; the surrounding ScrollFrame scrolls if needed.
        self._scroll_frame = tk.Frame(self, bg=C["panel"])
        self._scroll_frame.pack(fill="x")

    def _build_header(self):
        hdr = tk.Frame(self, bg=C["grid_head"], height=28)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        for i, text in enumerate(("USERNAME", "PASSWORD")):
            tk.Label(hdr, text=text, bg=C["grid_head"], fg=C["text_lo"],
                     font=FONT_LABELB, anchor="w", padx=8,
                     width=self.COL_W[i] // 8).pack(side="left")

    # Colours per column
    _U_BG     = "#14183A"   # username  – dark blue
    _P_BG     = "#130E28"   # password  – dark purple
    _U_BG_SEL = "#1A1F48"   # selected username
    _P_BG_SEL = "#1A1235"   # selected password
    _PH_FG    = "#3A4470"   # placeholder muted colour

    _PH_U = "enter username…"
    _PH_P = "enter password…"

    def add_row(self, username="", password=""):
        row_frame = tk.Frame(self._scroll_frame, bg=C["input_bg"], height=28)
        row_frame.pack(fill="x", pady=1)
        row_frame.pack_propagate(False)

        sel_var  = tk.BooleanVar(value=False)
        u_is_ph  = [not bool(username)]   # mutable flag via list
        p_is_ph  = [not bool(password)]

        # Selection indicator stripe
        sel_dot = tk.Frame(row_frame, bg=C["input_bg"], width=4)
        sel_dot.pack(side="left", fill="y")

        def on_click(e=None):
            for r in self._rows:
                self._style_unselected(r)
            sel_var.set(True)
            sel_dot.config(bg=C["accent"])
            row_frame.config(bg="#1A1F40")
            u_entry.config(bg=self._U_BG_SEL)
            p_entry.config(bg=self._P_BG_SEL)

        # ── Username entry ────────────────────────────────────────────────
        u_entry = tk.Entry(row_frame,
                           bg=self._U_BG,
                           fg=self._PH_FG if u_is_ph[0] else C["text_hi"],
                           insertbackground=C["text_hi"],
                           relief="flat", font=FONT_INPUT,
                           width=self.COL_W[0] // 8)
        u_entry.pack(side="left", ipady=4, padx=(2, 0))
        u_entry.insert(0, username if username else self._PH_U)

        def u_focus_in(e):
            if u_is_ph[0]:
                u_entry.delete(0, "end")
                u_entry.config(fg=C["text_hi"])
                u_is_ph[0] = False

        def u_focus_out(e):
            if not u_entry.get().strip():
                u_entry.delete(0, "end")
                u_entry.insert(0, self._PH_U)
                u_entry.config(fg=self._PH_FG)
                u_is_ph[0] = True

        u_entry.bind("<FocusIn>",  u_focus_in)
        u_entry.bind("<FocusOut>", u_focus_out)

        # ── Password entry ────────────────────────────────────────────────
        p_entry = tk.Entry(row_frame,
                           bg=self._P_BG,
                           fg=self._PH_FG if p_is_ph[0] else C["text_hi"],
                           insertbackground=C["text_hi"],
                           relief="flat", font=FONT_INPUT,
                           width=self.COL_W[1] // 8,
                           show="" if p_is_ph[0] else ("•" if not self._show_pass else ""))
        p_entry.pack(side="left", ipady=4, padx=(4, 0))
        p_entry.insert(0, password if password else self._PH_P)

        def p_focus_in(e):
            if p_is_ph[0]:
                p_entry.delete(0, "end")
                p_entry.config(fg=C["text_hi"],
                               show="•" if not self._show_pass else "")
                p_is_ph[0] = False

        def p_focus_out(e):
            if not p_entry.get():
                p_entry.delete(0, "end")
                p_entry.insert(0, self._PH_P)
                p_entry.config(fg=self._PH_FG, show="")
                p_is_ph[0] = True

        p_entry.bind("<FocusIn>",  p_focus_in)
        p_entry.bind("<FocusOut>", p_focus_out)

        # Click → select row
        for w in (row_frame, sel_dot):
            w.bind("<Button-1>", on_click)
        u_entry.bind("<Button-1>", lambda e: (on_click(), u_entry.focus_set()))
        p_entry.bind("<Button-1>", lambda e: (on_click(), p_entry.focus_set()))

        row_data = {"u_is_ph": u_is_ph, "p_is_ph": p_is_ph,
                    "sel": sel_var, "frame": row_frame, "dot": sel_dot,
                    "ue": u_entry, "pe": p_entry}
        self._rows.append(row_data)

    def _style_unselected(self, r):
        r["sel"].set(False)
        r["dot"].config(bg=C["input_bg"])
        r["frame"].config(bg=C["input_bg"])
        r["ue"].config(bg=self._U_BG)
        r["pe"].config(bg=self._P_BG)

    def remove_selected(self):
        doomed = [r for r in self._rows if r["sel"].get()]
        if not doomed:
            return
        # The table must never end up empty. When every row is selected the first
        # one survives (just deselected) - a destroyed frame cannot be packed
        # again, that raises TclError: bad window path name.
        if len(doomed) == len(self._rows):
            self._style_unselected(doomed.pop(0))
        dead = {id(r) for r in doomed}
        for r in doomed:
            r["frame"].destroy()
        self._rows = [r for r in self._rows if id(r) not in dead]

    def set_show_passwords(self, show: bool):
        self._show_pass = show
        for r in self._rows:
            if not r["p_is_ph"][0]:   # don't touch placeholder rows
                r["pe"].config(show="" if show else "•")

    def randomize_selected(self):
        selected = [r for r in self._rows if r["sel"].get()] or self._rows
        for r in selected:
            pwd = random_password()
            r["pe"].delete(0, "end")
            r["pe"].insert(0, pwd)
            r["pe"].config(fg=C["text_hi"],
                           show="•" if not self._show_pass else "")
            r["p_is_ph"][0] = False

    def clear_passwords(self):
        for r in self._rows:
            r["pe"].delete(0, "end")
            r["pe"].insert(0, self._PH_P)
            r["pe"].config(fg=self._PH_FG, show="")
            r["p_is_ph"][0] = True

    def get_users(self) -> list[dict]:
        result = []
        for r in self._rows:
            u = "" if r["u_is_ph"][0] else r["ue"].get().strip()
            p = "" if r["p_is_ph"][0] else r["pe"].get()
            if u:
                result.append({"Username": u, "Password": p})
        return result


# ══════════════════════════════════════════════════════════════════════════════
#  MAIN APP
# ══════════════════════════════════════════════════════════════════════════════
class NovivoCTkApp(ctk.CTk):
    def __init__(self):
        super().__init__(fg_color=C["bg"])
        self._setup_scrollbar_style()
        self.title("NOVIVO Remote Desktop")
        self.geometry("1080x700")
        self.minsize(900, 620)
        self.resizable(True, True)

        # icon
        ico = _asset("icon.ico")
        if os.path.exists(ico):
            self.iconbitmap(ico)

        self._vpn_method = tk.StringVar(value="tailscale")
        self._install_running = False

        self._build_header()
        self._build_body()
        self._build_statusbar()
        self._show_briefing()
        # Auto-save servers on close
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _show_briefing(self):
        """The log pane is empty until a run starts - use it to say plainly what
        START SETUP is going to do to this machine."""
        for line in (
            "=== NOVIVO REMOTE DESKTOP SETUP ===",
            "",
            "Pressing START SETUP changes THIS computer:",
            "",
            "[INFO] 1. Installs and connects the selected VPN (Tailscale / ZeroTier)",
            "[INFO]    and sets it to reconnect at every boot, before anyone logs in",
            "[INFO] 2. Creates or updates the Windows accounts listed on the left",
            "[INFO]    and adds every one of them to the Administrators group",
            "[INFO] 3. Enables Remote Desktop, opens the firewall on the RDP port",
            "[INFO] 4. Disables Network Level Authentication (NLA)",
            "[INFO] 5. Turns sleep and hibernate off for good (plugged in and on",
            "[INFO]    battery; lid close does nothing when plugged in), re-applied",
            "[INFO]    at every boot",
            "[WARNING] 6. If the RDP listener will not start, this machine RESTARTS",
            "[WARNING]    automatically 30 seconds after setup finishes.",
            "[INFO]    A pending restart can be cancelled with:  shutdown /a",
            "",
            "--- The installation log replaces this text when setup begins ---",
        ):
            self._log_write(line)

    # ── Scrollbar style ──────────────────────────────────────────────────────
    def _setup_scrollbar_style(self):
        s = ttk.Style(self)
        s.theme_use("clam")
        s.configure("Dark.Vertical.TScrollbar",
                    background=C["input_bg"],      # thumb
                    troughcolor=C["bg"],            # track
                    bordercolor=C["bg"],
                    arrowcolor=C["btn_dim"],
                    darkcolor=C["input_bg"],
                    lightcolor=C["input_bg"],
                    relief="flat",
                    arrowsize=10,
                    width=8)
        s.map("Dark.Vertical.TScrollbar",
              background=[("active", C["accent"]), ("pressed", C["accent_hov"])])

    # ── Header ───────────────────────────────────────────────────────────────
    def _build_header(self):
        hdr = tk.Frame(self, bg=C["header_bg"], height=86)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)

        # left accent stripe
        tk.Frame(hdr, bg=C["accent"], width=5).pack(side="left", fill="y")

        # NOVIVO hexagon logo (LOGO KO CHU.png)
        try:
            _img = Image.open(LOGO_ICO).convert("RGBA").resize((54, 54), Image.LANCZOS)
            self._logo_img = ImageTk.PhotoImage(_img)   # keep ref to avoid GC
            tk.Label(hdr, image=self._logo_img,
                     bg=C["header_bg"], bd=0).pack(side="left", padx=(12, 0))
        except Exception:
            pass

        # brand text block
        brand_block = tk.Frame(hdr, bg=C["header_bg"])
        brand_block.pack(side="left", padx=(10, 0))
        tk.Label(brand_block, text="NOVIVO", bg=C["header_bg"],
                 fg=C["text_hi"], font=FONT_BRAND).pack(anchor="w")
        tk.Label(brand_block, text="Remote Desktop Setup Tool",
                 bg=C["header_bg"], fg=C["text_lo"],
                 font=("Segoe UI", 10)).pack(anchor="w")

        # right: admin badge + version
        right = tk.Frame(hdr, bg=C["header_bg"])
        right.pack(side="right", padx=20)
        badge_row = tk.Frame(right, bg=C["header_bg"])
        badge_row.pack(anchor="e")
        tk.Frame(badge_row, bg=C["success"], width=8, height=8).pack(side="left", pady=2)
        tk.Label(badge_row, text="  Administrator", bg=C["header_bg"],
                 fg=C["success"], font=FONT_LABELB).pack(side="left")
        tk.Label(right, text=f"v{APP_VERSION}", bg=C["header_bg"],
                 fg=C["text_lo"], font=FONT_SMALL).pack(anchor="e")

        # bottom accent line
        tk.Frame(self, bg=C["accent"], height=2).pack(fill="x")

    # ── Body (2 columns) ─────────────────────────────────────────────────────
    def _build_body(self):
        body = tk.Frame(self, bg=C["bg"])
        body.pack(fill="both", expand=True)
        # Both columns grow with the window. Previously column 0 was pinned at
        # 460px, so every pixel gained by resizing went to the empty log pane.
        body.columnconfigure(0, weight=2, minsize=460)
        body.columnconfigure(1, weight=0)
        body.columnconfigure(2, weight=3)
        body.rowconfigure(0, weight=1)

        self._build_left(body)
        tk.Frame(body, bg=C["border"], width=1).grid(row=0, column=1, sticky="ns")
        self._build_right(body)

    # ── Left Config Panel ─────────────────────────────────────────────────────
    def _build_left(self, parent):
        left = tk.Frame(parent, bg=C["panel"])
        left.grid(row=0, column=0, sticky="nsew")

        # Packed FIRST and against the bottom edge, so a growing user table can
        # never push the primary action off-screen the way it used to.
        self._btn_start = ctk.CTkButton(
            left,
            text="▶  START SETUP",
            command=self._start_install,
            fg_color=C["accent"],
            hover_color=C["accent_hov"],
            text_color="white",
            corner_radius=6,
            font=FONT_BTN_LG,
            height=48)
        self._btn_start.pack(side="bottom", fill="x", padx=14, pady=(0, 14))
        tk.Frame(left, bg=C["border"], height=1).pack(side="bottom", fill="x",
                                                      pady=(10, 12))

        # Everything above the button scrolls, so no control is ever clipped.
        scroller = ScrollFrame(left)
        scroller.pack(fill="both", expand=True)
        left = scroller.body

        # ── VPN METHOD ───────────────────────────────────────────────────────
        self._section_header(left, "VPN METHOD", C["accent"])

        vpn_row = tk.Frame(left, bg=C["panel"])
        vpn_row.pack(fill="x", padx=14, pady=(4, 0))

        self._btn_ts = self._vpn_btn(vpn_row, "TAILSCALE", "tailscale", side="left")
        self._btn_zt = self._vpn_btn(vpn_row, "ZEROTIER",  "zerotier",  side="right")
        self._refresh_vpn_buttons()

        tk.Frame(left, bg=C["border"], height=1).pack(fill="x", pady=8)

        # ── VPN SERVERS ──────────────────────────────────────────────────────
        self._section_header(left, "VPN SERVERS", C["warn"])

        self._server_list = ServerList(left, self._vpn_method, status_cb=self._set_status,
                                       log_cb=self._log_write)
        self._server_list.pack(fill="x", padx=14, pady=(4, 0))

        # Load saved servers or add default row
        self._load_servers()

        # Server action buttons
        srv_btns = tk.Frame(left, bg=C["panel"])
        srv_btns.pack(fill="x", padx=14, pady=(6, 0))
        self._flat_btn(srv_btns, "+ Add Server",    C["warn"],    self._add_server,      w=110).pack(side="left", padx=(0, 4))
        self._flat_btn(srv_btns, "- Remove Server", C["danger"],  self._remove_server,   w=130).pack(side="left", padx=(0, 4))
        # Renamed: the radio button already says which server is active - this
        # button only reorders the list, so it should say so.
        self._flat_btn(srv_btns, "↑ To Top",        C["purple"],  self._set_default_srv, w=85 ).pack(side="left", padx=(0, 4))
        self._flat_btn(srv_btns, "Save",            C["success"], self._save_servers,    w=75 ).pack(side="left")

        # Dynamic VPN mode hint
        self._vpn_hint = tk.Label(
            left, text="ℹ  Tailscale: paste a tskey-auth-… key, or type the unlock code",
            bg=C["panel"], fg=C["text_lo"], font=("Segoe UI", 8), anchor="w", padx=18)
        self._vpn_hint.pack(fill="x", pady=(2, 0))

        tk.Frame(left, bg=C["border"], height=1).pack(fill="x", pady=8)

        # ── REMOTE DESKTOP ───────────────────────────────────────────────────
        self._section_header(left, "REMOTE DESKTOP ACCESS", C["success"])

        # The port configures RDP, not the VPN server list it used to sit under.
        port_row = tk.Frame(left, bg=C["panel"])
        port_row.pack(fill="x", padx=14, pady=(6, 0))
        tk.Label(port_row, text="RDP PORT:", bg=C["panel"], fg=C["text_lo"],
                 font=FONT_LABELB).pack(side="left")
        self._rdp_port = tk.Entry(port_row, bg=C["input_bg"], fg=C["text_hi"],
                                  insertbackground=C["text_hi"], relief="flat",
                                  font=FONT_INPUT, width=6, justify="center")
        self._rdp_port.insert(0, "3389")
        self._rdp_port.pack(side="left", ipady=3, padx=(6, 0))
        tk.Label(port_row, text="(default 3389 — change if blocked)",
                 bg=C["panel"], fg=C["text_lo"], font=("Segoe UI", 8)).pack(side="left", padx=(6, 0))

        self._table = UserTable(left)
        self._table.pack(fill="x", padx=14, pady=(8, 0))
        self._table.add_row(os.environ.get("USERNAME", ""), "")

        # The toggle sits directly under the table it controls
        chk_row = tk.Frame(left, bg=C["panel"])
        chk_row.pack(fill="x", padx=14, pady=(4, 0))
        self._chk_show = ctk.CTkCheckBox(
            chk_row, text="Show passwords",
            variable=tk.BooleanVar(value=False),
            command=self._toggle_show_pass,
            text_color=C["text_lo"],
            fg_color=C["accent"],
            font=("Segoe UI", 9))
        self._chk_show.pack(side="left")

        btn_row1 = tk.Frame(left, bg=C["panel"])
        btn_row1.pack(fill="x", padx=14, pady=(8, 0))
        self._flat_btn(btn_row1, "+ Add User",    C["accent"],   self._add_user,   w=100).pack(side="left", padx=(0, 4))
        self._flat_btn(btn_row1, "- Remove User", C["danger"],   self._rem_user,   w=115).pack(side="left", padx=(0, 4))
        self._flat_btn(btn_row1, "Random Pwd",    C["success"],  self._rand_pass,  w=105).pack(side="left", padx=(0, 4))
        self._flat_btn(btn_row1, "Clear All",     C["text_lo"],  self._clear_pass, w=90 ).pack(side="left")

        tk.Frame(left, bg=C["border"], height=1).pack(fill="x", pady=8)

        # ── THIS TOOL ────────────────────────────────────────────────────────
        # Separate from START SETUP: this configures the tool itself, not the
        # VPN or the RDP host, and it only ever needs running once per machine.
        self._section_header(left, "THIS TOOL", C["purple"])

        self._btn_always_admin = ctk.CTkButton(
            left,
            text=BTN_ALWAYS_ADMIN,
            command=self._set_always_admin,
            fg_color=C["purple"],
            hover_color="#8F63E8",
            text_color="white",
            corner_radius=6,
            font=FONT_BTN,
            height=36)
        self._btn_always_admin.pack(fill="x", padx=14, pady=(6, 0))

        tk.Label(left,
                 text="ℹ  Machine-wide admin flag + a Desktop shortcut that skips the UAC prompt",
                 bg=C["panel"], fg=C["text_lo"], font=("Segoe UI", 8),
                 anchor="w", padx=18, wraplength=420, justify="left").pack(fill="x", pady=(2, 0))

        tk.Frame(left, bg=C["panel"], height=10).pack(fill="x")

    # ── Right Log Panel ────────────────────────────────────────────────────────
    def _build_right(self, parent):
        right = tk.Frame(parent, bg=C["log_bg"])
        right.grid(row=0, column=2, sticky="nsew")
        right.rowconfigure(1, weight=1)
        right.columnconfigure(0, weight=1)

        # log header band
        log_hdr = tk.Frame(right, bg=C["panel2"], height=34)
        log_hdr.grid(row=0, column=0, sticky="ew")
        log_hdr.pack_propagate(False)
        tk.Frame(log_hdr, bg=C["log_fg"], width=3).pack(side="left", fill="y")
        tk.Label(log_hdr, text="INSTALLATION LOG", bg=C["panel2"],
                 fg=C["log_fg"], font=FONT_TITLE, padx=10).pack(side="left")

        # clear log button
        clr = tk.Label(log_hdr, text="✕ clear", bg=C["panel2"],
                       fg=C["text_lo"], font=FONT_SMALL, cursor="hand2", padx=8)
        clr.pack(side="right")
        clr.bind("<Button-1>", lambda e: self._clear_log())

        # log text area
        log_frame = tk.Frame(right, bg=C["log_bg"])
        log_frame.grid(row=1, column=0, sticky="nsew")

        self._log = tk.Text(log_frame, bg=C["log_bg"], fg=C["log_fg"],
                            font=FONT_LOG, relief="flat", wrap="word",
                            state="disabled", padx=10, pady=6,
                            insertbackground=C["log_fg"])
        scroll = ttk.Scrollbar(log_frame, command=self._log.yview,
                              style="Dark.Vertical.TScrollbar")
        self._log.config(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self._log.pack(side="left", fill="both", expand=True)

        # colour tags
        self._log.tag_config("ok",   foreground="#00C480")
        self._log.tag_config("err",  foreground="#E03C46")
        self._log.tag_config("warn", foreground="#FFB428")
        self._log.tag_config("info", foreground="#6090CC")
        self._log.tag_config("sep",  foreground="#2A3460")
        self._log.tag_config("head", foreground="#4A7CFF", font=("Consolas", 9, "bold"))

        # bottom bar: copy + progress + close
        bot = tk.Frame(right, bg=C["panel2"], height=46)
        bot.grid(row=2, column=0, sticky="ew")
        bot.pack_propagate(False)

        self._btn_copy = self._flat_btn(
            bot, "COPY LOG", C["btn_dim"], self._copy_log, w=130)
        self._btn_copy.pack(side="left", padx=(10, 0), pady=8)

        self._progress = ctk.CTkProgressBar(bot, mode="indeterminate",
                                            fg_color=C["border"],
                                            progress_color=C["accent"],
                                            height=6, width=200)
        # not packed here - shown only while an install is running

        close_btn = ctk.CTkButton(
            bot, text="✕  CLOSE",
            command=self._on_close,
            fg_color="#2C0E10", hover_color="#3C1418",
            text_color=C["danger"],
            corner_radius=4,
            font=FONT_BTN,
            width=110, height=30)
        close_btn.pack(side="right", padx=10, pady=8)

    # ── Status bar ────────────────────────────────────────────────────────────
    def _build_statusbar(self):
        bar = tk.Frame(self, bg=C["status_bg"], height=26)
        bar.pack(fill="x", side="bottom")
        bar.pack_propagate(False)
        self._lbl_status = tk.Label(bar, text="Ready  |  Running as Administrator",
                                     bg=C["status_bg"], fg=C["text_lo"],
                                     font=FONT_SMALL, anchor="w", padx=12)
        self._lbl_status.pack(side="left")
        tk.Label(bar, text=f"NOVIVO Remote Desktop  v{APP_VERSION}",
                 bg=C["status_bg"], fg=C["text_lo"],
                 font=FONT_SMALL, anchor="e", padx=12).pack(side="right")

    # ── Widget helpers ────────────────────────────────────────────────────────
    def _section_header(self, parent, text, accent_color):
        hdr = tk.Frame(parent, bg="#12162E", height=30)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        tk.Frame(hdr, bg=accent_color, width=3).pack(side="left", fill="y")
        tk.Label(hdr, text=text, bg="#12162E", fg=accent_color,
                 font=FONT_TITLE, padx=10).pack(side="left")

    def _flat_btn(self, parent, text, color, cmd, w=None, h=30):
        """Secondary action: outlined, so START SETUP is the only solid button
        on screen and reads as the primary action."""
        kw = dict(width=w) if w else {}
        b = ctk.CTkButton(parent, text=text, command=cmd,
                          fg_color="transparent", bg_color=parent.cget("bg"),
                          border_width=1, border_color=color,
                          hover_color=C["btn_hov"],
                          text_color=color, corner_radius=4,
                          font=FONT_BTN, height=h, **kw)
        return b

    def _vpn_btn(self, parent, label, value, side):
        btn = ctk.CTkButton(
            parent, text=label, width=210, height=38,
            corner_radius=4, font=FONT_BTN,
            fg_color=C["accent"] if self._vpn_method.get() == value else C["btn_dim"],
            hover_color=C["accent_hov"],
            text_color="white",
            command=lambda v=value: self._select_vpn(v))
        # fill/expand so the pair splits the panel evenly at any window width
        btn.pack(side=side, fill="x", expand=True,
                 padx=(0, 4) if side == "left" else (4, 0))
        return btn

    def _refresh_vpn_buttons(self):
        pass  # state handled in _select_vpn

    def _select_vpn(self, value):
        self._vpn_method.set(value)
        if value == "tailscale":
            self._btn_ts.configure(fg_color=C["accent"])
            self._btn_zt.configure(fg_color=C["btn_dim"])
            self._vpn_hint.config(
                text="ℹ  Tailscale: paste a tskey-auth-… key, or type the unlock code",
                fg=C["text_lo"])
        else:
            self._btn_zt.configure(fg_color=C["accent"])
            self._btn_ts.configure(fg_color=C["btn_dim"])
            self._vpn_hint.config(
                text="ℹ  ZeroTier: paste Network ID (16-char hex) for each server",
                fg="#5A8AFF")
        self._server_list.update_key_placeholders()

    # ── Server list actions ───────────────────────────────────────────────────
    def _add_server(self):
        self._server_list.add_row()

    def _remove_server(self):
        self._server_list.remove_active()

    def _set_default_srv(self):
        self._server_list.set_default()
        self._set_status("Default server updated.")

    def _save_servers(self):
        data = self._server_list.get_all()
        try:
            with open(SERVERS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            self._set_status(f"Saved {len(data)} server(s) to servers.json")
        except Exception as exc:
            messagebox.showerror("Save Error", str(exc))

    def _on_close(self):
        """Auto-save server list then close the window."""
        if self._install_running and not messagebox.askyesno(
                "Setup running",
                "Setup is still running.\nClosing now leaves it unfinished.\n\nClose anyway?"):
            return
        try:
            data = self._server_list.get_all()
            with open(SERVERS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
        except Exception:
            pass
        self.destroy()

    def _load_servers(self):
        if os.path.exists(SERVERS_FILE):
            try:
                with open(SERVERS_FILE, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if data:
                    self._server_list.load_all(data)
                    return
            except Exception:
                pass
        # Default: one empty row - the tool ships no credential of its own
        self._server_list.add_row(name="Default", key="", is_active=True)

    # ── User table actions ────────────────────────────────────────────────────
    def _add_user(self):
        self._table.add_row()

    def _rem_user(self):
        self._table.remove_selected()

    def _rand_pass(self):
        self._table.randomize_selected()

    def _clear_pass(self):
        if messagebox.askyesno("Clear Passwords", "Clear all passwords?"):
            self._table.clear_passwords()

    def _toggle_show_pass(self):
        self._table.set_show_passwords(self._chk_show.get())

    # ── Log helpers ───────────────────────────────────────────────────────────
    def _log_write(self, line: str):
        self._log.config(state="normal")
        # pick colour tag
        tag = None
        l = line.strip()
        if l.startswith("[OK]"):         tag = "ok"
        elif l.startswith("[ERROR]") or l.startswith("[CRITICAL"): tag = "err"
        elif l.startswith("[WARNING]"):  tag = "warn"
        elif l.startswith("[INFO]"):     tag = "info"
        elif l.startswith("===") or l.startswith(">>>"): tag = "head"
        elif l.startswith("---"):        tag = "sep"
        if tag:
            self._log.insert("end", line + "\n", tag)
        else:
            self._log.insert("end", line + "\n")
        self._log.see("end")
        self._log.config(state="disabled")

    def _clear_log(self):
        self._log.config(state="normal")
        self._log.delete("1.0", "end")
        self._log.config(state="disabled")

    def _copy_log(self):
        text = self._log.get("1.0", "end").strip()
        if not text:
            messagebox.showinfo("Copy Log", "Log is empty.")
            return
        self.clipboard_clear()
        self.clipboard_append(text)
        self._btn_copy.configure(text="✓ COPIED!", fg_color=C["success"])
        self.after(1600, lambda: self._btn_copy.configure(
            text="COPY LOG", fg_color="transparent"))

    def _set_status(self, text):
        self._lbl_status.config(text=text)

    def _ui(self, fn, *args):
        """Marshal a call from the worker thread; drop it if the window is gone."""
        try:
            self.after(0, fn, *args)
        except (tk.TclError, RuntimeError):
            pass

    # ── Install ───────────────────────────────────────────────────────────────
    def _start_install(self):
        if self._install_running:
            return

        net_key = self._server_list.get_active_key()
        method  = self._vpn_method.get()
        users   = self._table.get_users()

        # Unlock code still in the box (START doesn't take focus, so the box may
        # never have lost it): trade it for the key first, then START resumes.
        if method == "tailscale" and self._server_list.unlock_active(then=self._start_install):
            return

        # Validate
        if not net_key:
            messagebox.showerror("Validation",
                "No server key selected.\nAdd a server and enter its Auth Key / Network ID.")
            return
        if method == "zerotier" and net_key.lower().startswith("tskey-"):
            if not messagebox.askyesno("Check server key",
                "ZeroTier is selected but this key looks like a Tailscale auth key "
                "(tskey-…).\n\nRun anyway?"):
                return
        if method == "tailscale" and re.fullmatch(r"[0-9a-fA-F]{16}", net_key):
            if not messagebox.askyesno("Check server key",
                "Tailscale is selected but this key looks like a ZeroTier network ID "
                "(16 hex characters).\n\nRun anyway?"):
                return
        if not users:
            messagebox.showerror("Validation", "Add at least one user.")
            return
        for u in users:
            if not u["Password"]:
                messagebox.showerror("Validation",
                    f"Password for '{u['Username']}' cannot be empty.")
                return

        rdp_port = self._rdp_port.get().strip()
        if not rdp_port.isdigit() or not (1 <= int(rdp_port) <= 65535):
            messagebox.showerror("Validation", "RDP port must be a number between 1 and 65535.")
            return

        if not messagebox.askokcancel(
                "Confirm setup",
                # short lines - the message box re-wraps anything longer
                "This will modify THIS computer (%s).\n\n"
                "VPN method :  %s\n"
                "RDP port   :  %s\n"
                "Accounts   :  %s\n\n"
                "The accounts above are created or updated\n"
                "and added to local Administrators.\n"
                "Remote Desktop is enabled, firewall opened.\n"
                "NLA is disabled.\n"
                "Sleep and hibernate are turned off for good.\n"
                "If the RDP listener will not start, this\n"
                "machine restarts itself 30s after setup.\n\n"
                "Continue?" % (
                    os.environ.get("COMPUTERNAME", "this machine"),
                    method, rdp_port,
                    ", ".join(u["Username"] for u in users)),
                icon="warning", default=messagebox.CANCEL):
            return

        self._begin_busy(self._btn_start, "⏳  RUNNING…", "Installing…")
        self._clear_log()

        self._run_ps(BACKEND, [
            "-Method",     method,
            "-NetworkKey", net_key,
            "-UsersJson",  json.dumps(users),
            "-RdpPort",    rdp_port,
        ], self._install_done)

    # ── Backend runner (shared by every PowerShell action) ────────────────────
    def _begin_busy(self, btn, busy_text, status):
        """Lock both action buttons for the duration of one backend run."""
        self._install_running = True
        self._btn_start.configure(state="disabled")
        self._btn_always_admin.configure(state="disabled")
        btn.configure(text=busy_text)
        self._progress.pack(side="left", padx=14, pady=18)
        self._progress.start()
        self._set_status(status)

    def _end_busy(self):
        self._install_running = False
        self._btn_start.configure(state="normal", text="▶  START SETUP")
        self._btn_always_admin.configure(state="normal", text=BTN_ALWAYS_ADMIN)
        self._progress.stop()
        self._progress.pack_forget()

    def _run_ps(self, script: str, args: list, done_cb):
        """Run a bundled PowerShell script on a worker thread, streaming each
        line it prints into the log. done_cb(exit_code) runs on the UI thread."""
        # Reset the per-run outcome the backend reports via its final
        # "[NOVIVO-RESULT] <STATE>" line (see _scan_result_line).
        self._run_result = None
        def run():
            ps_cmd = ["powershell.exe",
                      "-NoProfile",
                      "-ExecutionPolicy", "Bypass",
                      "-File", script] + args
            try:
                proc = subprocess.Popen(
                    ps_cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    creationflags=subprocess.CREATE_NO_WINDOW)

                for line in proc.stdout:
                    text = line.rstrip()
                    self._scan_result_line(text)
                    self._ui(self._log_write, text)

                proc.wait()
                self._ui(done_cb, proc.returncode)
            except Exception as exc:
                self._ui(self._log_write,
                         f"[ERROR] Failed to run {os.path.basename(script)}: {exc}")
                self._ui(done_cb, -1)

        threading.Thread(target=run, daemon=True).start()

    def _scan_result_line(self, text: str):
        """Capture the backend's machine-readable verdict. The backend prints
        exactly one '[NOVIVO-RESULT] <STATE>' line near the end; the last one
        wins. This is the primary success signal — the exit code is a fallback
        for older backends that don't emit it."""
        marker = "[NOVIVO-RESULT]"
        idx = text.find(marker)
        if idx != -1:
            state = text[idx + len(marker):].strip().split()
            if state:
                self._run_result = state[0].upper()

    def _install_done(self, exit_code: int):
        self._end_busy()
        # Prefer the backend's explicit verdict; fall back to the exit code
        # (0=success, 3=restart, 4=authorise) for backends without the marker.
        result = getattr(self, "_run_result", None)
        if result is None:
            result = {0: "SUCCESS", 2: "NOT_SUPPORTED", 3: "NEEDS_RESTART",
                      4: "NEEDS_AUTH"}.get(exit_code, "FAILED")

        if result == "SUCCESS":
            self._set_status("Setup completed — RDP is ready.")
            self._log_write("\n[OK] RDP listener verified. You can connect now.")
        elif result == "NEEDS_RESTART":
            self._set_status("Setup done, but a RESTART is required for RDP to start.")
            self._log_write("\n[ACTION] Restart this machine, then wait ~2 minutes "
                            "before connecting. RDP is NOT listening yet.")
        elif result == "NEEDS_AUTH":
            self._set_status("Setup done — authorise this device in the console to connect.")
            self._log_write("\n[ACTION] RDP is listening locally, but this device is not "
                            "reachable yet. Authorise it in the Tailscale/ZeroTier console, "
                            "then wait ~1 minute.")
        elif result == "NOT_SUPPORTED":
            self._set_status("This Windows can't host the selected method — see the log.")
            self._log_write("\n[INFO] Setup stopped and made no changes. Try the other "
                            "network method, or use a supported Windows edition/build.")
        else:  # FAILED / unknown
            self._set_status(f"Setup FAILED — RDP is not ready (see log). Code {exit_code}.")
            self._log_write(f"\n[ERROR] Setup did not complete successfully "
                            f"(result={result}, code={exit_code}). Review the log above.")

    # ── Always run as administrator ───────────────────────────────────────────
    def _set_always_admin(self):
        if self._install_running:
            return

        if not getattr(sys, "frozen", False):
            messagebox.showinfo(
                "Built .exe only",
                "This configures the built NOVIVO .exe.\n\n"
                "Running from source, the only thing to point it at is the Python "
                "interpreter — and forcing that to elevate would affect every "
                "unrelated script on this machine.\n\n"
                "Build the .exe first, then run this from the .exe.")
            return

        target = sys.executable
        if not messagebox.askyesno(
                "Always run as Administrator",
                f"For:\n{target}\n\nthis will:\n\n"
                "•  set a machine-wide RUNASADMIN flag, so every user's launch elevates\n"
                "•  register an elevated Scheduled Task\n"
                "•  put a shortcut on your Desktop that opens the tool with NO UAC prompt\n\n"
                "Both routes store an absolute path — re-run this if you move the .exe.\n\n"
                "Continue?"):
            return

        self._begin_busy(self._btn_always_admin, "⏳  CONFIGURING…",
                         "Configuring admin launch…")
        self._clear_log()
        self._run_ps(ALWAYS_ADMIN, ["-TargetPath", target], self._admin_done)

    def _admin_done(self, exit_code: int):
        self._end_busy()
        if exit_code == 0:
            self._set_status("Always-run-as-admin configured")
        else:
            self._set_status(f"Admin setup finished with errors (code {exit_code})")
            self._log_write(f"\n[WARNING] Process exited with code {exit_code}")


# ══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    app = NovivoCTkApp()
    app.mainloop()
