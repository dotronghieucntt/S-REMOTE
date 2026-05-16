"""
Generate PyInstaller version_file from version.txt.
Run: python version_info.py  →  writes build_tmp/version_info.txt
"""
import os, re

HERE     = os.path.dirname(os.path.abspath(__file__))
VER_FILE = os.path.join(HERE, "version.txt")
OUT_DIR  = os.path.join(HERE, "build_tmp")
OUT_FILE = os.path.join(OUT_DIR, "version_info.txt")

ver_str  = open(VER_FILE).read().strip()
parts    = [int(x) for x in ver_str.split(".")]
while len(parts) < 4:
    parts.append(0)
v        = tuple(parts)

os.makedirs(OUT_DIR, exist_ok=True)

content = f"""# UTF-8
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=({v[0]}, {v[1]}, {v[2]}, {v[3]}),
    prodvers=({v[0]}, {v[1]}, {v[2]}, {v[3]}),
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo([
      StringTable(
        u'040904B0',
        [StringStruct(u'CompanyName',      u'NOVIVO'),
         StringStruct(u'FileDescription',  u'NOVIVO Remote Desktop Setup Tool'),
         StringStruct(u'FileVersion',      u'{ver_str}'),
         StringStruct(u'InternalName',     u'NOVIVO-RemoteDesktop'),
         StringStruct(u'LegalCopyright',   u'\\xa9 2026 NOVIVO. All rights reserved.'),
         StringStruct(u'OriginalFilename', u'NOVIVO Remote Desktop v{ver_str}.exe'),
         StringStruct(u'ProductName',      u'NOVIVO Remote Desktop'),
         StringStruct(u'ProductVersion',   u'{ver_str}')])
    ]),
    VarFileInfo([VarStruct(u'Translation', [0x0409, 1200])])
  ]
)
"""

with open(OUT_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print(f"Written: {OUT_FILE}  (v{ver_str})")
