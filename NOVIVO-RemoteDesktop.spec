# -*- mode: python ; coding: utf-8 -*-
# ──────────────────────────────────────────────────────────────────────────────
#  NOVIVO Remote Desktop — PyInstaller spec (TỰ ĐỘNG HOÀN TOÀN)
#
#  Đừng gọi pyinstaller trực tiếp. Build bằng:   .\Build-Release.ps1 -SkipGitHub
#  Hướng dẫn đầy đủ + lỗi từng gặp:              BUILD.md
#
#  Một lần chạy ra HAI bản, cùng một Analysis:
#    dist/NOVIVO Remote Desktop vX.Y.Z.exe          onefile — bản phát hành chính
#    dist/NOVIVO Remote Desktop vX.Y.Z (Full)/      onedir  — gói vào .zip "Bản Full"
#
#  Spec tự lo hết, KHÔNG cần khai tay khi thêm code vào NOVIVO-App.py:
#    1. Import       đọc AST của app: mọi `import`/`from … import`, kể cả import nằm
#                    trong hàm → hiddenimports. PyInstaller tự kéo phần gián tiếp.
#    2. Thư viện ngoài   import nào không thuộc thư viện chuẩn → collect_all (code +
#                    data + dll), rồi lần theo requirements trong metadata để gom
#                    luôn thư viện mà nó phụ thuộc (customtkinter → darkdetect, packaging).
#    3. File đi kèm  quét chuỗi os.path.join(_BUNDLE, "…") và _asset("…") trong app →
#                    bundle vào gốc. Thiếu file thì DỪNG build, không ra exe hỏng.
#    4. Icon + version   tự tạo icon.ico đủ cỡ 16→256 từ logo, tự tạo version resource
#                    (Properties → Details của exe) từ version.txt.
#    5. Self-test    ghi _selftest.json + gắn runtime hook pyi_hooks/pyi_rth_selftest.py;
#                    Build-Release.ps1 chạy exe thật với --selftest để kiểm sau build.
#    6. Rào chắn     cấm loại (exclude) module thư viện chuẩn — v1.0.18 chết vì
#                    exclude "email" mà urllib.request cần.
# ──────────────────────────────────────────────────────────────────────────────
import ast
import importlib.metadata as md
import importlib.util
import json
import os
import re
import runpy
import sys

from packaging.requirements import Requirement
from PyInstaller.utils.hooks import collect_all

HERE = os.path.abspath(SPECPATH)            # noqa: F821 — PyInstaller cấp SPECPATH
WORK = os.path.join(HERE, "build_tmp")      # file sinh ra lúc build (git bỏ qua)
os.makedirs(WORK, exist_ok=True)


def log(msg):
    print(f"[spec] {msg}", flush=True)


def fail(msg):
    raise SystemExit(f"\n[spec] DỪNG BUILD: {msg}\n")


# ══════════════════════════════════════════════════════════════════════════════
#  0. CẤU HÌNH — khối DUY NHẤT có thể phải sửa tay (thường là không)
# ══════════════════════════════════════════════════════════════════════════════
ENTRY      = os.path.join(HERE, "NOVIVO-App.py")
APP_TITLE  = "NOVIVO Remote Desktop"
LOGO_PNG   = os.path.join(HERE, "LOGO KO CHU.png")       # nguồn để tạo icon.ico
SELFTEST_HOOK = os.path.join(HERE, "pyi_hooks", "pyi_rth_selftest.py")

# Module nạp động (importlib.import_module("…"), __import__) mà AST không thấy được
EXTRA_HIDDEN = []

# File cần bundle mà app không gọi qua _BUNDLE/_asset: [(đường dẫn nguồn, thư mục đích)]
EXTRA_DATAS = []

# Chỉ loại thư viện NGOÀI to và không dùng tới. Cấm ghi module thư viện chuẩn vào đây.
EXCLUDES = [
    "matplotlib", "numpy", "scipy", "pandas",
    "PyQt5", "PyQt6", "PySide2", "PySide6", "wx",
    "IPython", "notebook", "jupyter_client", "jupyter_core",
]

UPX_EXCLUDE = ["vcruntime140.dll", "python3*.dll", "_tkinter.pyd", "tcl*.dll", "tk*.dll"]

ICON_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

# Self-test gọi thử HTTPS tới đây chỉ bằng CA của certifi (giả lập máy mới cài,
# thiếu root). Máy chủ mở khoá key nằm ở đây. None = bỏ bước này.
SELFTEST_NET_CHECK = "https://remote.novivo.net/health"


# ══════════════════════════════════════════════════════════════════════════════
#  Phiên bản
# ══════════════════════════════════════════════════════════════════════════════
VER_FILE = os.path.join(HERE, "version.txt")
if not os.path.exists(VER_FILE):
    fail("thiếu version.txt")
