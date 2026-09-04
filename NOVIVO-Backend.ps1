# NOVIVO-Backend.ps1 - Install logic only
param([Parameter(Mandatory)][string]$Method,[string]$NetworkKey,[string]$UsersJson,[int]$RdpPort = 3389,[switch]$PreflightOnly)

function Write-Output-Box { param([string]$Message,[string]$Color="Lime"); Write-Host $Message; [Console]::Out.Flush() }

function Test-RDPPort {
    param([string]$IPAddress, [int]$Port = 3389, [int]$TimeoutSeconds = 3)
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $tcp.BeginConnect($IPAddress, $Port, $null, $null)
        # WaitOne() is signalled for a REFUSED connection too, so it alone proves
        # nothing. EndConnect() throws unless the handshake actually completed.
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)) {
            try { $tcp.Close() } catch {}
            return $false
        }
        $tcp.EndConnect($ar)
        $connected = $tcp.Connected
        try { $tcp.Close() } catch {}
        return $connected
    } catch {
        if ($tcp) { try { $tcp.Close() } catch {} }
        return $false
    }
}

function Test-RdpListener {
    # Is the RDP listener REALLY up? A bare port check is also satisfied by an
    # unrelated process squatting the port - often the very reason TermService
    # could not bind it - so attribute the socket to TermService when possible.
    param([int]$Port)
    $conns = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($conns.Count -eq 0) { return $false }
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='TermService'" -ErrorAction Stop
        if ($svc -and $svc.ProcessId) {
            return [bool]($conns | Where-Object { $_.OwningProcess -eq $svc.ProcessId })
        }
    } catch { }
    return $true      # owner could not be determined - accept "something is listening"
}

# ═══════════════════════════════════════════════════════════════════════════
#  OS SUPPORT PREFLIGHT
#  Not every Windows can host this. Establish that before downloading 20 MB of
#  installer and failing on step 7 with "tailscale.exe not found".
# ═══════════════════════════════════════════════════════════════════════════

function Get-NovivoOSInfo {
    # Build number is the only trustworthy gate: Caption is localised, and
    # ProductName still reads "Windows 10" on Windows 11.
    $info = [ordered]@{
        Build = 0; UBR = 0; Caption = 'Unknown'
        IsHome = $false; IsServer = $false; IsSMode = $false
        Is64Bit = [Environment]::Is64BitOperatingSystem
    }
    try {
        $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $info.Build = [int](Get-ItemProperty -Path $cv -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
        $ubr = Get-ItemProperty -Path $cv -Name UBR -ErrorAction SilentlyContinue
        if ($ubr) { $info.UBR = [int]$ubr.UBR }
    } catch {
        try { $info.Build = [Environment]::OSVersion.Version.Build } catch { }
    }
    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop }
    catch { try { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop } catch { } }
    if ($os) {
        $info.Caption  = $os.Caption
        $info.IsServer = ($os.ProductType -ne 1)
        # SKU beats the localised Caption. 2/3/5 = Home Basic/Premium/N,
        # 98..101 = Core / Core N / Core Single Language / Core Country Specific
        if ($null -ne $os.OperatingSystemSKU) {
            $info.IsHome = (@(2,3,5,98,99,100,101) -contains [int]$os.OperatingSystemSKU)
        }
    }
    if (-not $info.IsHome -and $info.Caption -match '\bHome\b|\bCore\b') { $info.IsHome = $true }
    # S mode locks the machine to Store apps - no installer of ours can run.
    try {
        $ci = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name SkuPolicyRequired -ErrorAction SilentlyContinue
        if ($ci -and [int]$ci.SkuPolicyRequired -eq 1) { $info.IsSMode = $true }
    } catch { }
    return [pscustomobject]$info
}

function Test-NovivoOSSupport {
    # $true = setup may continue. On $false the reason has already been printed.
    param([string]$Method, $OSInfo)

    $bits = '32-bit'
    if ($OSInfo.Is64Bit) { $bits = '64-bit' }
    $ed = 'Pro/Enterprise'
    if ($OSInfo.IsHome) { $ed = 'Home' }
    Write-Output-Box "[INFO] Windows: $($OSInfo.Caption)"
    Write-Output-Box "[INFO] Build $($OSInfo.Build).$($OSInfo.UBR) - $bits - edition family: $ed"

    if ($OSInfo.IsSMode) {
        Write-Output-Box ""
        Write-Output-Box "[ERROR] This PC runs Windows in S mode."
        Write-Output-Box "[INFO] S mode only permits apps from the Microsoft Store, so neither"
        Write-Output-Box "[INFO] Tailscale nor ZeroTier can be installed."
        Write-Output-Box "[INFO] Fix: Settings > System > Activation > 'Switch out of S mode'"
        Write-Output-Box "[INFO] (one-way change - there is no way back to S mode afterwards)"
        return $false
    }

    if ($Method -eq 'tailscale' -and $OSInfo.Build -lt 17763) {
        $name = "Windows 10 build $($OSInfo.Build) (older than 1809)"
        if     ($OSInfo.Build -lt 9200)  { $name = 'Windows 7 / Server 2008 R2' }
        elseif ($OSInfo.Build -lt 9600)  { $name = 'Windows 8 / Server 2012' }
        elseif ($OSInfo.Build -eq 9600)  { $name = 'Windows 8.1 / Server 2012 R2' }
        Write-Output-Box ""
        Write-Output-Box "[ERROR] Tailscale does not support $name."
        Write-Output-Box "[INFO] Tailscale needs Windows 10 build 17763 (version 1809) or newer,"
        Write-Output-Box "[INFO] Windows 11, or Windows Server 2019 and later. Support for"
        Write-Output-Box "[INFO] Windows 7 and 8.1 was dropped by Tailscale in 2023."
        Write-Output-Box ""
        Write-Output-Box "[INFO] >>> Use the ZeroTier method instead - it still runs on this Windows."
        Write-Output-Box "[INFO] Switch the method to ZeroTier in the app and paste a ZeroTier"
        Write-Output-Box "[INFO] Network ID (16 hex characters) in place of the Tailscale auth key."
        Write-Output-Box "[INFO] The switch cannot be made automatically: a Tailscale auth key is"
        Write-Output-Box "[INFO] not a ZeroTier Network ID, so there is no credential to carry over."
        return $false
    }

    if ($Method -ne 'tailscale' -and $OSInfo.Build -lt 7601) {
        Write-Output-Box ""
        Write-Output-Box "[ERROR] ZeroTier needs Windows 7 SP1 (build 7601) or newer."
        return $false
    }
    if ($Method -ne 'tailscale' -and $OSInfo.Build -lt 10240) {
        Write-Output-Box "[WARNING] ZeroTier no longer targets this Windows version - the installer"
        Write-Output-Box "[WARNING] may fail or the virtual adapter may not load. Continuing anyway."
    }

    return $true
}

# ═══════════════════════════════════════════════════════════════════════════
#  WINDOWS HOME RDP SUPPORT
#  Home ships no RDP host. RDP Wrapper is the usual fix, but "installed" is not
#  "working": rdpwrap.ini carries one section per Windows build and is routinely
#  months behind, so the wrapper loads while RDP stays dead. Every step below is
#  therefore verified, with a termsrv.dll patch as the fallback.
# ═══════════════════════════════════════════════════════════════════════════

function Add-NovivoDefenderExclusion {
    # Defender flags both RDPWrap and a patched termsrv.dll as
    # HackTool:Win32/RDPWrap and deletes them mid-install. Best-effort only:
    # Defender may be off, policy-locked, or replaced by a third-party AV.
    # ProgramData\NOVIVO holds the generated repair script, which Defender also
    # scans (as script content) each time the boot task runs it.
    $paths = @("$env:TEMP", "$env:ProgramFiles\RDP Wrapper",
               "$env:SystemRoot\System32\termsrv.dll", "$env:ProgramData\NOVIVO")
    $added = 0
    foreach ($p in $paths) {
        try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop ; $added++ } catch { }
    }
    try { Add-MpPreference -ExclusionProcess 'RDPWInst.exe' -ErrorAction SilentlyContinue } catch { }
    if ($added -gt 0) {
        Write-Output-Box "[OK] Defender exclusions added ($added of $($paths.Count) paths)"
    } else {
        Write-Output-Box "[INFO] Defender exclusions not applied (Defender disabled, policy-locked, or 3rd-party AV)"
    }
}

function Test-RdpWrapActive {
    # Proof of life, not proof of installation: rdpwrap.dll actually mapped into
    # the TermService host process, plus a listener owned by that process.
    param([int]$Port)
    $loaded = $false
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='TermService'" -ErrorAction Stop
        if ($svc -and $svc.ProcessId) {
            $proc = Get-Process -Id $svc.ProcessId -ErrorAction SilentlyContinue
            if ($proc) {
                try { $loaded = [bool](@($proc.Modules) | Where-Object { $_.ModuleName -eq 'rdpwrap.dll' }) } catch { }
            }
        }
    } catch { }
    $listening = Test-RdpListener -Port $Port
    return [pscustomobject]@{ WrapperLoaded = $loaded; Listening = $listening; Ok = $listening }
}

function New-NovivoRepairScript {
    # One generated file is the single source of truth for repairing RDP, used
    # both as the install-time fallback and as the boot-time scheduled task.
    $dir = "$env:ProgramData\NOVIVO"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir 'Repair-NovivoRdp.ps1'
    $body = @'
# NOVIVO RDP repair - re-arms RDP hosting on Windows Home.
# Generated by NOVIVO Remote Desktop. Runs at boot and on demand.
param([int]$Port = __PORT__, [switch]$PatchOnly)

$LogDir = "$env:ProgramData\NOVIVO"
$Log    = Join-Path $LogDir 'rdp-repair.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param([string]$m) ; "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -Path $Log }

function Test-Listener {
    $c = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return $false }
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='TermService'" -ErrorAction Stop
        if ($svc -and $svc.ProcessId) { return [bool]($c | Where-Object { $_.OwningProcess -eq $svc.ProcessId }) }
    } catch { }
    return $true
}

function Update-RdpWrapIni {
    # A new Windows build needs a matching rdpwrap.ini section. The community
    # fork is the only one still updated.
    $ini = "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"
    if (-not (Test-Path $ini)) { return $false }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
        $tmp = "$env:TEMP\rdpwrap.ini.new"
        $wc.DownloadFile('https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini', $tmp)
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 10KB) { Write-Log 'ini download too small - ignored'; return $false }
        Copy-Item $tmp $ini -Force
        Restart-Service TermService -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 8
        return $true
    } catch { Write-Log "ini refresh failed: $($_.Exception.Message)"; return $false }
}

