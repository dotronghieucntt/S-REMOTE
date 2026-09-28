# NOVIVO install — scenario matrix & install-reliability notes

A dependency-free test harness that runs the **real** installer functions from
`NOVIVO-Backend.ps1` against **simulated machines**, so "install completes but
RDP doesn't work" gets caught here instead of on a customer's PC.

No Pester, no internet, no admin, nothing to install.

```powershell
powershell -ExecutionPolicy Bypass -File Tests\Run-Scenarios.ps1
```

Exit code `0` = all scenarios passed; non-zero = number of failing scenarios.

## How it works

- `NovivoTest.Engine.ps1` loads the target functions out of `NOVIVO-Backend.ps1`
  via the PowerShell **AST** (so the top-level install block never executes),
  then builds a dynamic module that **shadows** the Windows cmdlets those
  functions call (`Get-CimInstance`, `Get-NetTCPConnection`, `Get-ItemProperty`,
  `Get-Process`, …) with fakes driven by a per-scenario hashtable.
- `Install-Scenarios.Tests.ps1` is the matrix: each row is a simulated machine +
  the decision the installer must reach on it.

Add a scenario by appending a row to the relevant group; add a new function to
the matrix by adding it to the `New-NovivoSandbox -Functions @(...)` list.

## The matrix (29 scenarios)

| Group        | What it pins down |
|--------------|-------------------|
| ResultState  | The outcome the GUI is told: listener down ⇒ `NEEDS_RESTART`, listener up but no overlay IP ⇒ `NEEDS_AUTH`, listener up + IP ⇒ `SUCCESS`. |
| OSSupport    | Preflight gate across S mode, Win7/8.1/10<1809/10/11/Server, Tailscale vs ZeroTier. |
| OSInfo       | Edition/build/S-mode detection from SKU, caption fallback, ProductType, registry. |
| Listener     | `Test-RdpListener` is **ownership-aware**: a port squatted by a non-TermService process is NOT "listening". |
| RdpWrap      | "installed" ≠ "working": wrapper loaded vs. listener actually up. |
| Tailscale    | Login detection: a `100.x` tailnet IP means logged in; "Logged out", "stopped", "needs browser login", or a backend that isn't answering yet all mean NOT logged in. |

## Root cause fixed: "cài xong báo thành công nhưng RDP chết"

The dominant reason a finished install still needed manual fixup: **the backend
never set a non-zero exit code, and the GUI judged success purely by exit code**,
so every failure mode (expired Tailscale key, unauthorised ZeroTier node, Windows
Home without a working RDP host, a port already in use, an edition needing a
reboot) still displayed *"Setup completed successfully!"*.

Fix (both sides now agree on a contract):

- **`NOVIVO-Backend.ps1`** computes the outcome from the **authoritative,
  ownership-aware** listener check (it already did this), then in its `finally`
  prints one machine-readable line `**[NOVIVO-RESULT] <STATE>**` and **exits with
  a matching code** — `0` SUCCESS, `3` NEEDS_RESTART, `4` NEEDS_AUTH, `1` FAILED
  (and `2` NOT_SUPPORTED from preflight). The shared helper `Get-NovivoResultState`
  keeps both network branches from drifting. Silence ⇒ `FAILED`, never success.
- **`NOVIVO-App.py`** reads that line as the primary signal (exit code is a
  fallback for older backends) and shows an honest status + next action instead
  of a blanket "success".

The `ResultState` group locks this decision logic in place.

## Also fixed: "cài xong không tự đăng nhập Tailscale"

`tailscale up` used to fire once, ~4 s after starting the service, with no check
that it worked. Right after a fresh install the local `tailscaled` isn't ready
yet, so that single `up` silently does nothing and the node is left **logged
out** — even though the auth key was valid. TS-STEP 3 now:

1. **waits** until `tailscaled` answers (`Test-TailscaleBackendReady`) instead of
   a fixed sleep, nudging the service while it waits;
2. runs `tailscale up --unattended --authkey …` with a **retry loop**;
3. **verifies the real login state** (`Test-TailscaleLoggedIn` — a `100.x` IP and
   not "Logged out"/"stopped"/needs-login), never the `up` exit code alone;
4. stops early with a clear message if the key was rejected (a normal key is
   single-use — a second machine needs a **reusable** key).

If it still can't log in, the run reports `NEEDS_AUTH`, not success. The
`Tailscale` group covers this detection.

## Recommended, not yet applied (need real-hardware validation)

These came out of the audit and are worth doing, but they touch live-system
behaviour the harness can't fully simulate, so they were left for a hardware
test pass rather than changed blind:

1. **Home RDP fallback is version-pinned.** RDPWrap is pinned to `v1.6.2` (2018)
   and the termsrv patch uses a single byte signature. On a newer Win10/11 Home
   build where both miss, Home cannot host RDP at all (and the patch refuses on
   32-bit). Consider a per-build signature table + verifying the `rdpwrap.ini`
   actually contains a section for the running build before trusting it.
2. **Boot auto-repair is trigger-happy.** The generated `Repair-NovivoRdp.ps1`
   waits a single 30 s then does a one-shot listener check; poll (e.g. 6×10 s)
   before running the destructive repair, and have it re-apply
   `Enable-NovivoMultiSession` after a successful patch.
3. **termsrv rollback after TrustedInstaller re-own.** Re-`takeown`/`icacls`
   immediately before the rollback copy and verify size/hash, so a failed patch
   can never leave a half-restored `termsrv.dll`.
4. **Consolidate the three patch implementations.** `Patch-TermSrv.ps1` diverges
   from the two in-sync copies of `Invoke-TermSrvPatch`; fold them into one.
5. **`NOVIVO-Remote-Desktop.ps1` is a legacy monolith** the shipping app does not
   run (`NOVIVO-App.py` runs `NOVIVO-Backend.ps1`). Its `SecurityLayer=0` /
   force-kill-svchost / post-`Install-HomeRdpSupport` clobber issues do not affect
   the product, but the file should be retired or kept in sync to avoid confusion.

## Known environment issue (unrelated to this work)

`.venv\Scripts\python.exe` is a `uv` shim pointing at a path for user `HIEU`
(`C:\Users\HIEU\...`) that does not exist on this machine, so the venv can't run
here and `NOVIVO-App.py` couldn't be byte-compiled locally. Recreate the venv on
this machine before building.