VER = open(VER_FILE, encoding="utf-8").read().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", VER):
    fail(f"version.txt phải dạng X.Y.Z, đang là {VER!r}")
APP_NAME = f"{APP_TITLE} v{VER}"


# ══════════════════════════════════════════════════════════════════════════════
#  1. IMPORT — quét AST của app
# ══════════════════════════════════════════════════════════════════════════════
STDLIB = set(sys.stdlib_module_names) | set(sys.builtin_module_names)


def _findable(name):
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError, AttributeError):
        return False


def scan_imports(path):
    """(bắt buộc, có thể) — `import a.b` / `from a import …` là bắt buộc;
    `from a import b` thì a.b CÓ THỂ là module con (tkinter.ttk) hoặc chỉ là tên."""
    tree = ast.parse(open(path, encoding="utf-8").read(), path)
    required, maybe = set(), set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            required.update(a.name for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            required.add(node.module)
            maybe.update(f"{node.module}.{a.name}" for a in node.names if a.name != "*")
    return required, maybe


_required, _maybe = scan_imports(ENTRY)
_missing = sorted(m for m in _required if not _findable(m))
if _missing:
    fail("app import module không cài trong Python đang build: " + ", ".join(_missing)
         + f"\n        Python: {sys.executable}  →  pip install …")
APP_IMPORTS = sorted(_required | {m for m in _maybe if _findable(m)} | set(EXTRA_HIDDEN))
TOP_LEVELS = sorted({m.split(".")[0] for m in APP_IMPORTS})


# ══════════════════════════════════════════════════════════════════════════════
#  6. RÀO CHẮN exclude (kiểm sớm, trước khi tốn thời gian Analysis)
# ══════════════════════════════════════════════════════════════════════════════
_bad = [e for e in EXCLUDES if e.split(".")[0] in STDLIB]
if _bad:
    fail("EXCLUDES có module thư viện chuẩn: " + ", ".join(_bad)
         + "\n        Thư viện chuẩn hay bị kéo gián tiếp (urllib.request → email). Xoá khỏi EXCLUDES.")


# ══════════════════════════════════════════════════════════════════════════════
#  2. THƯ VIỆN NGOÀI — collect_all + lần theo dependency trong metadata
# ══════════════════════════════════════════════════════════════════════════════
def _norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


_pkg_dists = md.packages_distributions()              # {"PIL": ["pillow"], …}
_dist_tops = {}
for _top, _dists in _pkg_dists.items():
    for _d in _dists:
        _dist_tops.setdefault(_norm(_d), set()).add(_top)


def _requires(dist):
    try:
        reqs = md.requires(dist) or []
    except md.PackageNotFoundError:
        return []
    out = []
    for r in reqs:
        req = Requirement(r)
        if req.marker and not req.marker.evaluate({"extra": ""}):
            continue                                   # chỉ dành cho extra/phiên bản Python khác
        out.append(_norm(req.name))
    return out


THIRD_PARTY = [t for t in TOP_LEVELS if t not in STDLIB]
_todo = [_norm(d) for t in THIRD_PARTY for d in _pkg_dists.get(t, [])]
_seen_dists = set()
while _todo:
    _d = _todo.pop()
    if _d not in _seen_dists:
        _seen_dists.add(_d)
        _todo.extend(_requires(_d))

COLLECT_TOPS = sorted(
    (set(THIRD_PARTY) | {t for d in _seen_dists for t in _dist_tops.get(d, ())})
    - {e.split(".")[0] for e in EXCLUDES}
)
_clash = [t for t in THIRD_PARTY if t in {e.split(".")[0] for e in EXCLUDES}]
if _clash:
    fail("app import thư viện đang nằm trong EXCLUDES: " + ", ".join(_clash))

datas, binaries, hiddenimports = [], [], list(APP_IMPORTS)
for _top in COLLECT_TOPS:
    try:
        _d, _b, _h = collect_all(_top)
    except Exception as _e:                           # module đơn (không phải package)
        log(f"collect_all({_top}) bỏ qua: {_e}")
        hiddenimports.append(_top)
        continue
    datas += _d
    binaries += _b
    hiddenimports += _h
hiddenimports = sorted(set(hiddenimports))


# ══════════════════════════════════════════════════════════════════════════════
#  4. ICON + VERSION RESOURCE (sinh vào build_tmp/, không đụng file trong git)
# ══════════════════════════════════════════════════════════════════════════════
ICON_ICO = os.path.join(WORK, "icon.ico")
try:
    from PIL import Image
    Image.open(LOGO_PNG).convert("RGBA").save(ICON_ICO, format="ICO", sizes=ICON_SIZES)
except Exception as _e:
    fail(f"không tạo được icon.ico từ {LOGO_PNG}: {_e}")
with Image.open(ICON_ICO) as _ic:
    _got = sorted(_ic.info.get("sizes", ()))
if (256, 256) not in _got:
    fail(f"icon.ico thiếu cỡ 256 (chỉ có {_got}) — logo phải ≥ 256px")

runpy.run_path(os.path.join(HERE, "version_info.py"))   # ghi build_tmp/version_info.txt
VER_INFO = os.path.join(WORK, "version_info.txt")
if not os.path.exists(VER_INFO):
    fail("version_info.py không tạo được build_tmp/version_info.txt")


# ══════════════════════════════════════════════════════════════════════════════
#  3. FILE ĐI KÈM — quét chuỗi _BUNDLE/_asset trong app
# ══════════════════════════════════════════════════════════════════════════════
_RES_RE = re.compile(r'(?:os\.path\.join\(\s*_BUNDLE\s*,\s*|_asset\(\s*)["\']([^"\']+)["\']')
_GENERATED = {"icon.ico": ICON_ICO}                     # tên trong bundle → file sinh ra
RESOURCES = sorted(set(_RES_RE.findall(open(ENTRY, encoding="utf-8").read())))

bundle_files = []
for _name in RESOURCES:
    _src = _GENERATED.get(_name, os.path.join(HERE, _name))
    if not os.path.exists(_src):
        fail(f"app cần file đi kèm '{_name}' nhưng không thấy {_src}")
    datas.append((_src, "."))
    bundle_files.append(_name)
for _src, _dst in EXTRA_DATAS:
    if not os.path.exists(_src):
        fail(f"EXTRA_DATAS: không thấy {_src}")
    datas.append((_src, _dst))
    bundle_files.append(os.path.join(_dst, os.path.basename(_src)).lstrip(".\\/"))


# ══════════════════════════════════════════════════════════════════════════════
#  5. SELF-TEST manifest (runtime hook đọc file này khi exe chạy với --selftest)
# ══════════════════════════════════════════════════════════════════════════════
if not os.path.exists(SELFTEST_HOOK):
    fail(f"thiếu runtime hook {SELFTEST_HOOK}")
SELFTEST_JSON = os.path.join(WORK, "_selftest.json")
with open(SELFTEST_JSON, "w", encoding="utf-8") as _f:
    json.dump({"version": VER,
               "imports": sorted(set(APP_IMPORTS) | set(COLLECT_TOPS)),
               "files": bundle_files,
               "net_check": SELFTEST_NET_CHECK}, _f, ensure_ascii=False, indent=2)
datas.append((SELFTEST_JSON, "."))


# ══════════════════════════════════════════════════════════════════════════════
#  UAC manifest — exe luôn xin quyền admin
# ══════════════════════════════════════════════════════════════════════════════
MANIFEST = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
    </windowsSettings>
  </application>
</assembly>"""
MANIFEST_FILE = os.path.join(WORK, "uac_admin.manifest")
with open(MANIFEST_FILE, "w", encoding="utf-8") as _mf:
    _mf.write(MANIFEST)


log(f"phiên bản      : {VER}")
log(f"import của app : {len(APP_IMPORTS)}  ({', '.join(TOP_LEVELS)})")
log(f"thư viện ngoài : {', '.join(COLLECT_TOPS) or '—'}")
log(f"file đi kèm    : {', '.join(bundle_files)}")
log(f"loại trừ       : {', '.join(EXCLUDES)}")


# ══════════════════════════════════════════════════════════════════════════════
#  ANALYSIS (dùng chung cho cả hai bản)
# ══════════════════════════════════════════════════════════════════════════════
a = Analysis(                       # noqa: F821
    [ENTRY],
    pathex=[HERE],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[SELFTEST_HOOK],
    excludes=EXCLUDES,
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure)                   # noqa: F821

_exe_common = dict(
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=UPX_EXCLUDE,
    console=False,                  # app GUI, không cửa sổ console
    disable_windowed_traceback=False,   # lỗi lúc chạy vẫn hiện hộp traceback cho người dùng
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=ICON_ICO,
    version=VER_INFO,
    uac_admin=True,
    manifest=MANIFEST_FILE,
)

# ── Bản 1: ONEFILE — một file .exe duy nhất (bản phát hành chính) ─────────────
exe_onefile = EXE(                  # noqa: F821
    pyz, a.scripts, a.binaries, a.datas, [],
    exclude_binaries=False,
    **_exe_common,
)

# ── Bản 2: ONEDIR — thư mục đầy đủ, khởi động nhanh, ít bị diệt virus báo nhầm ─
exe_onedir = EXE(                   # noqa: F821
    pyz, a.scripts, [],
    exclude_binaries=True,
    **_exe_common,
)
coll = COLLECT(                     # noqa: F821
    exe_onedir, a.binaries, a.datas,
    strip=False,
    upx=True,
    upx_exclude=UPX_EXCLUDE,
    name=APP_NAME + " (Full)",
)