function Invoke-TermSrvPatch {
    # x64 Win10/11 session-limit check:
    #   39 81 3C 06 00 00   cmp dword ptr [rcx+63Ch], eax
    #   0F 84 xx xx xx xx   je  <reject connection>
    # becomes
    #   B8 00 01 00 00      mov eax, 100h
    #   89 81 38 06 00 00   mov dword ptr [rcx+638h], eax
    #   90                  nop
    # The signature must occur EXACTLY once. A blind scan that patches every hit
    # corrupts the DLL, so anything other than one match is a hard refusal.
    if (-not [Environment]::Is64BitOperatingSystem) { Write-Log 'termsrv patch: 32-bit OS not supported'; return $false }
    $src = "$env:SystemRoot\System32\termsrv.dll"
    $bak = "$env:SystemRoot\System32\termsrv.dll.novivo.bak"
    $sigHex = '39813C0600000F84'
    $newBytes = [byte[]](0xB8,0x00,0x01,0x00,0x00,0x89,0x81,0x38,0x06,0x00,0x00,0x90)

    try { $bytes = [System.IO.File]::ReadAllBytes($src) }
    catch { Write-Log "termsrv read failed: $($_.Exception.Message)"; return $false }

    # Hex-string search: a managed scan over ~1 MB is far too slow in PS 5.1.
    $hex  = [System.BitConverter]::ToString($bytes) -replace '-', ''
    $hits = @()
    $pos  = $hex.IndexOf($sigHex)
    while ($pos -ge 0) {
        if ($pos % 2 -eq 0) { $hits += ($pos / 2) }   # odd index = not a byte boundary
        $pos = $hex.IndexOf($sigHex, $pos + 1)
    }
    if ($hits.Count -ne 1) {
        Write-Log "termsrv patch: signature matched $($hits.Count) time(s) - refusing to patch"
        return $false
    }
    $off = $hits[0]
    Write-Log "termsrv patch: signature at offset 0x$('{0:X}' -f $off)"

    Stop-Service TermService -Force -ErrorAction SilentlyContinue
    Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4

    # The signature is only present in an UNPATCHED file, so this backup is
    # always pristine - including after a Windows Update replaced the DLL.
    try { Copy-Item $src $bak -Force } catch { Write-Log "backup failed: $($_.Exception.Message)"; return $false }

    & takeown.exe /f $src /a 2>&1 | Out-Null
    & icacls.exe $src /grant '*S-1-5-32-544:F' 2>&1 | Out-Null

    for ($k = 0; $k -lt $newBytes.Length; $k++) { $bytes[$off + $k] = $newBytes[$k] }

    $written = $false
    try { [System.IO.File]::WriteAllBytes($src, $bytes); $written = $true }
    catch {
        # File still mapped: swap it out under a different name instead.
        try {
            $stale = "$src.old"
            if (Test-Path $stale) { Remove-Item $stale -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $src -NewName 'termsrv.dll.old' -Force
            [System.IO.File]::WriteAllBytes($src, $bytes)
            $written = $true
        } catch { Write-Log "termsrv write failed: $($_.Exception.Message)" }
    }
    if (-not $written) { return $false }

    & icacls.exe $src /setowner 'NT SERVICE\TrustedInstaller' 2>&1 | Out-Null

    # RDPWrap may have redirected ServiceDll; the patch only takes effect when
    # TermService loads the real termsrv.dll again.
    try {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\services\TermService\Parameters' `
            -Name 'ServiceDll' -Value '%SystemRoot%\System32\termsrv.dll' -Type ExpandString -Force
    } catch { }

    Start-Service TermService -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 8
    if (Test-Listener) { Write-Log 'termsrv patch applied and listener is up'; return $true }

    Write-Log 'termsrv patch did not bring the listener up - rolling back'
    Stop-Service TermService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    try { Copy-Item $bak $src -Force } catch { Write-Log "ROLLBACK FAILED: $($_.Exception.Message)" }
    Start-Service TermService -ErrorAction SilentlyContinue
    return $false
}

# ── main ────────────────────────────────────────────────────────────────────
if (-not $PatchOnly) {
    Start-Sleep -Seconds 30          # let TermService settle when run at boot
    if (Test-Listener) { exit 0 }
    Write-Log "listener down on port $Port - repairing"
    if (Update-RdpWrapIni) {
        if (Test-Listener) { Write-Log 'repaired by refreshing rdpwrap.ini'; exit 0 }
    }
}
if (Invoke-TermSrvPatch) { exit 0 }
Write-Log 'repair exhausted - RDP still down'
exit 1
'@
    $body = $body.Replace('__PORT__', [string]$RdpPort)
    Set-Content -Path $path -Value $body -Encoding UTF8 -Force
    return $path
}

function Enable-NovivoMultiSession {
    # Home permits a single session. These are the switches RDPWrap and the
    # termsrv patch rely on to admit concurrent users.
    $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    try {
        Set-ItemProperty -Path $ts -Name 'fSingleSessionPerUser' -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Output-Box "[OK] Concurrent sessions enabled (fSingleSessionPerUser=0)"
    } catch { Write-Output-Box "[INFO] fSingleSessionPerUser: $($_.Exception.Message)" }
    # 0xFFFFFFFF overflows Int32 in Set-ItemProperty, so go through reg.exe.
    & reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxInstanceCount /t REG_DWORD /d 4294967295 /f 2>&1 | Out-Null
    Write-Output-Box "[OK] Session limit raised (MaxInstanceCount unlimited)"
}

function Register-NovivoRepairTask {
    # Windows Update replaces termsrv.dll and bumps the build number, silently
    # killing both RDPWrap (no ini section for the new build) and any patch.
    param([string]$ScriptPath)
    $taskName = 'NOVIVO-RDP-AutoRepair'
    try {
        schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null
        $ps  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $cmd = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
        & schtasks.exe /Create /TN $taskName /TR $cmd /SC ONSTART /RU SYSTEM /RL HIGHEST /F 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Output-Box "[OK] Auto-repair task registered (runs at every boot)"
        } else {
            Write-Output-Box "[WARNING] Could not register auto-repair task (schtasks exit $LASTEXITCODE)"
        }
    } catch { Write-Output-Box "[WARNING] Auto-repair task: $($_.Exception.Message)" }
}

