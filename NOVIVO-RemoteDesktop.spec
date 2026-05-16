# -*- mode: python ; coding: utf-8 -*-
# ──────────────────────────────────────────────────────────────────────────────
#  NOVIVO Remote Desktop — PyInstaller Spec
#  Produces TWO outputs in a single run:
#    • NOVIVO Remote Desktop vX.Y.Z.exe  (onefile, for distribution)
#    • NOVIVO Remote Desktop vX.Y.Z/     (onedir,  full portable folder)
#
#  Always build via  Build-Release.ps1  — never invoke pyinstaller directly.
# ──────────────────────────────────────────────────────────────────────────────
import os
import sys
import shutil
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

# ─── Paths ───────────────────────────────────────────────────────────────────
HERE     = os.path.abspath(SPECPATH)   # noqa: F821 — SPECPATH injected by PyInstaller
VER_FILE = os.path.join(HERE, "version.txt")
VER      = open(VER_FILE).read().strip() if os.path.exists(VER_FILE) else "1.0.0"
APP_NAME = f"NOVIVO Remote Desktop v{VER}"

ICON_ICO  = os.path.join(HERE, "icon.ico")
BACKEND   = os.path.join(HERE, "NOVIVO-Backend.ps1")
LOGO_PNG  = os.path.join(HERE, "LOGO KO CHU.png")
LOGO_FULL = os.path.join(HERE, "NEN DEN.png")
VER_INFO  = os.path.join(HERE, "build_tmp", "version_info.txt")

# ─── Data files ──────────────────────────────────────────────────────────────
# CustomTkinter: theme JSON + image assets are required at runtime
_ctk_datas = collect_data_files("customtkinter", include_py_files=False)

added_datas = (
    _ctk_datas
    + [(BACKEND,   ".")]          # PowerShell backend → root of bundle
    + [(LOGO_PNG,  ".")]          # logo (no text) → for splash / about
    + [(LOGO_FULL, ".")]          # logo (full)    → for header image
)

# ─── Hidden imports ───────────────────────────────────────────────────────────
# Modules that PyInstaller's static analyser misses
hidden_imports = [
    # CustomTkinter internals
    "customtkinter",
    "customtkinter.windows",
    "customtkinter.windows.widgets",
    "customtkinter.windows.widgets.core_rendering",
    "customtkinter.windows.widgets.theme",
    "customtkinter.windows.ctk_tk",
    "customtkinter.windows.ctk_toplevel",
    # Pillow
    "PIL",
    "PIL._tkinter_finder",
    "PIL.Image",
    "PIL.ImageTk",
    "PIL.PngImagePlugin",
    "PIL.IcoImagePlugin",
    # tkinter
    "tkinter",
    "tkinter.messagebox",
    "tkinter.filedialog",
    "tkinter.ttk",
    "_tkinter",
    # stdlib used at runtime
    "ctypes",
    "ctypes.wintypes",
    "json",
    "threading",
    "subprocess",
    "random",
    "string",
    "os",
    "sys",
    "pathlib",
]
hidden_imports += collect_submodules("customtkinter")
hidden_imports += collect_submodules("PIL")

# ─── Excludes (trim size) ────────────────────────────────────────────────────
excludes = [
    "matplotlib", "numpy", "scipy", "pandas",
    "PyQt5", "PyQt6", "wx",
    "IPython", "notebook",
    "email", "html", "xml", "xmlrpc",
    "unittest", "test", "pydoc",
    "lib2to3",
]

# ─── Admin-elevation manifest ─────────────────────────────────────────────────
# UAC: request admin rights on launch
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

_manifest_path = os.path.join(HERE, "build_tmp", "uac_admin.manifest")
os.makedirs(os.path.join(HERE, "build_tmp"), exist_ok=True)
with open(_manifest_path, "w", encoding="utf-8") as _mf:
    _mf.write(MANIFEST)

# ═════════════════════════════════════════════════════════════════════════════
#  ANALYSIS  (shared between both build targets)
# ═════════════════════════════════════════════════════════════════════════════
a = Analysis(
    [os.path.join(HERE, "NOVIVO-App.py")],
    pathex=[HERE],
    binaries=[],
    datas=added_datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure)   # noqa: F821

# ═════════════════════════════════════════════════════════════════════════════
#  TARGET 1 — ONEFILE  (single portable .exe — recommended for sharing)
# ═════════════════════════════════════════════════════════════════════════════
exe_onefile = EXE(          # noqa: F821
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=["vcruntime140.dll", "python3*.dll", "_tkinter.pyd"],
    console=False,           # no console window (GUI app)
    windowed=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=ICON_ICO,
    version=VER_INFO if os.path.exists(VER_INFO) else None,
    uac_admin=True,
    manifest=_manifest_path,
    exclude_binaries=False,  # ← onefile: embed everything
)

# ═════════════════════════════════════════════════════════════════════════════
#  TARGET 2 — ONEDIR  (full folder — faster startup, easier to debug)
# ═════════════════════════════════════════════════════════════════════════════
exe_onedir = EXE(           # noqa: F821
    pyz,
    a.scripts,
    [],
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=["vcruntime140.dll", "python3*.dll", "_tkinter.pyd"],
    console=False,
    windowed=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=ICON_ICO,
    version=VER_INFO if os.path.exists(VER_INFO) else None,
    uac_admin=True,
    manifest=_manifest_path,
    exclude_binaries=True,   # ← onedir: binaries go into COLLECT
)

coll = COLLECT(             # noqa: F821
    exe_onedir,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=["vcruntime140.dll", "python3*.dll", "_tkinter.pyd"],
    name=APP_NAME + " (Full)",
)
