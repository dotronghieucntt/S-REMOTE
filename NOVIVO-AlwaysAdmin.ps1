# NOVIVO-AlwaysAdmin.ps1 - make the NOVIVO tool always start with admin rights.
#
# Two independent mechanisms, both keyed to the EXE's ABSOLUTE path:
#
#   1. HKLM ...\AppCompatFlags\Layers = "~ RUNASADMIN"
#      Forces elevation for every user on this machine, no matter how the EXE is
#      started (Explorer, a script, someone else's shortcut). UAC still prompts.
#
#   2. A no-trigger Scheduled Task (RunLevel Highest) plus a Desktop shortcut
#      that fires it through wscript.exe.
#      Task Scheduler starts its action already elevated, so this route skips the
#      UAC prompt completely. wscript - rather than calling schtasks straight from
#      the shortcut - is what keeps a console window from flashing up.
#
# Both mechanisms store an absolute path: re-run this after moving the EXE.

param(
    [Parameter(Mandatory)][string]$TargetPath,
    [string]$TaskName     = "NOVIVORemoteDesktop",
    [string]$ShortcutName = "NOVIVO Remote Desktop (Admin)"
)

$ErrorActionPreference = 'Stop'

function Write-Output-Box { param([string]$Message); Write-Host $Message; [Console]::Out.Flush() }

$failures = New-Object System.Collections.Generic.List[string]

Write-Output-Box "=== NOVIVO - ALWAYS RUN AS ADMINISTRATOR ==="
Write-Output-Box ""

# -- Preflight ---------------------------------------------------------------
try {
    $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output-Box "[ERROR] This must run elevated. Start the tool as Administrator and try again."
        exit 1
    }
} catch {
    Write-Output-Box "[ERROR] Could not determine elevation state: $($_.Exception.Message)"
    exit 1
}

try {
    $TargetPath = [IO.Path]::GetFullPath($TargetPath)
} catch {
    Write-Output-Box "[ERROR] Not a usable path: $TargetPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    Write-Output-Box "[ERROR] Target does not exist: $TargetPath"
    exit 1
}

# Guard against pointing either mechanism at a shared interpreter. Tagging
# python.exe or powershell.exe RUNASADMIN would elevate every unrelated script
# on the machine.
$leaf = [IO.Path]::GetFileName($TargetPath).ToLowerInvariant()
if (@('python.exe','pythonw.exe','powershell.exe','pwsh.exe','cmd.exe','wscript.exe','cscript.exe') -contains $leaf) {
    Write-Output-Box "[ERROR] Refusing to target the interpreter '$leaf'."
    Write-Output-Box "[INFO] Point this at the built NOVIVO .exe instead - tagging a shared"
    Write-Output-Box "[INFO] interpreter would force elevation on every script that uses it."
    exit 1
}

Write-Output-Box "[INFO] Target : $TargetPath"
Write-Output-Box "[INFO] User   : $env:USERDOMAIN\$env:USERNAME"
Write-Output-Box ""

$targetDir = [IO.Path]::GetDirectoryName($TargetPath)

# -- 1. AppCompat RUNASADMIN flag (machine-wide) -----------------------------
Write-Output-Box "[1/3] Setting the RUNASADMIN compatibility flag (all users)..."
$layersKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
try {
    if (-not (Test-Path $layersKey)) { New-Item -Path $layersKey -Force | Out-Null }
    # The value NAME is the executable path; the DATA is the space-separated
    # list of compatibility layers to apply.
    New-ItemProperty -Path $layersKey -Name $TargetPath -Value '~ RUNASADMIN' `
                     -PropertyType String -Force | Out-Null
    Write-Output-Box "[OK] HKLM Layers flag written"
} catch {
    Write-Output-Box "[ERROR] Registry flag failed: $($_.Exception.Message)"
    $failures.Add("RUNASADMIN registry flag")
}

# -- 2. Elevated Scheduled Task (the UAC-free launch route) ------------------
Write-Output-Box ""
Write-Output-Box "[2/3] Registering elevated Scheduled Task '$TaskName'..."
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute $TargetPath -WorkingDirectory $targetDir

    # Interactive + Highest: runs on this user's desktop, already elevated.
    # The task owner is the only account allowed to start it, so this does not
    # hand a standard user a way up.
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                            -LogonType Interactive -RunLevel Highest

    # No trigger at all - the shortcut is the only thing that starts it.
    # ExecutionTimeLimit 0 = never kill the GUI out from under the user.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero) `
                                             -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Principal $principal -Settings $settings `
        -Description "Start NOVIVO Remote Desktop elevated, without a UAC prompt" `
        -Force | Out-Null

    Write-Output-Box "[OK] Task registered (Interactive / RunLevel Highest / no trigger)"
} catch {
    Write-Output-Box "[ERROR] Scheduled Task failed: $($_.Exception.Message)"
    $failures.Add("Scheduled Task")
}