function Install-HomeRdpSupport {
    # Everything Windows Home needs to host RDP, in order, each step verified.
    param([int]$Port)

    Write-Output-Box ""
    Write-Output-Box "[HOME] Windows Home detected - installing RDP hosting support..."

    # 1. keep the AV from eating the payload, the patched DLL, or the repair
    #    script - done first so every path below writes into excluded folders
    Add-NovivoDefenderExclusion

    $active = Test-RdpWrapActive -Port $Port
    if ($active.Ok) {
        Write-Output-Box "[OK] RDP is already listening - skipping RDP Wrapper install"
        Enable-NovivoMultiSession
        $sp = New-NovivoRepairScript
        Register-NovivoRepairTask -ScriptPath $sp
        return $true
    }

    # 2. RDP Wrapper + a current ini
    $rdpwZip = "$env:TEMP\RDPWrap.zip"
    $rdpwDir = "$env:TEMP\RDPWrapExtract"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $wc.DownloadFile("https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip", $rdpwZip)
        if ((Test-Path $rdpwZip) -and (Get-Item $rdpwZip).Length -gt 100KB) {
            if (Test-Path $rdpwDir) { Remove-Item $rdpwDir -Recurse -Force }
            Expand-Archive -Path $rdpwZip -DestinationPath $rdpwDir -Force
            $inst = Get-ChildItem $rdpwDir -Filter "RDPWInst.exe" -Recurse | Select-Object -First 1
            if ($inst) {
                $p = Start-Process -FilePath $inst.FullName -ArgumentList "-i" -Wait -PassThru -WindowStyle Hidden
                Write-Output-Box "[OK] RDP Wrapper installed (exit code $($p.ExitCode))"
                try {
                    $wc2 = New-Object System.Net.WebClient
                    $wc2.Headers.Add("User-Agent", "Mozilla/5.0")
                    $wc2.DownloadFile("https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini", "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini")
                    Write-Output-Box "[OK] rdpwrap.ini updated for the current Windows build"
                } catch { Write-Output-Box "[INFO] ini update skipped: $($_.Exception.Message)" }
                Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 8
            } else { Write-Output-Box "[WARNING] RDPWInst.exe not found inside the archive" }
        } else { Write-Output-Box "[WARNING] RDP Wrapper download failed or the file is too small" }
    } catch { Write-Output-Box "[WARNING] RDP Wrapper install failed: $($_.Exception.Message)" }

    # 3. did it actually work? this is the check the old code never made
    $active = Test-RdpWrapActive -Port $Port
    if ($active.WrapperLoaded) { Write-Output-Box "[OK] rdpwrap.dll is loaded into TermService" }
    else { Write-Output-Box "[WARNING] rdpwrap.dll is NOT loaded into TermService" }

    $ok = $active.Ok
    if ($ok) {
        Write-Output-Box "[OK] RDP listener verified on port $Port"
    } else {
        # 4. fallback: patch termsrv.dll directly
        Write-Output-Box "[WARNING] RDP Wrapper is installed but RDP is still not listening."
        Write-Output-Box "[INFO] This build most likely has no section in rdpwrap.ini."
        Write-Output-Box "[INFO] Falling back to patching termsrv.dll (backup + auto-rollback)..."
        $sp = New-NovivoRepairScript
        try {
            $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            $pp = Start-Process -FilePath $ps -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$sp`"","-PatchOnly","-Port",$Port -Wait -PassThru -WindowStyle Hidden
            $ok = ($pp.ExitCode -eq 0)
        } catch { Write-Output-Box "[WARNING] termsrv patch failed to run: $($_.Exception.Message)" }
        if ($ok) {
            Write-Output-Box "[OK] termsrv.dll patched - RDP listener is up"
        } else {
            Write-Output-Box "[WARNING] termsrv.dll patch did not help (see $env:ProgramData\NOVIVO\rdp-repair.log)"
            Write-Output-Box "[WARNING] Could not auto-enable RDP hosting on Windows Home"
            Write-Output-Box "[INFO] Options: upgrade to Windows Pro, or use Chrome Remote Desktop"
        }
    }

    # 5 + 6. concurrent sessions, and survive the next Windows Update
    Enable-NovivoMultiSession
    $sp2 = New-NovivoRepairScript
    Register-NovivoRepairTask -ScriptPath $sp2

    return $ok
}

# Dry run: report what this Windows supports and change nothing.
if ($PreflightOnly) {
    $osi = Get-NovivoOSInfo
    $supported = Test-NovivoOSSupport -Method $Method -OSInfo $osi
    Write-Output-Box ""
    if ($supported) { Write-Output-Box "[RESULT] Supported - setup would continue." ; exit 0 }
    Write-Output-Box "[RESULT] Not supported - setup would stop here."
    exit 2
}

# NetworkKey/UsersJson are validated below rather than declared Mandatory: a
# missing Mandatory parameter makes powershell.exe block on a console prompt
# that a GUI-spawned process can never answer.
$userList = @()
if (-not [string]::IsNullOrWhiteSpace($UsersJson)) { $userList = @($UsersJson | ConvertFrom-Json) }
$networkID = $NetworkKey
$rdpWorking = $false

# ── Preflight: can this Windows host the selected method at all? ────────────
# Runs before anything with a side effect, so an unsupported machine is left
# exactly as it was found.
$osInfo = Get-NovivoOSInfo
if (-not (Test-NovivoOSSupport -Method $Method -OSInfo $osInfo)) {
    Write-Output-Box ""
    Write-Output-Box "[INFO] Setup stopped - no changes were made to this computer."
    exit 2
}

# ── Disable sleep & hibernate during installation ───────────────────────────
$_powerLoaded = $false
try {
    $sig = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    Add-Type -MemberDefinition $sig -Name "NovivoPower" -Namespace "Win32" -ErrorAction Stop
    $_powerLoaded = $true
} catch {
    # Type may already be loaded from a previous run
    try { [void][Win32.NovivoPower] ; $_powerLoaded = $true } catch { $_powerLoaded = $false }
}
if ($_powerLoaded) {
    # ES_CONTINUOUS(2147483648) | ES_SYSTEM_REQUIRED(1) | ES_AWAYMODE_REQUIRED(64)
    # Use decimal literals - PS5.1 parses 0x80000000 as negative Int32 which fails UInt32 cast
    [void][Win32.NovivoPower]::SetThreadExecutionState([uint32]2147483648 -bor [uint32]1 -bor [uint32]64)
}
powercfg /hibernate off 2>$null | Out-Null
Write-Output-Box "[INFO] Sleep blocked during setup; hibernate turned off permanently (an RDP host must stay reachable)"

try {
    $rdpWorking = $false
    
    try {
        # Validate inputs
        if ([string]::IsNullOrWhiteSpace($networkID)) {
            Write-Output-Box "[ERROR] Network ID / Auth Key cannot be empty!"
            return
        }
        if ($userList.Count -eq 0) {
            Write-Output-Box "[ERROR] Please add at least one user in the Users table!"
            return
        }
        foreach ($u in $userList) {
            if ([string]::IsNullOrWhiteSpace($u.Password)) {
                Write-Output-Box "[ERROR] Password for user '$($u.Username)' cannot be empty!"
                return
            }
        }
        # Primary user used for connection info display
        $username = $userList[0].Username
        $password = $userList[0].Password

        # ====================================================================
        #  TAILSCALE BRANCH  – runs when user selects Tailscale method
        # ====================================================================
        if ($Method -eq "tailscale") {

            $authKey  = $networkID
            $tsRdpWorking = $false
            $tsNeedsAutoRestart = $false

            Write-Output-Box "==================================================="
            Write-Output-Box ">>> NOVIVO REMOTE DESKTOP - TAILSCALE SETUP <<<"
            Write-Output-Box "==================================================="
            Write-Output-Box ""

            # TS-STEP 1: Download / Install Tailscale
            Write-Output-Box "[1/7] Downloading Tailscale installer..."
            $tsInstallerPath = "$env:TEMP\TailscaleSetup.exe"  # default, overridden per URL in loop
            $tsInstalledViaWinget = $false

            # --- Try winget first (most reliable, no URL guessing) ---
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Output-Box "[INFO] Trying winget install..."
                try {
                    $wgOut = & winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -or $wgOut -match 'Successfully installed') {
                        Write-Output-Box "[OK] Tailscale installed via winget"
                        $tsInstalledViaWinget = $true
                    } else {
                        Write-Output-Box "[INFO] winget exit $LASTEXITCODE - falling back to direct download"
                    }
                } catch { Write-Output-Box "[INFO] winget failed - falling back to direct download" }
            }

            $tsDownloaded = $false
            # Check if already installed — skip download entirely if found
            $tsAlreadyInstalled = $false
            foreach ($tsPC in @("$env:ProgramFiles\Tailscale\tailscale.exe", 'C:\Program Files (x86)\Tailscale\tailscale.exe')) {
                if (Test-Path $tsPC) { $tsAlreadyInstalled = $true; break }
            }
            if (-not $tsAlreadyInstalled) {
                $tsPreGC = Get-Command tailscale -ErrorAction SilentlyContinue
                if ($tsPreGC) { $tsAlreadyInstalled = $true }
            }
            if (-not $tsInstalledViaWinget -and -not $tsAlreadyInstalled) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
                # Certificate validation stays ON: this downloads an installer that is
                # then run with admin rights, so an unverified peer is a code-exec hole.

                $tsUrls = @(
                    "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
                )

                foreach ($tsUrl in $tsUrls) {
                    try {
                        Write-Output-Box "Trying: $tsUrl"
                        # Save with correct extension
                        $tsExt = if ($tsUrl -match '\.msi$') { '.msi' } else { '.exe' }
                        $tsInstallerPath = "$env:TEMP\TailscaleSetup$tsExt"
                        $wc = New-Object System.Net.WebClient
                        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                        $wc.DownloadFile($tsUrl, $tsInstallerPath)
                        $tsFileOk = $false
                        if ((Test-Path $tsInstallerPath) -and (Get-Item $tsInstallerPath).Length -gt 5MB) {
                            $tsBytes = [System.IO.File]::ReadAllBytes($tsInstallerPath)
                            # EXE: MZ header; MSI: D0 CF 11 E0 (OLE2) or just skip header check for MSI
                            $tsValidHeader = ($tsExt -eq '.exe' -and $tsBytes[0] -eq 0x4D -and $tsBytes[1] -eq 0x5A) -or
                                             ($tsExt -eq '.msi' -and $tsBytes[0] -eq 0xD0 -and $tsBytes[1] -eq 0xCF)
                            if ($tsValidHeader) {
                                Write-Output-Box "[OK] Downloaded ($([math]::Round((Get-Item $tsInstallerPath).Length/1MB,2)) MB)"
                                $tsDownloaded = $true
                                $tsFileOk = $true
                            } else { Write-Output-Box "Invalid file header, skipping..." }
                        } else { Write-Output-Box "File too small (<5 MB), skipping..." }
                        if ($tsFileOk) { break }
                    }
                    catch {
                        Write-Output-Box "WebClient failed: $($_.Exception.Message)"
                        try {
                            $tsExt2 = if ($tsUrl -match '\.msi$') { '.msi' } else { '.exe' }
                            $tsInstallerPath = "$env:TEMP\TailscaleSetup$tsExt2"
                            Invoke-WebRequest -Uri $tsUrl -OutFile $tsInstallerPath -UseBasicParsing -TimeoutSec 180
                            if ((Test-Path $tsInstallerPath) -and (Get-Item $tsInstallerPath).Length -gt 5MB) {
                                $tsBytes2 = [System.IO.File]::ReadAllBytes($tsInstallerPath)
                                $tsVH2 = ($tsExt2 -eq '.exe' -and $tsBytes2[0] -eq 0x4D -and $tsBytes2[1] -eq 0x5A) -or
                                         ($tsExt2 -eq '.msi' -and $tsBytes2[0] -eq 0xD0 -and $tsBytes2[1] -eq 0xCF)
                                if ($tsVH2) {
                                    Write-Output-Box "[OK] Downloaded (fallback method)"
                                    $tsDownloaded = $true
                                    break
                                }
                            }
                        }
                        catch { Write-Output-Box "Fallback failed: $($_.Exception.Message)" }
                    }
                }

                if (-not $tsDownloaded) {
                    Write-Output-Box "[ERROR] Could not download Tailscale. Check internet connection."
                    return
                }
            }

            # TS-STEP 2: Install Tailscale silently
            Write-Output-Box ""
            Write-Output-Box "[2/7] Installing Tailscale..."

            if ($tsAlreadyInstalled) {
                Write-Output-Box "[INFO] Tailscale already installed  -  skipping installer"
            }

            if (-not $tsInstalledViaWinget -and -not $tsAlreadyInstalled) {
                try {
                    $tsIsMsi = $tsInstallerPath -match '\.msi$'
                    if ($tsIsMsi) {
                        Write-Output-Box "[INFO] Installing MSI package..."
                        $tsProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tsInstallerPath`" /qn /norestart" -Wait -PassThru
                        if ($tsProc.ExitCode -eq 1603 -or $tsProc.ExitCode -eq 1638) {
                            Write-Output-Box "[INFO] MSI code $($tsProc.ExitCode)  -  trying upgrade/repair mode..."
                            $tsProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tsInstallerPath`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vomus" -Wait -PassThru
                        }
                    } else {
                        $tsProc = Start-Process -FilePath $tsInstallerPath -ArgumentList "/S /NORESTART" -Wait -PassThru
                    }
                    if ($tsProc.ExitCode -eq 0 -or $tsProc.ExitCode -eq 3010) {
                        Write-Output-Box "[OK] Tailscale installed successfully (code $($tsProc.ExitCode))"
                    } else {
                        Write-Output-Box "[WARNING] Installer exit code $($tsProc.ExitCode)"
                        if (-not $tsIsMsi -and $tsProc.ExitCode -ne 0) {
                            Write-Output-Box "[INFO] Retrying with plain /S flag..."
                            $tsProc2 = Start-Process -FilePath $tsInstallerPath -ArgumentList "/S" -Wait -PassThru
                            Write-Output-Box "[INFO] Retry exit code: $($tsProc2.ExitCode)"
                        }
                    }
                    Start-Sleep -Seconds 10
                }
                catch {
                    Write-Output-Box "[ERROR] Tailscale install error: $($_.Exception.Message)"
                    return
                }
            } else {
                if ($tsInstalledViaWinget) { Write-Output-Box "[INFO] Skipping installer (already installed via winget)" }
                # else: already installed branch already printed its own message above
            }

            # Locate tailscale.exe - refresh PATH first so newly installed binaries are found
            $tsCliPath = ''
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
            Start-Sleep -Seconds 5

            $tsPossiblePaths = @(
                "$env:ProgramFiles\Tailscale\tailscale.exe",
                'C:\Program Files (x86)\Tailscale\tailscale.exe',
                "$env:LocalAppData\Tailscale\tailscale.exe",
                'C:\Windows\System32\tailscale.exe'
            )
            foreach ($tsP in $tsPossiblePaths) {
                if (Test-Path $tsP) { $tsCliPath = $tsP; break }
            }
            if (-not $tsCliPath) {
                $tsGC2 = Get-Command tailscale -ErrorAction SilentlyContinue
                if ($tsGC2) { $tsCliPath = $tsGC2.Source }
            }
            # Last resort: find it on disk
            if (-not $tsCliPath) {
                $tsFound = Get-ChildItem 'C:\Program Files*' -Recurse -Filter 'tailscale.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($tsFound) { $tsCliPath = $tsFound.FullName }
            }
            if (-not $tsCliPath) {
                Write-Output-Box "[ERROR] tailscale.exe not found after installation. Install may have failed."
                Write-Output-Box "[INFO] Please install Tailscale manually from https://tailscale.com/download/windows"
                return
            }
            Write-Output-Box "[INFO] tailscale path: $tsCliPath"

            # ── Ensure Tailscale service is running ──────────────────────────────
            $tsSvcName = 'Tailscale'
            try {
                $tsSvcObj = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $tsSvcObj) { $tsSvcObj = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue }
                if ($tsSvcObj) { $tsSvcName = $tsSvcObj.Name }

                if ($tsSvcObj.Status -ne 'Running') {
                    Start-Service -Name $tsSvcName -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 4
                    Write-Output-Box "[INFO] Started Tailscale service"
                }
            } catch { }

            # ── Configure Tailscale user-session autostart (Startup folder + Run key)
            # Full boot-time config (service + scheduled task) is handled in step 6.5
            Write-Output-Box ""
            Write-Output-Box "[INFO] Configuring Tailscale user-session autostart..."

            # Method 1: All-Users Startup folder (fallback for after login)
            try {
                $tsTrayExe = $null
                $tsTrayPaths = @(
                    "$env:ProgramFiles\Tailscale\Tailscale.exe",
                    'C:\Program Files (x86)\Tailscale\Tailscale.exe'
                )
                foreach ($tp in $tsTrayPaths) { if (Test-Path $tp) { $tsTrayExe = $tp; break } }

                if ($tsTrayExe) {
                    $tsAllUsersStartup = [System.Environment]::GetFolderPath('CommonStartup')
                    if (-not $tsAllUsersStartup) {
                        $tsAllUsersStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
                    }
                    $tsLnkPath = Join-Path $tsAllUsersStartup "Tailscale.lnk"
                    $tsShell   = New-Object -ComObject WScript.Shell
                    $tsLnk     = $tsShell.CreateShortcut($tsLnkPath)
                    $tsLnk.TargetPath       = $tsTrayExe
                    $tsLnk.WorkingDirectory = Split-Path $tsTrayExe
                    $tsLnk.Description      = "Tailscale autostart"
                    $tsLnk.Save()
                    Write-Output-Box "[OK] Tailscale shortcut added to All-Users Startup folder"
                }
            } catch {
                Write-Output-Box "[WARNING] Startup folder: $($_.Exception.Message)"
            }

            # Method 4: HKLM Run key (machine-wide, any user session)
            try {
                $tsRunExe = if ($tsCliPath) { $tsCliPath } else { 'tailscale.exe' }
                Set-ItemProperty `
                    -Path  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
                    -Name  "TailscaleAutostart" `
                    -Value "`"$tsRunExe`"" `
                    -Type  String -Force
                Write-Output-Box "[OK] HKLM Run key set for Tailscale"
            } catch {
                Write-Output-Box "[WARNING] HKLM Run key: $($_.Exception.Message)"
            }

            Write-Output-Box "[OK] Tailscale user-session autostart configured (Startup folder + Run key)"

            # TS-STEP 3: Connect / bring up Tailscale
            Write-Output-Box ''
            Write-Output-Box '[3/7] Connecting to Tailscale network...'
            try {
                # --unattended = persist "want-up" state to disk so Tailscale reconnects
                # automatically after every reboot WITHOUT requiring user interaction
                $tsUpArgs = @('up', '--unattended', '--accept-routes', '--accept-dns')
                if (-not [string]::IsNullOrWhiteSpace($authKey)) {
                    Write-Output-Box '[INFO] Using auth key to connect...'
                    $tsUpArgs += @('--authkey', $authKey)
                } else {
                    Write-Output-Box '[INFO] No auth key - browser login may open'
                }
                $tsUpOut = & $tsCliPath $tsUpArgs 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0 -or $tsUpOut -match 'invalid key|expired|unauthorized|failed|error') {
                    Write-Output-Box "[ERROR] tailscale up did NOT succeed (exit code $LASTEXITCODE)"
                    Write-Output-Box "[INFO] The auth key is most likely expired, already used or revoked."
                    Write-Output-Box "[INFO] Generate a new one: https://login.tailscale.com/admin/settings/keys"
                } else {
                    Write-Output-Box '[OK] tailscale up --unattended executed (auto-reconnect on reboot enabled)'
                }
                if ($tsUpOut -and $tsUpOut.Trim()) { Write-Output-Box "Out: $($tsUpOut.Trim())" }
                Start-Sleep -Seconds 5
                # Show Tailscale connection status
                try {
                    $tsStatus = & $tsCliPath status 2>&1 | Out-String
                    if ($tsStatus) {
                        Write-Output-Box "[INFO] Tailscale status:"
                        $tsStatus.Trim().Split("`n") | Select-Object -First 8 | ForEach-Object {
                            Write-Output-Box "  $($_.TrimEnd())"
                        }
                    }
                } catch {}
            }
            catch {
                Write-Output-Box "[WARNING] tailscale up: $($_.Exception.Message)"
            }

            # TS-STEP 4: Enable RDP (same as ZeroTier)
            Write-Output-Box ""
            Write-Output-Box "[4/7] Configuring Remote Desktop..."
            try {
                & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
                & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f 2>&1 | Out-Null
                Write-Output-Box "[OK] Core RDP settings applied"
            }
            catch { Write-Output-Box "[WARNING] reg.exe failed, using PowerShell fallback" }

            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force

            $tsRegPaths = @(
                # Policy path overrides: these take priority over WinStation settings when a GPO exists
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fDenyTSConnections"; Value=0},
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fAllowToGetHelp"; Value=1},
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="UserAuthentication"; Value=0},
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="SecurityLayer"; Value=1},
                # WinStation settings
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name="AllowTSConnections"; Value=1},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="PortNumber"; Value=$RdpPort; Type="DWord"},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="SecurityLayer"; Value=1},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="UserAuthentication"; Value=0},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="fEnableWinStation"; Value=1},
                @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name="LocalAccountTokenFilterPolicy"; Value=1}
            )
            foreach ($r in $tsRegPaths) {
                if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
                $rType = if ($r.Type) { $r.Type } else { "DWord" }
                Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type $rType -Force
            }
            Write-Output-Box "[OK] RDP registry configured"

            # Firewall
            try {
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                $fwName = "RDP-Tailscale-$RdpPort"
                $existFw = Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue
                if ($existFw) { Remove-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue }
                New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Protocol TCP -LocalPort $RdpPort -Action Allow -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
                & netsh advfirewall firewall add rule name="RDP-Tailscale-Netsh" dir=in action=allow protocol=TCP localport=$RdpPort 2>&1 | Out-Null
                Write-Output-Box "[OK] Firewall rules configured"
            }
            catch { Write-Output-Box "[WARNING] Firewall: $($_.Exception.Message)" }

            # Enable RDP via WMI / CIM / wmic  -  tries multiple methods for Pro for Workstations
            try {
                $tsWmiTS = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root/cimv2/TerminalServices -ErrorAction SilentlyContinue
                if ($tsWmiTS) {
                    $wmiOk = $false
                    # PowerShell does NOT splat an array into method parameters, so each
                    # argument list has to be written out literally on its own call.
                    try { $tsWmiTS.SetAllowTSConnections(1) | Out-Null;    $wmiOk = $true } catch {}
                    if (-not $wmiOk) { try { $tsWmiTS.SetAllowTSConnections(1, 1) | Out-Null; $wmiOk = $true } catch {} }
                    if (-not $wmiOk) { try { $tsWmiTS.SetAllowTSConnections(1, 0) | Out-Null; $wmiOk = $true } catch {} }
                    if ($wmiOk) { Write-Output-Box "[OK] RDP enabled via WMI (AllowTSConnections)" }
                    else { Write-Output-Box "[INFO] WMI SetAllowTSConnections: all args failed - trying CIM..." }
                }
            } catch { Write-Output-Box "[INFO] WMI enable: $($_.Exception.Message)" }

            # CIM fallback (different code path from WMI - sometimes works on Pro for Workstations)
            try {
                $cimTS = Get-CimInstance -Namespace "root/cimv2/TerminalServices" -ClassName Win32_TerminalServiceSetting -ErrorAction Stop
                $cimResult = Invoke-CimMethod -InputObject $cimTS -MethodName "SetAllowTSConnections" -Arguments @{fAllowTSConnections=[uint32]1; ModifyFirewallException=[uint32]0} -ErrorAction Stop
                if ($cimResult.ReturnValue -eq 0) { Write-Output-Box "[OK] RDP enabled via CIM" }
            } catch {}

            # wmic command-line fallback (bypasses PowerShell WMI layer)
            try {
                $wmicOut = & cmd.exe /c "wmic /namespace:\\root\cimv2\TerminalServices PATH Win32_TerminalServiceSetting WHERE TerminalServerMode=1 CALL SetAllowTSConnections 1" 2>&1 | Out-String
                if ($wmicOut -match 'ReturnValue = 0') { Write-Output-Box "[OK] RDP enabled via wmic" }
            } catch {}

            # Windows Home ships no RDP host - install the support stack and
            # verify it actually took (see Install-HomeRdpSupport).
            try {
                if ($osInfo.IsHome) {
                    [void](Install-HomeRdpSupport -Port $RdpPort)
                } else {
                    Write-Output-Box "[INFO] Windows edition: $($osInfo.Caption) - native RDP host available"
                }
            } catch { Write-Output-Box "[WARNING] Home RDP support: $($_.Exception.Message)" }

            # TS-STEP 5: Configure user accounts
            Write-Output-Box ""
            Write-Output-Box "[5/7] Configuring $($userList.Count) user account(s)..."
            foreach ($userEntry in $userList) {
                $username = $userEntry.Username
                $password = $userEntry.Password
                Write-Output-Box "  [USER] >>> $username <<<"
                try {
                    # --- Detect Microsoft account FIRST ---
                    $isMicrosoftAccount = $false
                    try {
                        $localUserObj = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
                        if ($localUserObj -and "$($localUserObj.PrincipalSource)" -eq 'MicrosoftAccount') {
                            $isMicrosoftAccount = $true
                        }
                    } catch {}

                    if ($isMicrosoftAccount) {
                        Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                        Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                    } else {
                        $tsNetUserCheck = & net user $username 2>&1
                        $tsUserExists = ($LASTEXITCODE -eq 0)

                        if (-not $tsUserExists) {
                            $tsNetRes = & net user $username $password /add /passwordchg:no /expires:never /comment:"Created by NOVIVO Remote Desktop" 2>&1
                            $tsNetResStr = $tsNetRes | Out-String
                            if ($LASTEXITCODE -eq 0) {
                                Write-Output-Box "[OK] User created: $username"
                                & wmic useraccount where "name='$username'" set PasswordExpires=False 2>&1 | Out-Null
                            }
                            elseif ($tsNetResStr -match '8646|not authoritative|online provider') {
                                Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                                Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                            }
                            else { throw "Failed to create user: $tsNetResStr" }
                        } else {
                            $tsNetRes = & net user $username $password 2>&1
                            $tsNetResStr = $tsNetRes | Out-String
                            if ($LASTEXITCODE -eq 0) {
                                Write-Output-Box "[OK] Password updated for: $username"
                                & wmic useraccount where "name='$username'" set PasswordExpires=False 2>&1 | Out-Null
                            }
                            elseif ($tsNetResStr -match '8646|not authoritative|online provider') {
                                Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                                Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                            }
                            else { throw "Failed to update password: $tsNetResStr" }
                        }
                    }
                    # Get Remote Desktop Users group name via SID (works on all locales)
                    $tsRdpGroupName = 'Remote Desktop Users'
                    try {
                        $tsRdpSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-555'
                        $tsRdpNT  = $tsRdpSid.Translate([System.Security.Principal.NTAccount]).Value
                        $tsParts  = $tsRdpNT.Split('\\'.ToCharArray())
                        $tsRdpGroupName = $tsParts[$tsParts.Length - 1]
                    } catch { }

                    $tsAddAdm = & net localgroup Administrators $username /add 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to Administrators" }
                    else { Write-Output-Box "[INFO] Administrators: $tsAddAdm" }
                    # Create the group if it doesn't exist (absent on Win11 Home/some configs)
                    $tsRdpGrpExists = Get-LocalGroup -SID "S-1-5-32-555" -ErrorAction SilentlyContinue
                    if (-not $tsRdpGrpExists) {
                        try {
                            New-LocalGroup -Name $tsRdpGroupName -Description "Members in this group are granted the right to logon remotely" -ErrorAction SilentlyContinue | Out-Null
                            Write-Output-Box "[OK] Created '$tsRdpGroupName' group (was missing)"
                        } catch { Write-Output-Box "[INFO] Could not create RDP group: $($_.Exception.Message)" }
                    }
                    try {
                        Add-LocalGroupMember -SID "S-1-5-32-555" -Member $username -ErrorAction Stop
                        Write-Output-Box "[OK] Added to $tsRdpGroupName"
                    } catch {
                        if ($_.Exception.Message -match 'already.*member|member.*already') {
                            Write-Output-Box "[INFO] Already in $tsRdpGroupName"
                        } else {
                            $tsAddRdp = & net localgroup $tsRdpGroupName $username /add 2>&1
                            if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to $tsRdpGroupName" }
                            else { Write-Output-Box "[INFO] RDP Users: $tsAddRdp" }
                        }
                    }
                }
                catch {
                    Write-Output-Box "[ERROR] User config failed for '$username': $($_.Exception.Message)"
                    return
                }
            }

            # TS-STEP 6: Restart RDP services
            Write-Output-Box ""
            Write-Output-Box "[6/7] Restarting RDP services..."
            try {
                Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "SessionEnv"  -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "UmRdpService"-Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                & sc.exe config TermService  start= auto 2>&1 | Out-Null
                & sc.exe config SessionEnv   start= auto 2>&1 | Out-Null
                & sc.exe config UmRdpService start= auto 2>&1 | Out-Null

                Start-Service -Name "SessionEnv"   -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Service -Name "TermService"  -ErrorAction Stop
                Start-Sleep -Seconds 5
                Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue

                $tsSvc = Get-Service -Name "TermService"
                if ($tsSvc.Status -eq "Running") {
                    Write-Output-Box "[OK] TermService is RUNNING"
                    $tsRdpWorking = $true
                } else {
                    Write-Output-Box "[WARNING] TermService status: $($tsSvc.Status)"
                }

                # Poll for port — Pro for Workstations can take 20-45s to bind after service start
                Write-Output-Box "[INFO] Waiting for port $RdpPort to bind (up to 45s)..."
                $tsPortReady = $false
                for ($pi = 1; $pi -le 15; $pi++) {
                    Start-Sleep -Seconds 3
                    $tsPortCheck = Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue
                    if ($tsPortCheck) {
                        Write-Output-Box "[OK] Port $RdpPort is LISTENING (bound after $($pi*3)s)"
                        $tsRdpWorking = $true; $tsPortReady = $true; break
                    }
                    if ($pi % 5 -eq 0) { Write-Output-Box "[INFO] Still waiting... ($($pi*3)s elapsed)" }
                }

                if (-not $tsPortReady) {
                    Write-Output-Box "[WARNING] Port $RdpPort not yet listening - running deep reset (no reboot)..."

                    # Toggle fEnableWinStation=0 → full stop → fEnableWinStation=1 → start
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "fEnableWinStation" -Value 0 -Force -ErrorAction SilentlyContinue
                    & sc.exe stop UmRdpService 2>&1 | Out-Null
                    & sc.exe stop TermService  2>&1 | Out-Null
                    & sc.exe stop SessionEnv   2>&1 | Out-Null
                    Start-Sleep -Seconds 5
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "fEnableWinStation" -Value 1 -Force -ErrorAction SilentlyContinue
                    & sc.exe start SessionEnv   2>&1 | Out-Null; Start-Sleep -Seconds 3
                    & sc.exe start TermService  2>&1 | Out-Null; Start-Sleep -Seconds 3
                    & sc.exe start UmRdpService 2>&1 | Out-Null

                    # Poll again after deep reset
                    Write-Output-Box "[INFO] Waiting for port $RdpPort after deep reset (up to 45s)..."
                    for ($pi = 1; $pi -le 15; $pi++) {
                        Start-Sleep -Seconds 3
                        $tsPortCheck2 = Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue
                        if ($tsPortCheck2) {
                            Write-Output-Box "[OK] Port $RdpPort LISTENING after deep reset (bound after $($pi*3)s)"
                            $tsRdpWorking = $true; $tsPortReady = $true; break
                        }
                        if ($pi % 5 -eq 0) { Write-Output-Box "[INFO] Still waiting... ($($pi*3)s elapsed)" }
                    }

                    if (-not $tsPortReady) {
                        Write-Output-Box "[WARNING] Port $RdpPort still not listening after all reset attempts"
                        Write-Output-Box "[INFO] Windows 10 Pro for Workstations requires a clean OS boot to activate RDP listener"
                        Write-Output-Box "[INFO] Auto-restart will be triggered after setup completes"
                        $tsRdpWorking = $false
                        $tsNeedsAutoRestart = $true
                    }
                }
            }
            catch {
                Write-Output-Box "[WARNING] Service restart: $($_.Exception.Message)"
            }

            # TS-STEP 6.5: Configure Tailscale to auto-connect on boot (headless/no-login)
            Write-Output-Box ""
            Write-Output-Box "[INFO] Configuring Tailscale headless auto-start..."
            try {
                # 1. Set Tailscale service to Automatic + network dependency + recovery restart
                $tsSvcName2 = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name
                if (-not $tsSvcName2) { $tsSvcName2 = 'Tailscale' }
                # Startup type: Automatic (delayed)  -  starts after network ready
                & sc.exe config $tsSvcName2 start= delayed-auto 2>&1 | Out-Null
                # Network stack dependency
                & sc.exe config $tsSvcName2 depend= Tcpip/Afd/Nsi 2>&1 | Out-Null
                # Recovery: restart service on 1st, 2nd, subsequent failures (reset counter every 86400s)
                & sc.exe failure $tsSvcName2 reset= 86400 actions= restart/5000/restart/10000/restart/10000 2>&1 | Out-Null
                Write-Output-Box "[OK] Tailscale service: delayed-auto + network dependency + auto-recovery set"

                # 2. Save auth key to disk (used as fallback if node state is lost)
                $tsScriptDir = "$env:ProgramData\Tailscale"
                if (-not (Test-Path $tsScriptDir)) { New-Item -ItemType Directory -Path $tsScriptDir -Force | Out-Null }
                $tsKeyFile = "$tsScriptDir\auth.key"
                if (-not [string]::IsNullOrWhiteSpace($authKey)) {
                    $authKey | Set-Content -Path $tsKeyFile -Encoding UTF8 -Force
                    # Restrict file to Administrators + SYSTEM only
                    $acl = Get-Acl $tsKeyFile
                    $acl.SetAccessRuleProtection($true, $false)
                    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
                    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM","FullControl","Allow")))
                    Set-Acl $tsKeyFile $acl -ErrorAction SilentlyContinue
                    Write-Output-Box "[OK] Auth key saved for reconnection fallback"
                }

                # 3. Write reconnect helper script  -  logs every step for diagnostics
                $tsScriptPath = "$tsScriptDir\reconnect-boot.ps1"
                $tsCliPathEsc = $tsCliPath
@"
# Tailscale boot reconnect  -  runs as SYSTEM via Scheduled Task
`$logFile = "`$env:ProgramData\Tailscale\reconnect.log"
"`$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') ===== Boot reconnect START =====" | Add-Content `$logFile

# Wait up to 3 minutes for Tailscale service to be Running
for (`$i = 1; `$i -le 18; `$i++) {
    Start-Sleep -Seconds 10
    `$svc = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1
    "`$(Get-Date -f 'HH:mm:ss') Attempt `$i - Service: `$(`$svc.Status)" | Add-Content `$logFile
    if (`$svc -and `$svc.Status -eq 'Running') { break }
    if (`$i -eq 18) {
        # Last resort: try to start service
        Start-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

# Try without auth key first  -  --unattended is CRITICAL for headless reconnect
`$r1 = & "$tsCliPathEsc" up --unattended --accept-routes --accept-dns 2>&1 | Out-String
"`$(Get-Date -f 'HH:mm:ss') tailscale up result: `$r1" | Add-Content `$logFile

# If failed and auth key exists, retry with auth key
if (`$LASTEXITCODE -ne 0 -or `$r1 -match 'failed|error|unauthorized|Logged out') {
    `$keyFile = "`$env:ProgramData\Tailscale\auth.key"
    if (Test-Path `$keyFile) {
        `$key = (Get-Content `$keyFile -Raw).Trim()
        `$r2 = & "$tsCliPathEsc" up --unattended --authkey=`$key --accept-routes --accept-dns 2>&1 | Out-String
        "`$(Get-Date -f 'HH:mm:ss') tailscale up with key result: `$r2" | Add-Content `$logFile
    }
}
"`$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') ===== Boot reconnect END =====" | Add-Content `$logFile
"@ | Set-Content -Path $tsScriptPath -Encoding UTF8 -Force
                Write-Output-Box "[OK] Reconnect script written to $tsScriptPath"

                # 4. Register Scheduled Task  -  trigger: AtStartup + also on event 10000 (network connected)
                $tsTaskName = "TailscaleAutoConnect"
                Unregister-ScheduledTask -TaskName $tsTaskName -Confirm:$false -ErrorAction SilentlyContinue

                $tsTaskAction    = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tsScriptPath`""

                # Two triggers: boot + network-connected event (ensures reconnect even if boot trigger missed)
                $tsTriggerBoot = New-ScheduledTaskTrigger -AtStartup
                $tsTriggerNet  = New-ScheduledTaskTrigger -AtLogOn   # fires when any user logs on (extra safety net)

                $tsTaskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                $tsTaskSettings  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
                    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2) `
                    -MultipleInstances IgnoreNew

                Register-ScheduledTask -TaskName $tsTaskName `
                    -Action $tsTaskAction `
                    -Trigger @($tsTriggerBoot, $tsTriggerNet) `
                    -Principal $tsTaskPrincipal `
                    -Settings $tsTaskSettings `
                    -Description "Auto-connect Tailscale VPN at boot without requiring user login" `
                    -Force | Out-Null

                # Run the task immediately to confirm it works
                Start-ScheduledTask -TaskName $tsTaskName -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] Scheduled Task '$tsTaskName' created and started (boot + logon triggers)"
                Write-Output-Box "[OK] Diagnostic log: $tsScriptDir\reconnect.log"
                Write-Output-Box "[OK] Tailscale will auto-connect on every restart (no login required)"
            }
            catch {
                Write-Output-Box "[WARNING] Auto-start config: $($_.Exception.Message)"
            }

            # TS-STEP 7: Get Tailscale IP
            Write-Output-Box ""
            Write-Output-Box "[7/7] Getting Tailscale IP address..."

            $tsIP = $null
            for ($tsAttempt = 1; $tsAttempt -le 12; $tsAttempt++) {
                Write-Output-Box "[INFO] Attempt $tsAttempt/12..."
                try {
                    $tsIpOut = & $tsCliPath ip -4 2>&1 | Out-String
                    if ($tsIpOut -match '(\d+\.\d+\.\d+\.\d+)') {
                        $tsIP = $Matches[1]
                        Write-Output-Box "[OK] Tailscale IP: $tsIP"
                        break
                    }
                }
                catch { }
                Start-Sleep -Seconds 3
            }

            if ($null -eq $tsIP) {
                Write-Output-Box "[WARNING] Could not detect Tailscale IP automatically"
                Write-Output-Box "[INFO] Check Tailscale Admin Console: https://login.tailscale.com/admin/machines"
            } else {
                # Test RDP on LOCALHOST first (reliable) then via Tailscale IP
                Write-Output-Box ""
                Write-Output-Box ">>> TESTING RDP CONNECTION <<<"
                # Localhost test = definitive: is RDP actually listening?
                $tsRdpLocal  = Test-RDPPort -IPAddress "127.0.0.1" -Port $RdpPort -TimeoutSeconds 3
                $tsRdpReady  = $false
                if ($tsRdpLocal) {
                    Write-Output-Box "[OK] RDP port $RdpPort is LISTENING locally"
                    # Also probe via Tailscale IP (confirms routing is working)
                    for ($i = 1; $i -le 5; $i++) {
                        Write-Output-Box "[INFO] Attempt $i/5..."
                        $tsRdpReady = Test-RDPPort -IPAddress $tsIP -Port $RdpPort -TimeoutSeconds 3
                        if ($tsRdpReady) { Write-Output-Box "[OK] RDP port is OPEN via Tailscale IP!"; break }
                        Start-Sleep -Seconds 2
                    }
                    if (-not $tsRdpReady) {
                        Write-Output-Box "[WARNING] RDP listens locally but Tailscale IP test failed"
                        Write-Output-Box "[INFO] Check: device approved in Tailscale Admin, firewall allows port $RdpPort"
                        $tsRdpReady = $true  # local is listening = usable after Tailscale propagates
                    }
                } else {
                    Write-Output-Box "[WARNING] RDP port $RdpPort is NOT listening on this machine"
                    Write-Output-Box "[INFO] A machine restart is required for RDP listener to start"
                }
                if ($tsRdpReady) { Write-Output-Box "[INFO] RDP reachable via Tailscale" }
            }

            # Authoritative status: the summary must reflect the real listener state,
            # never an earlier optimistic flag. Runs even when no Tailscale IP was found.
            $tsRdpWorking = Test-RdpListener -Port $RdpPort
            if ($tsRdpWorking -and $tsNeedsAutoRestart) {
                # Listener bound late - the reboot is no longer needed.
                Write-Output-Box "[OK] Port $RdpPort bound before finishing - restart cancelled"
                $tsNeedsAutoRestart = $false
            }

            # Final summary – Tailscale
            Write-Output-Box ""
            Write-Output-Box "==================================================="
            Write-Output-Box ">>> CONNECTION INFORMATION (TAILSCALE) <<<"
            Write-Output-Box "==================================================="
            if ($tsIP) { Write-Output-Box "Tailscale IP : $tsIP" } else { Write-Output-Box "Tailscale IP : (Check Tailscale Admin Console)" }
            Write-Output-Box "RDP Port     : $RdpPort"
            Write-Output-Box "RDP Status   : $(if ($tsRdpWorking) { 'READY' } else { 'REQUIRES RESTART' })"
            Write-Output-Box "--- Users Created ($($userList.Count)) ---"
            foreach ($u in $userList) { Write-Output-Box "  Username: $($u.Username)  |  Password: $($u.Password)" }
            Write-Output-Box "==================================================="
            Write-Output-Box ""
            Write-Output-Box "[DONE] NOVIVO Remote Desktop setup completed!"
            Write-Output-Box ""
            Write-Output-Box "=== HOW TO CONNECT FROM ANOTHER MACHINE ==="
            Write-Output-Box ""
            Write-Output-Box "ON THE CLIENT MACHINE (your laptop / PC):"
            Write-Output-Box "  1. Install Tailscale: https://tailscale.com/download/windows"
            Write-Output-Box "  2. Sign in with THE SAME account used here"
            Write-Output-Box "  3. Confirm this server appears at: https://login.tailscale.com/admin/machines"
            Write-Output-Box "  4. Press Win+R, type: mstsc  -> click OK"
            Write-Output-Box "  5. Computer: ${tsIP}:${RdpPort}"
            Write-Output-Box "  6. Username: (see below)  Password: (see below)"
            Write-Output-Box ""
            Write-Output-Box "NEXT STEPS:"
            Write-Output-Box "1. Open Tailscale Admin: https://login.tailscale.com/admin/machines"
            Write-Output-Box "2. Confirm this device appears in your tailnet"
            Write-Output-Box "3. Connect via RDP: mstsc /v:${tsIP}:${RdpPort}"
            if ($tsNeedsAutoRestart) {
                Write-Output-Box ""
                Write-Output-Box "!!! AUTO-RESTART IN 30 SECONDS !!!"
                Write-Output-Box "[INFO] To cancel the restart, run in a terminal:  shutdown /a"
                Write-Output-Box "[INFO] RDP listener cannot start on this Windows edition without a clean boot"
                Write-Output-Box "[INFO] Everything is configured. After restart Tailscale will reconnect automatically."
                Write-Output-Box "[INFO] Wait ~2-3 minutes after restart, then connect: mstsc /v:${tsIP}:${RdpPort}"
                Write-Output-Box ""
                try {
                    & shutdown.exe /r /t 30 /c "NOVIVO: activating RDP" 2>&1 | Out-Null
                    Write-Output-Box "[OK] Restart scheduled (30s). App will close shortly."
                } catch {
                    Write-Output-Box "[WARNING] Could not schedule restart: $($_.Exception.Message)"
                    Write-Output-Box "[INFO] Please run manually: shutdown /r /t 0"
                }
            } elseif (-not $tsRdpWorking) {
                Write-Output-Box ""
                Write-Output-Box "[WARNING] RDP port $RdpPort is not yet listening"
                Write-Output-Box "[INFO] A manual machine restart is required for RDP to work on this Windows edition"
                Write-Output-Box "[INFO] After restarting, wait ~2 minutes then connect: mstsc /v:${tsIP}:${RdpPort}"
            }
            return   # <-- end of Tailscale branch
        }
        # ====================================================================
        #  END TAILSCALE BRANCH
        # ====================================================================

        Write-Output-Box "==================================================="
        Write-Output-Box ">>> NOVIVO REMOTE DESKTOP - ZEROTIER SETUP <<<"
        Write-Output-Box "==================================================="
        Write-Output-Box ""
        
        # STEP 1: Download ZeroTier
        Write-Output-Box "[1/7] Downloading ZeroTier One..."
        $installerPath = "$env:TEMP\ZeroTierOne.msi"
        
        # Enable all TLS protocols for maximum compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
        # Certificate validation stays ON - see the Tailscale branch for why.
        
        $downloadSuccess = $false
        $downloadUrls = @(
            "https://download.zerotier.com/dist/ZeroTier One.msi",
            "https://download.zerotier.com/RELEASES/1.14.0/dist/ZeroTier One.msi"
        )
        
        foreach ($downloadUrl in $downloadUrls) {
            try {
                Write-Output-Box "Trying: $downloadUrl"
                
                # Method 1: Try WebClient (more reliable)
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($downloadUrl, $installerPath)
                
                if (Test-Path $installerPath) {
                    $fileSize = (Get-Item $installerPath).Length
                    if ($fileSize -gt 1MB) {
                        Write-Output-Box "[OK] Downloaded successfully ($([math]::Round($fileSize/1MB,2)) MB)"
                        $downloadSuccess = $true
                        break
                    }
                }
            }
            catch {
                Write-Output-Box "Failed: $($_.Exception.Message)"
                # Try Method 2: Invoke-WebRequest
                try {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 60
                    if (Test-Path $installerPath) {
                        Write-Output-Box "[OK] Downloaded successfully (fallback method)"
                        $downloadSuccess = $true
                        break
                    }
                }
                catch {
                    continue
                }
            }
        }
        
        if (-not $downloadSuccess) {
            Write-Output-Box "[ERROR] All download methods failed."
            Write-Output-Box "[INFO] Check the internet connection. If this network inspects TLS traffic,"
            Write-Output-Box "[INFO] its root certificate must be trusted by Windows, or install ZeroTier manually"
            Write-Output-Box "[INFO] from https://www.zerotier.com/download/ and run this setup again."
            return
        }
        
        # STEP 2: Install ZeroTier
        Write-Output-Box ""
        Write-Output-Box "[2/7] Installing ZeroTier One..."
        try {
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn /norestart" -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-Output-Box "[OK] Installation completed"
                Start-Sleep -Seconds 3
            }
            else {
                Write-Output-Box "[ERROR] Installation failed with code: $($process.ExitCode)"
                return
            }
        }
        catch {
            Write-Output-Box "[ERROR] $($_.Exception.Message)"
            return
        }
        
        # Find ZeroTier CLI
        $ztCliPath = $null
        $possiblePaths = @(
            "$env:ProgramFiles\ZeroTier\One\zerotier-one_x64.exe",
            "$env:ProgramFiles\ZeroTier\One\zerotier-one.exe",
            "C:\Program Files (x86)\ZeroTier\One\zerotier-one.exe",
            "C:\ProgramData\ZeroTier\One\zerotier-one.exe"
        )
        foreach ($p in $possiblePaths) {
            if (Test-Path $p) { $ztCliPath = $p; break }
        }
        if (-not $ztCliPath) {
            $ztFound = Get-ChildItem "C:\Program Files*" -Filter "zerotier-one*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ztFound) { $ztCliPath = $ztFound.FullName }
        }
        if (-not $ztCliPath) {
            Write-Output-Box "[ERROR] ZeroTier executable not found after installation"
            return
        }
        Write-Output-Box "[INFO] ZeroTier path: $ztCliPath"
        
        # STEP 3: Start ZeroTier service
        Write-Output-Box ""
        Write-Output-Box "[3/7] Starting ZeroTier service..."
        try {
            Start-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            $ztSvc = Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
            if ($ztSvc -and $ztSvc.Status -eq "Running") {
                Write-Output-Box "[OK] ZeroTier service is running"
            } else {
                Write-Output-Box "[WARNING] Service may not be running yet, continuing..."
            }
        }
        catch {
            Write-Output-Box "[WARNING] $($_.Exception.Message)"
        }
        
        # STEP 4: Join ZeroTier network
        Write-Output-Box ""
        Write-Output-Box "[4/7] Joining ZeroTier network: $networkID"
        try {
            $joinResult = & $ztCliPath "-q" "join" $networkID 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $joinResult -match 'error|invalid|failed') {
                Write-Output-Box "[ERROR] Join did NOT succeed (exit code $LASTEXITCODE): $($joinResult.Trim())"
                Write-Output-Box "[INFO] Check the Network ID (16 hex characters) and that the ZeroTier service is running."
            } else {
                Write-Output-Box "[OK] Join command executed: $joinResult"
            }
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Output-Box "[ERROR] Failed to join network: $($_.Exception.Message)"
            return
        }
        
        # STEP 5: Enable RDP  
        Write-Output-Box ""
        Write-Output-Box "[5/7] Enabling Remote Desktop..."
        
        try {
            & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
            & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f 2>&1 | Out-Null
            Write-Output-Box "[OK] Core RDP settings applied via reg.exe"
        }
        catch {
            Write-Output-Box "[WARNING] reg.exe failed, using PowerShell fallback"
        }
        
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
        
        $regPaths = @(
            @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fDenyTSConnections"; Value=0},
            @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fAllowToGetHelp"; Value=1},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name="AllowTSConnections"; Value=1},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="PortNumber"; Value=$RdpPort; Type="DWord"},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="SecurityLayer"; Value=0},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="UserAuthentication"; Value=0},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="fEnableWinStation"; Value=1},
            @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name="LocalAccountTokenFilterPolicy"; Value=1}
        )
        foreach ($reg in $regPaths) {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            $regType = if ($reg.Type) { $reg.Type } else { "DWord" }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $regType -Force
        }
        Write-Output-Box "[OK] RDP registry fully configured"
        
        # Firewall
        try {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            $fwNameZT = "RDP-ZeroTier-$RdpPort"
            $existingRule = Get-NetFirewallRule -DisplayName $fwNameZT -ErrorAction SilentlyContinue
            if ($existingRule) { Remove-NetFirewallRule -DisplayName $fwNameZT -ErrorAction SilentlyContinue }
            New-NetFirewallRule -DisplayName $fwNameZT -Direction Inbound -Protocol TCP -LocalPort $RdpPort -Action Allow -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
            & netsh advfirewall firewall add rule name="RDP-ZeroTier-Netsh" dir=in action=allow protocol=TCP localport=$RdpPort 2>&1 | Out-Null
            Write-Output-Box "[OK] Firewall rules configured (3 methods)"
        }
        catch {
            Write-Output-Box "[WARNING] Firewall: $($_.Exception.Message)"
        }

        # Enable RDP via WMI  -  most reliable method on Win11
        try {
            $wmiTS = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root/cimv2/TerminalServices -ErrorAction SilentlyContinue
            if ($wmiTS) {
                # Single-arg works on all editions including Win10 Pro for Workstations
                try { $wmiTS.SetAllowTSConnections(1) | Out-Null }
                catch { $wmiTS.SetAllowTSConnections(1, 0) | Out-Null }
                Write-Output-Box "[OK] RDP enabled via WMI (AllowTSConnections)"
            }
        } catch { Write-Output-Box "[INFO] WMI enable: $($_.Exception.Message)" }

        # Windows Home ships no RDP host - install the support stack and verify
        # it actually took (see Install-HomeRdpSupport).
        try {
            if ($osInfo.IsHome) {
                [void](Install-HomeRdpSupport -Port $RdpPort)
            } else {
                Write-Output-Box "[INFO] Windows edition: $($osInfo.Caption) - native RDP host available"
            }
        } catch { Write-Output-Box "[WARNING] Home RDP support: $($_.Exception.Message)" }

        # Configure user accounts
        Write-Output-Box ""
        Write-Output-Box "[5b/7] Configuring $($userList.Count) user account(s)..."
        foreach ($userEntry in $userList) {
            $uname2 = $userEntry.Username
            $upass2 = $userEntry.Password
            Write-Output-Box "  [USER] >>> $uname2 <<<"
            try {
                $isMsAcc = $false
                try {
                    $lu = Get-LocalUser -Name $uname2 -ErrorAction SilentlyContinue
                    if ($lu -and "$($lu.PrincipalSource)" -eq 'MicrosoftAccount') { $isMsAcc = $true }
                } catch {}

                if ($isMsAcc) {
                    Write-Output-Box "[INFO] Microsoft account - password change skipped"
                    Write-Output-Box "[INFO] Use your Microsoft account password for RDP"
                } else {
                    $ztNetChk = & net user $uname2 2>&1
                    $ztUsrEx  = ($LASTEXITCODE -eq 0)
                    if (-not $ztUsrEx) {
                        $ztRes = & net user $uname2 $upass2 /add /passwordchg:no /expires:never /comment:"Created by NOVIVO Remote Desktop" 2>&1
                        $ztResStr = $ztRes | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            Write-Output-Box "[OK] User created: $uname2"
                            & wmic useraccount where "name='$uname2'" set PasswordExpires=False 2>&1 | Out-Null
                        } elseif ($ztResStr -match '8646|not authoritative|online provider') {
                            Write-Output-Box "[INFO] Microsoft account - password change skipped"
                        } else { throw "Failed to create user: $ztResStr" }
                    } else {
                        $ztRes2 = & net user $uname2 $upass2 2>&1
                        $ztResStr2 = $ztRes2 | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            Write-Output-Box "[OK] Password updated for: $uname2"
                            & wmic useraccount where "name='$uname2'" set PasswordExpires=False 2>&1 | Out-Null
                        } elseif ($ztResStr2 -match '8646|not authoritative|online provider') {
                            Write-Output-Box "[INFO] Microsoft account - password change skipped"
                        } else { throw "Failed to update password: $ztResStr2" }
                    }
                }
                $ztRdpGrpName = 'Remote Desktop Users'
                try {
                    $ztRdpSid  = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-555'
                    $ztRdpNT   = $ztRdpSid.Translate([System.Security.Principal.NTAccount]).Value
                    $ztParts   = $ztRdpNT.Split('\\'.ToCharArray())
                    $ztRdpGrpName = $ztParts[$ztParts.Length - 1]
                } catch { }
                $addAdm = & net localgroup Administrators $uname2 /add 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to Administrators" }
                else { Write-Output-Box "[INFO] Administrators: $addAdm" }
                $ztGrpExists = Get-LocalGroup -SID "S-1-5-32-555" -ErrorAction SilentlyContinue
                if (-not $ztGrpExists) {
                    try {
                        New-LocalGroup -Name $ztRdpGrpName -Description "Members in this group are granted the right to logon remotely" -ErrorAction SilentlyContinue | Out-Null
                        Write-Output-Box "[OK] Created '$ztRdpGrpName' group"
                    } catch {}
                }
                try {
                    Add-LocalGroupMember -SID "S-1-5-32-555" -Member $uname2 -ErrorAction Stop
                    Write-Output-Box "[OK] Added to $ztRdpGrpName"
                } catch {
                    if ($_.Exception.Message -match 'already.*member|member.*already') {
                        Write-Output-Box "[INFO] Already in $ztRdpGrpName"
                    } else {
                        $addRdp = & net localgroup $ztRdpGrpName $uname2 /add 2>&1
                        if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to $ztRdpGrpName" }
                        else { Write-Output-Box "[INFO] RDP Users: $addRdp" }
                    }
                }
            }
            catch {
                Write-Output-Box "[ERROR] User config failed for '$uname2': $($_.Exception.Message)"
                return
            }
        }
        
        # STEP 6: Restart RDP Services
        Write-Output-Box ""
        Write-Output-Box "[6/7] Restarting RDP services..."
        try {
            Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            
            & sc.exe config TermService  start= auto 2>&1 | Out-Null
            & sc.exe config SessionEnv   start= auto 2>&1 | Out-Null
            & sc.exe config UmRdpService start= auto 2>&1 | Out-Null
            
            Start-Service -Name "SessionEnv"  -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Start-Service -Name "TermService" -ErrorAction Stop
            Start-Sleep -Seconds 10
            Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
            
            $svcStatus = (Get-Service -Name "TermService").Status
            if ($svcStatus -eq "Running") {
                Write-Output-Box "[OK] TermService is RUNNING"
                $rdpWorking = $true
            } else {
                Write-Output-Box "[WARNING] TermService status: $svcStatus"
            }
            
            Start-Sleep -Seconds 5
            $portListening = Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue
            
            if (-not $portListening) {
                Write-Output-Box "[WARNING] Port $RdpPort not listening, trying emergency fixes..."
                
                try {
                    # EMERGENCY FIX SEQUENCE
                    Write-Output-Box "[INFO] Emergency: Force killing all RDP services..."
                    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
                    
                    # Kill stuck processes
                    Get-Process | Where-Object { $_.ProcessName -like "*svchost*" } | ForEach-Object {
                        try {
                            if ($_.Modules.ModuleName -contains "termsrv.dll") {
                                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                            }
                        }
                        catch {}
                    }
                    
                    Start-Sleep -Seconds 5
                    Write-Output-Box "[OK] Services stopped, processes killed"
                    
                    # Restart in correct order
                    Write-Output-Box "[INFO] Emergency: Restarting services in order..."
                    Start-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 10
                    Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 5
                    
                    Write-Output-Box "[OK] Emergency restart completed"
                    
                    # Re-check port
                    Start-Sleep -Seconds 3
                    $portCheck = Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue
                    
                    if ($portCheck) {
                        Write-Output-Box "[SUCCESS] Port $RdpPort is NOW LISTENING!"
                        Write-Output-Box "[INFO] Emergency fix WORKED - RDP is ready!"
                        $rdpWorking = $true
                    }
                    else {
                        # LAST RESORT: Try to rebuild RDP-Tcp listener via registry
                        Write-Output-Box ""
                        Write-Output-Box "[INFO] Last attempt: Rebuilding RDP-Tcp listener..."
                        
                        try {
                            # Force rebind by toggling fEnableWinStation
                            $rdpTcpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
                            Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 0 -Force
                            Start-Sleep -Seconds 2
                            Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 1 -Force
                            
                            # Restart TermService one more time
                            Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 10
                            
                            # Final check
                            $portCheck = Get-NetTCPConnection -LocalPort $RdpPort -State Listen -ErrorAction SilentlyContinue
                            if ($portCheck) {
                                Write-Output-Box "[SUCCESS] Listener rebuild WORKED! Port $RdpPort is now listening!"
                                $rdpWorking = $true
                            }
                            else {
                                Write-Output-Box "[ERROR] Listener rebuild failed"
                                $rdpWorking = $false
                            }
                        }
                        catch {
                            Write-Output-Box "[WARNING] Rebuild attempt failed: $($_.Exception.Message)"
                            $rdpWorking = $false
                        }
                        
                        if (-not $rdpWorking) {
                            Write-Output-Box ""
                            Write-Output-Box "=== MACHINE RESTART REQUIRED ==="
                            Write-Output-Box "[INFO] This Windows requires restart for RDP listener"
                            Write-Output-Box "[INFO] Registry is configured correctly"
                            Write-Output-Box "[INFO] After restart, RDP will work automatically"
                            Write-Output-Box ""
                            Write-Output-Box "Run this command to schedule safe restart:"
                            Write-Output-Box "  powershell -File .\Safe-Restart.ps1"
                            Write-Output-Box ""
                            Write-Output-Box "Or restart now:"
                            Write-Output-Box "  Restart-Computer"
                            Write-Output-Box ""
                        }
                    }
                }
                catch {
                    Write-Output-Box "[ERROR] Emergency fix failed: $($_.Exception.Message)"
                    Write-Output-Box "[INFO] Please restart machine manually"
                    $rdpWorking = $false
                }
            }
            else {
                Write-Output-Box "[SUCCESS] Port $RdpPort is LISTENING - RDP is READY!"
                $rdpWorking = $true
            }
        }
        catch {
            Write-Output-Box "[ERROR] Service restart failed: $($_.Exception.Message)"
            $rdpWorking = $false
        }
        
        # STEP 7: Get ZeroTier IP and Test
        Write-Output-Box ""
        Write-Output-Box "[7/7] Getting ZeroTier IP address..."
        
        Start-Sleep -Seconds 5
        
        $ztIP = $null
        $maxAttempts = 10
        $attempt = 0
        
        while ($attempt -lt $maxAttempts -and $null -eq $ztIP) {
            $attempt++
            Write-Output-Box "[INFO] Attempt $attempt/$maxAttempts..."
            
            try {
                $listResult = & $ztCliPath "-q" "listnetworks" 2>&1 | Out-String
                
                if ($listResult -match "(\d+\.\d+\.\d+\.\d+)") {
                    $ztIP = $Matches[1]
                    Write-Output-Box "[OK] ZeroTier IP detected: $ztIP"
                    break
                }
            }
            catch {
                Write-Output-Box "[WARNING] Retry in 3 seconds..."
            }
            
            Start-Sleep -Seconds 3
        }
        
        if ($null -eq $ztIP) {
            Write-Output-Box "[WARNING] Could not detect ZeroTier IP automatically"
            Write-Output-Box "[INFO] Please check ZeroTier Central to authorize this device"
        }
        else {
            # Test RDP connectivity
            Write-Output-Box ""
            Write-Output-Box ">>> TESTING RDP CONNECTION <<<"
            Write-Output-Box "[INFO] Testing RDP port $RdpPort..."
            
            # Try multiple times to allow services to fully initialize
            $rdpReady = $false
            for ($i = 1; $i -le 5; $i++) {
                Write-Output-Box "[INFO] Test attempt $i/5..."
                $rdpReady = Test-RDPPort -IPAddress $ztIP -Port $RdpPort -TimeoutSeconds 3
                if ($rdpReady) {
                    Write-Output-Box "[OK] RDP port is OPEN and READY!"
                    break
                }

                if ($i -lt 5) {
                    Write-Output-Box "[INFO] Port not ready yet, waiting 2 seconds..."
                    Start-Sleep -Seconds 2
                }
            }

            if (-not $rdpReady) {
                Write-Output-Box "[WARNING] RDP port test failed"
                Write-Output-Box "[INFO] RDP may need a few more seconds to initialize"
                Write-Output-Box "[INFO] Or firewall may be blocking connections"
            }
            if ($rdpReady) { Write-Output-Box "[INFO] RDP reachable via ZeroTier" }
        }

        # Authoritative status: never let a probe upgrade a conclusion the
        # emergency-fix path already reached. Runs even when no ZeroTier IP was found.
        $rdpWorking = Test-RdpListener -Port $RdpPort
        if ($rdpWorking -and $ztIP -and -not $rdpReady) {
            Write-Output-Box "[INFO] Listener is up locally but not reachable over ZeroTier yet."
            Write-Output-Box "[INFO] Authorize this device in ZeroTier Central, then allow ~1 minute to propagate."
        }
        
        # Final Summary
        Write-Output-Box ""
        Write-Output-Box "==================================================="  
        Write-Output-Box ">>> CONNECTION INFORMATION (ZEROTIER) <<<"
        Write-Output-Box "==================================================="  
        if ($null -ne $ztIP) {
            Write-Output-Box "IP Address  : $ztIP"
        }
        else {
            Write-Output-Box "IP Address  : (Check ZeroTier Central)"
        }
        Write-Output-Box "RDP Port    : $RdpPort"
        Write-Output-Box "--- Users Created ($($userList.Count)) ---"
        foreach ($u in $userList) { Write-Output-Box "  Username: $($u.Username)  |  Password: $($u.Password)" }

        # Show RDP status
        if ($rdpWorking) {
            Write-Output-Box "RDP Status  : READY (No restart needed)"
        }
        else {
            Write-Output-Box "RDP Status  : REQUIRES RESTART"
        }

        Write-Output-Box "==================================================="  
        Write-Output-Box ""
        Write-Output-Box "[DONE] NOVIVO Remote Desktop setup completed!"
        Write-Output-Box ""

        # Dynamic notes based on RDP status
        if ($rdpWorking) {
            Write-Output-Box "IMPORTANT NOTES:"
            Write-Output-Box "1. Authorize this device in ZeroTier Central"     
            Write-Output-Box "2. Wait 10-30 seconds for RDP to fully initialize"
            Write-Output-Box "3. Use Remote Desktop Connection (mstsc.exe)"     
            Write-Output-Box "4. RDP is ready - NO MACHINE RESTART NEEDED!"     
        }
        else {
            Write-Output-Box "!!! MACHINE RESTART REQUIRED !!!"
            Write-Output-Box "1. RDP listener could not be created without restart"
            Write-Output-Box "2. Registry is configured correctly"
            Write-Output-Box "3. After restart, RDP will work automatically"
            Write-Output-Box "4. Authorize device in ZeroTier Central"
            Write-Output-Box ""
            Write-Output-Box "To schedule safe restart (5 min delay):"
            Write-Output-Box "  powershell -File .\Safe-Restart.ps1"
            Write-Output-Box ""
            Write-Output-Box "To restart now:"
            Write-Output-Box "  Restart-Computer"
        }

    }
    catch {
        Write-Output-Box ""
        Write-Output-Box "[CRITICAL ERROR] $($_.Exception.Message)"
        Write-Output-Box ""
        Write-Output-Box "Stack Trace:"
        Write-Output-Box $_.ScriptStackTrace
    }
    finally {
    }
}
catch {
    Write-Output-Box ""
    Write-Output-Box "[CRITICAL ERROR] $($_.Exception.Message)"
}
finally {
    # ── Restore sleep settings ─────────────────────────────────────────────
    if ($_powerLoaded) {
        [void][Win32.NovivoPower]::SetThreadExecutionState([uint32]2147483648)  # ES_CONTINUOUS = reset
    }
    Write-Output-Box "[INFO] Sleep settings restored"
}
