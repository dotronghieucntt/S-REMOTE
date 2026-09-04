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
import string
import tkinter as tk

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

    def __init__(self, master, vpn_method_var: tk.StringVar, **kw):
        super().__init__(master, bg=C["panel"], **kw)
        self._rows: list[dict] = []
        self._active_idx = tk.IntVar(value=0)
        self._vpn_var = vpn_method_var
        self._build_header()
        # Rows grow the frame; the surrounding ScrollFrame scrolls if needed.
        self._inner = tk.Frame(self, bg=C["panel"])
        self._inner.pack(fill="x")

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
            if not k_entry.get().strip():
                k_entry.delete(0, "end"); k_entry.insert(0, self._ph_key())
                k_entry.config(fg=self._PH_FG); k_is_ph[0] = True

        n_entry.bind("<FocusOut>", n_fo)
        k_entry.bind("<FocusIn>",  k_fi); k_entry.bind("<FocusOut>", k_fo)

        self._rows.append({"idx": idx, "frame": row, "radio": rb,
                           "ne": n_entry, "ke": k_entry,
                           "n_is_ph": n_is_ph, "k_is_ph": k_is_ph})

    def remove_active(self):
        if len(self._rows) <= 1:
            return
        idx = self._active_idx.get()
        if idx >= len(self._rows):
            idx = 0
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
        return "" if r["k_is_ph"][0] else r["ke"].get().strip()

    def get_all(self) -> list[dict]:
        active = self._active_idx.get()
        return [{"name":   r["ne"].get().strip() or self._auto_name(i),
                 "key":    "" if r["k_is_ph"][0] else r["ke"].get().strip(),
                 "active": i == active}
                for i, r in enumerate(self._rows)]

    def load_all(self, servers: list[dict]):
        # servers.json is user-editable - keep only well-formed rows
        servers = [s for s in servers if isinstance(s, dict)] if isinstance(servers, list) else []
        for r in self._rows:
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
            if r["k_is_ph"][0]:
                r["ke"].delete(0, "end")
                r["ke"].insert(0, ph)


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
            "[INFO] 2. Creates or updates the Windows accounts listed on the left",
            "[INFO]    and adds every one of them to the Administrators group",
            "[INFO] 3. Enables Remote Desktop, opens the firewall on the RDP port",
            "[INFO] 4. Disables Network Level Authentication (NLA)",
            "[INFO] 5. Blocks sleep, and turns hibernate off permanently",
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

        self._server_list = ServerList(left, self._vpn_method)
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
            left, text="ℹ  Tailscale: paste tskey-auth-… key for each server",
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
                text="ℹ  Tailscale: paste tskey-auth-… key for each server",
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
                "Hibernate is turned off permanently.\n"
                "If the RDP listener will not start, this\n"
                "machine restarts itself 30s after setup.\n\n"
                "Continue?" % (
                    os.environ.get("COMPUTERNAME", "this machine"),
                    method, rdp_port,
                    ", ".join(u["Username"] for u in users)),
                icon="warning", default=messagebox.CANCEL):
            return

        self._install_running = True
        self._btn_start.configure(state="disabled", text="⏳  RUNNING…")
        self._progress.pack(side="left", padx=14, pady=18)
        self._progress.start()
        self._set_status("Installing…")
        self._clear_log()

        users_json = json.dumps(users)

        def run():
            ps_cmd = [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", BACKEND,
                "-Method", method,
                "-NetworkKey", net_key,
                "-UsersJson", users_json,
                "-RdpPort", rdp_port
            ]
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
                    line = line.rstrip()
                    self._ui(self._log_write, line)

                proc.wait()
                exit_code = proc.returncode
                self._ui(self._install_done, exit_code)
            except Exception as exc:
                self._ui(self._log_write, f"[ERROR] Failed to run backend: {exc}")
                self._ui(self._install_done, -1)

        threading.Thread(target=run, daemon=True).start()

    def _install_done(self, exit_code: int):
        self._install_running = False
        self._btn_start.configure(state="normal", text="▶  START SETUP")
        self._progress.stop()
        self._progress.pack_forget()
        if exit_code == 0:
            self._set_status("Setup completed successfully!")
            self._log_write("\n[OK] All done. Exit code: 0")
        else:
            self._set_status(f"Setup finished with errors (code {exit_code})")
            self._log_write(f"\n[WARNING] Process exited with code {exit_code}")


# ══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    app = NovivoCTkApp()
    app.mainloop()
