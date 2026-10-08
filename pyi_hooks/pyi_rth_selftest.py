# ──────────────────────────────────────────────────────────────────────────────
#  Runtime hook — chạy TRƯỚC NOVIVO-App.py bên trong exe (spec gắn vào).
#
#  Bình thường không làm gì. Chỉ khi exe được gọi:
#      "NOVIVO Remote Desktop vX.Y.Z.exe" --selftest <file-kết-quả.json>
#  thì kiểm chính bản build đó rồi THOÁT, app không chạy, không đòi admin:
#    • import đủ mọi module app dùng (danh sách spec ghi vào _selftest.json),
#      kể cả phần kéo theo gián tiếp: urllib.request -> email (v1.0.18 chết vì thiếu)
#    • đủ file đi kèm (backend .ps1, logo, icon, version.txt)
#    • Tcl/Tk khởi tạo được, SSL tạo được context (gọi https lấy key dùng chung)
#
#  Build-Release.ps1 chạy bước này ngay sau PyInstaller; lỗi thì build dừng và bản
#  hỏng không tới được trang tải về. Kết quả: {"ok": bool, "errors": [...], ...}
# ──────────────────────────────────────────────────────────────────────────────
import sys

if "--selftest" in sys.argv:
    import importlib
    import json
    import os
    import traceback

    _i = sys.argv.index("--selftest")
    _out = sys.argv[_i + 1] if len(sys.argv) > _i + 1 else None
    _res = {"ok": False, "errors": [], "checked": {}}

    try:
        _base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
        with open(os.path.join(_base, "_selftest.json"), encoding="utf-8") as _f:
            _man = json.load(_f)
        _res["version"] = _man.get("version")

        for _m in _man.get("imports", []):
            try:
                importlib.import_module(_m)
            except Exception as _e:
                _res["errors"].append(f"import {_m}: {type(_e).__name__}: {_e}")
        _res["checked"]["imports"] = len(_man.get("imports", []))

        for _name in _man.get("files", []):
            if not os.path.exists(os.path.join(_base, _name)):
                _res["errors"].append(f"thiếu file đi kèm: {_name}")
        _res["checked"]["files"] = len(_man.get("files", []))

        # Runtime hook tự viết chạy TRƯỚC pyi_rth__tkinter của PyInstaller (hook đó
        # đặt TCL_LIBRARY/TK_LIBRARY), nên tự dò init.tcl / tk.tcl trong bundle như nó.
        # Bundle thiếu thư viện Tcl/Tk thật thì vẫn không dò ra và Tk() vẫn báo lỗi.
        import glob
        for _var, _marker in (("TCL_LIBRARY", "init.tcl"), ("TK_LIBRARY", "tk.tcl")):
            if not os.environ.get(_var):
                _hits = sorted(glob.glob(os.path.join(_base, "**", _marker), recursive=True), key=len)
                if _hits:
                    os.environ[_var] = os.path.dirname(_hits[0])

        try:
            import tkinter
            _root = tkinter.Tk()
            _root.withdraw()
            _root.update_idletasks()
            _res["checked"]["tk"] = _root.tk.call("info", "patchlevel")
            _root.destroy()
        except Exception as _e:
            _res["errors"].append(f"Tcl/Tk: {type(_e).__name__}: {_e}")

        try:
            import ssl
            ssl.create_default_context()
            _res["checked"]["ssl"] = ssl.OPENSSL_VERSION
        except Exception as _e:
            _res["errors"].append(f"ssl: {type(_e).__name__}: {_e}")

        # certifi: app nạp thêm bộ CA này cho máy Windows mới thiếu root
        _cafile = None
        if "certifi" in _man.get("imports", []):
            try:
                import certifi
                _cafile = certifi.where()
                if not os.path.exists(_cafile):
                    _res["errors"].append(f"certifi: thiếu {_cafile}")
                    _cafile = None
            except Exception as _e:
                _res["errors"].append(f"certifi: {type(_e).__name__}: {_e}")

        # Gọi HTTPS thật CHỈ bằng CA của certifi = giả lập máy chưa có root nào.
        # Lỗi chứng chỉ là lỗi build; mất mạng thì chỉ ghi chú (không chặn build).
        _url = _man.get("net_check")
        if _url and _cafile:
            import urllib.error
            import urllib.request
            try:
                _ctx = ssl.create_default_context(cafile=_cafile)
                with urllib.request.urlopen(_url, timeout=15, context=_ctx) as _r:
                    _res["checked"]["net"] = f"{_url} -> HTTP {_r.status} (chỉ CA certifi)"
            except urllib.error.HTTPError as _e:
                _res["checked"]["net"] = f"{_url} -> HTTP {_e.code} (TLS ok)"
            except urllib.error.URLError as _e:
                if isinstance(_e.reason, ssl.SSLCertVerificationError):
                    _res["errors"].append(f"TLS {_url}: {_e.reason}")
                else:
                    _res["checked"]["net"] = f"bỏ qua (mạng): {_e.reason}"
            except Exception as _e:
                _res["checked"]["net"] = f"bỏ qua: {type(_e).__name__}: {_e}"
    except Exception:
        _res["errors"].append(traceback.format_exc())

    _res["ok"] = not _res["errors"]
    if _out:
        try:
            with open(_out, "w", encoding="utf-8") as _f:
                json.dump(_res, _f, ensure_ascii=False, indent=2)
        except OSError:
            pass
    os._exit(0 if _res["ok"] else 1)