# -- 3. VBS launcher + Desktop shortcut --------------------------------------
Write-Output-Box ""
Write-Output-Box "[3/3] Creating the no-UAC Desktop shortcut..."
$novivoDir = Join-Path $env:ProgramData 'NOVIVO'
$vbsPath   = Join-Path $novivoDir 'launch-admin.vbs'
$lnkPath   = $null
try {
    if (-not (Test-Path $novivoDir)) { New-Item -ItemType Directory -Path $novivoDir -Force | Out-Null }

    # Window style 0 hides the schtasks console; bWaitOnReturn False returns at once.
    $vbsBody = @'
' NOVIVO Remote Desktop - elevated launcher.
' Starts the scheduled task, which Task Scheduler runs already elevated, so no
' UAC prompt appears. Window style 0 keeps the schtasks console hidden.
Dim sh
Set sh = CreateObject("WScript.Shell")
sh.Run "schtasks.exe /run /tn ""__TASKNAME__""", 0, False
'@ -replace '__TASKNAME__', $TaskName

    Set-Content -LiteralPath $vbsPath -Value $vbsBody -Encoding ASCII -Force

    # ProgramData lets any user create files; lock the launcher down so only
    # administrators can rewrite what the shortcut executes.
    try {
        $acl = Get-Acl -LiteralPath $vbsPath
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM","FullControl","Allow")))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule("BUILTIN\Users","ReadAndExecute","Allow")))
        Set-Acl -LiteralPath $vbsPath -AclObject $acl
    } catch {
        Write-Output-Box "[WARNING] Could not tighten permissions on the launcher: $($_.Exception.Message)"
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop "$ShortcutName.lnk"

    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $lnk.Arguments        = '//B //Nologo "' + $vbsPath + '"'
    $lnk.WorkingDirectory = $targetDir
    $lnk.IconLocation     = "$TargetPath,0"     # borrow the app's own icon
    $lnk.WindowStyle      = 7                   # minimised - nothing to show
    $lnk.Description      = "Start NOVIVO Remote Desktop as Administrator (no UAC prompt)"
    $lnk.Save()

    Write-Output-Box "[OK] Launcher : $vbsPath"
    Write-Output-Box "[OK] Shortcut : $lnkPath"
} catch {
    Write-Output-Box "[ERROR] Shortcut creation failed: $($_.Exception.Message)"
    $failures.Add("Desktop shortcut")
}

# -- Verify what actually landed on disk -------------------------------------
Write-Output-Box ""
Write-Output-Box "--- VERIFICATION ---"

$regVal = $null
try { $regVal = (Get-ItemProperty -Path $layersKey -Name $TargetPath -ErrorAction Stop).$TargetPath } catch { }
if ($regVal -match 'RUNASADMIN') {
    Write-Output-Box "[OK] Registry flag  : $regVal"
} else {
    Write-Output-Box "[ERROR] Registry flag  : not found"
    if (-not $failures.Contains("RUNASADMIN registry flag")) { $failures.Add("RUNASADMIN registry flag") }
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task -and $task.Principal.RunLevel -eq 'Highest') {
    Write-Output-Box "[OK] Scheduled Task : $TaskName (RunLevel $($task.Principal.RunLevel))"
} else {
    Write-Output-Box "[ERROR] Scheduled Task : missing or not elevated"
    if (-not $failures.Contains("Scheduled Task")) { $failures.Add("Scheduled Task") }
}

if ($lnkPath -and (Test-Path -LiteralPath $lnkPath) -and (Test-Path -LiteralPath $vbsPath)) {
    Write-Output-Box "[OK] Desktop shortcut and launcher both present"
} else {
    Write-Output-Box "[ERROR] Desktop shortcut or launcher missing"
    if (-not $failures.Contains("Desktop shortcut")) { $failures.Add("Desktop shortcut") }
}

# A tool sitting somewhere every user can rewrite undermines the elevated task:
# whoever edits the EXE decides what runs with admin rights.
try {
    $userWritable = @("$env:USERPROFILE", "$env:PUBLIC", "$env:TEMP") |
                    Where-Object { $_ -and $targetDir.StartsWith($_, 'OrdinalIgnoreCase') }
    if ($userWritable) {
        Write-Output-Box ""
        Write-Output-Box "[WARNING] The tool sits in a user-writable folder ($targetDir)."
        Write-Output-Box "[WARNING] Anyone who can edit that file decides what runs elevated."
        Write-Output-Box "[INFO] Consider moving the .exe under C:\Program Files and re-running this."
    }
} catch { }

Write-Output-Box ""
if ($failures.Count -eq 0) {
    Write-Output-Box "[OK] Done. Use the Desktop shortcut '$ShortcutName' - it opens elevated with no UAC prompt."
    Write-Output-Box "[INFO] Launching the .exe directly still elevates, but still shows UAC."
    Write-Output-Box "[INFO] Re-run this after moving the .exe: both routes store an absolute path."
    exit 0
} else {
    Write-Output-Box "[WARNING] Finished with problems: $($failures -join '; ')"
    exit 1
}
