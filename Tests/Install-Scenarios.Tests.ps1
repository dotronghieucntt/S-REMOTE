# ============================================================================
#  Install-Scenarios.Tests.ps1
# ----------------------------------------------------------------------------
#  The scenario matrix. Each row is a simulated machine + the decision the
#  installer should reach on it. Runs the REAL functions from NOVIVO-Backend.ps1
#  against fakes (see NovivoTest.Engine.ps1) so a fresh-install regression is
#  caught here instead of on a customer's PC.
#
#  Run it:   powershell -ExecutionPolicy Bypass -File Tests\Run-Scenarios.ps1
# ============================================================================

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$project  = Split-Path -Parent $here
. (Join-Path $here 'NovivoTest.Engine.ps1')

$backend = Join-Path $project 'NOVIVO-Backend.ps1'
$script:Sandbox = New-NovivoSandbox -BackendPath $backend -Functions @(
    'Get-NovivoResultState',
    'Test-TailscaleBackendReady',
    'Test-TailscaleLoggedIn',
    'Test-NovivoOSSupport',
    'Get-NovivoOSInfo',
    'Test-RdpListener',
    'Test-RdpWrapActive',
    'Set-NovivoBootService',
    'Get-NovivoPowerSchemes',
    'Get-NovivoPowerValue',
    'Set-NovivoNoSleep',
    'Get-NovivoKeepAwakeScript'
)

# ── shorthands ───────────────────────────────────────────────────────────────
function OSInfo {
    # NB: no param named $Home — that shadows the read-only automatic $HOME.
    param([int]$Build,[string]$Caption='Windows',[bool]$HomeEdition=$false,[bool]$Server=$false,[bool]$SMode=$false,[bool]$x64=$true,[int]$UBR=0)
    [pscustomobject]@{ Build=$Build; UBR=$UBR; Caption=$Caption; IsHome=$HomeEdition; IsServer=$Server; IsSMode=$SMode; Is64Bit=$x64 }
}
function Should-Be { param($Actual,$Expected,[string]$What='value')
    if ("$Actual" -ne "$Expected") { throw "$What expected '$Expected' but got '$Actual'" } }

$CV = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$CI = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 1 — Get-NovivoResultState  (the honest-outcome fix)
#  A dead listener is never "success"; a live listener with no overlay IP means
#  the device still has to be authorised in the network console.
# ════════════════════════════════════════════════════════════════════════════
$resultCases = @(
    @{ n='listener up + overlay IP  => SUCCESS';        up=$true;  ip=$true;  restart=$false; want='SUCCESS' }
    @{ n='listener up + NO IP        => NEEDS_AUTH';     up=$true;  ip=$false; restart=$false; want='NEEDS_AUTH' }
    @{ n='listener down + restart    => NEEDS_RESTART';  up=$false; ip=$true;  restart=$true;  want='NEEDS_RESTART' }
    @{ n='listener down, no restart  => NEEDS_RESTART';  up=$false; ip=$false; restart=$false; want='NEEDS_RESTART' }
    @{ n='listener down but has IP   => NEEDS_RESTART';  up=$false; ip=$true;  restart=$false; want='NEEDS_RESTART' }
)
foreach ($c in $resultCases) {
    Invoke-NovivoScenario -Group 'ResultState' -Name $c.n -Machine @{} `
        -Act ([scriptblock]::Create("Get-NovivoResultState -ListenerUp `$$($c.up) -HasOverlayIP `$$($c.ip) -NeedsRestart `$$($c.restart)")) `
        -Assert ([scriptblock]::Create("param(`$a,`$log) Should-Be `$a '$($c.want)' 'state'"))
}

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 2 — Test-NovivoOSSupport  (preflight gate: may setup continue?)
# ════════════════════════════════════════════════════════════════════════════
$osSupportCases = @(
    @{ n='S mode blocks tailscale';            m='tailscale'; os=(OSInfo -Build 22000 -SMode $true);            want=$false }
    @{ n='S mode blocks zerotier';             m='zerotier';  os=(OSInfo -Build 22000 -SMode $true);            want=$false }
    @{ n='Win7 (7601) blocks tailscale';       m='tailscale'; os=(OSInfo -Build 7601  -Caption 'Windows 7');    want=$false }
    @{ n='Win8.1 (9600) blocks tailscale';     m='tailscale'; os=(OSInfo -Build 9600);                          want=$false }
    @{ n='Win10 1803 (17134) blocks tailscale';m='tailscale'; os=(OSInfo -Build 17134);                         want=$false }
    @{ n='Win10 1809 (17763) allows tailscale';m='tailscale'; os=(OSInfo -Build 17763);                         want=$true  }
    @{ n='Win11 (22000) allows tailscale';     m='tailscale'; os=(OSInfo -Build 22000);                         want=$true  }
    @{ n='Win10 Home 19045 allows tailscale';  m='tailscale'; os=(OSInfo -Build 19045 -HomeEdition $true);             want=$true  }
    @{ n='Win7 allows zerotier (warns)';       m='zerotier';  os=(OSInfo -Build 7601  -Caption 'Windows 7');    want=$true  }
    @{ n='Win10 Pro allows zerotier';          m='zerotier';  os=(OSInfo -Build 19045);                         want=$true  }
    @{ n='Server 2019 allows tailscale';       m='tailscale'; os=(OSInfo -Build 17763 -Server $true);           want=$true  }
)
foreach ($c in $osSupportCases) {
    Invoke-NovivoScenario -Group 'OSSupport' -Name $c.n -Machine @{ OSInfoArg=$c.os; MethodArg=$c.m } `
        -Act { Test-NovivoOSSupport -Method $global:__N.MethodArg -OSInfo $global:__N.OSInfoArg } `
        -Assert ([scriptblock]::Create("param(`$a,`$log) Should-Be `$a `$$($c.want) 'supported'"))
}

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 3 — Get-NovivoOSInfo  (edition/build/S-mode detection from the machine)
# ════════════════════════════════════════════════════════════════════════════
# 3a. Home SKU (101 = Core Single Language) is detected as Home.
Invoke-NovivoScenario -Group 'OSInfo' -Name 'SKU 101 => IsHome true' `
    -Machine @{ Reg=@{ "$CV|CurrentBuildNumber"=19045; "$CV|UBR"=3448 }; OS=(New-SimOS -Caption 'Windows 10 Home' -ProductType 1 -Sku 101) } `
    -Act { Get-NovivoOSInfo } `
    -Assert { param($a,$log) Should-Be $a.IsHome $true 'IsHome'; Should-Be $a.Build 19045 'Build'; Should-Be $a.IsServer $false 'IsServer' }

# 3b. Pro SKU (48) is not Home.
Invoke-NovivoScenario -Group 'OSInfo' -Name 'SKU 48 (Pro) => IsHome false' `
    -Machine @{ Reg=@{ "$CV|CurrentBuildNumber"=19045 }; OS=(New-SimOS -Caption 'Windows 10 Pro' -ProductType 1 -Sku 48) } `
    -Act { Get-NovivoOSInfo } `
    -Assert { param($a,$log) Should-Be $a.IsHome $false 'IsHome' }

# 3c. Caption fallback: SKU missing but caption says Home.
Invoke-NovivoScenario -Group 'OSInfo' -Name 'null SKU + "Home" caption => IsHome true' `
    -Machine @{ Reg=@{ "$CV|CurrentBuildNumber"=19045 }; OS=(New-SimOS -Caption 'Windows 10 Home Single Language' -ProductType 1 -Sku $null) } `
    -Act { Get-NovivoOSInfo } `
    -Assert { param($a,$log) Should-Be $a.IsHome $true 'IsHome' }

# 3d. Server product type.
Invoke-NovivoScenario -Group 'OSInfo' -Name 'ProductType 3 => IsServer true' `
    -Machine @{ Reg=@{ "$CV|CurrentBuildNumber"=17763 }; OS=(New-SimOS -Caption 'Windows Server 2019' -ProductType 3 -Sku 7) } `
    -Act { Get-NovivoOSInfo } `
    -Assert { param($a,$log) Should-Be $a.IsServer $true 'IsServer' }

# 3e. S mode flag.
Invoke-NovivoScenario -Group 'OSInfo' -Name 'SkuPolicyRequired=1 => IsSMode true' `
    -Machine @{ Reg=@{ "$CV|CurrentBuildNumber"=22000; "$CI|SkuPolicyRequired"=1 }; OS=(New-SimOS -Caption 'Windows 11 Home' -ProductType 1 -Sku 101) } `
    -Act { Get-NovivoOSInfo } `
    -Assert { param($a,$log) Should-Be $a.IsSMode $true 'IsSMode' }

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 4 — Test-RdpListener  (ownership-aware: a squatter is NOT success)
# ════════════════════════════════════════════════════════════════════════════
Invoke-NovivoScenario -Group 'Listener' -Name 'no listener => false' `
    -Machine @{ Listeners=@(); TermServicePid=444 } `
    -Act { Test-RdpListener -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a $false 'listening' }

Invoke-NovivoScenario -Group 'Listener' -Name 'owned by TermService => true' `
    -Machine @{ Listeners=@((New-SimListener -Port 3389 -ProcId 444)); TermServicePid=444 } `
    -Act { Test-RdpListener -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a $true 'listening' }

Invoke-NovivoScenario -Group 'Listener' -Name 'squatted by other PID => false' `
    -Machine @{ Listeners=@((New-SimListener -Port 3389 -ProcId 9999)); TermServicePid=444 } `
    -Act { Test-RdpListener -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a $false 'listening' }

Invoke-NovivoScenario -Group 'Listener' -Name 'listening but TermService PID unknown => true (best effort)' `
    -Machine @{ Listeners=@((New-SimListener -Port 3389 -ProcId 9999)); TermServicePid=$null } `
    -Act { Test-RdpListener -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a $true 'listening' }

Invoke-NovivoScenario -Group 'Listener' -Name 'custom port owned by TermService => true' `
    -Machine @{ Listeners=@((New-SimListener -Port 33890 -ProcId 444)); TermServicePid=444 } `
    -Act { Test-RdpListener -Port 33890 } `
    -Assert { param($a,$log) Should-Be $a $true 'listening' }

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 5 — Test-RdpWrapActive  ("installed" is not "working")
# ════════════════════════════════════════════════════════════════════════════
Invoke-NovivoScenario -Group 'RdpWrap' -Name 'wrapper loaded + listener => Ok, WrapperLoaded' `
    -Machine @{ Listeners=@((New-SimListener -Port 3389 -ProcId 444)); TermServicePid=444; TermServiceModules=@('ntdll.dll','rdpwrap.dll') } `
    -Act { Test-RdpWrapActive -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a.Ok $true 'Ok'; Should-Be $a.WrapperLoaded $true 'WrapperLoaded' }

Invoke-NovivoScenario -Group 'RdpWrap' -Name 'listener up but wrapper NOT loaded => Ok true, WrapperLoaded false' `
    -Machine @{ Listeners=@((New-SimListener -Port 3389 -ProcId 444)); TermServicePid=444; TermServiceModules=@('ntdll.dll') } `
    -Act { Test-RdpWrapActive -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a.Ok $true 'Ok'; Should-Be $a.WrapperLoaded $false 'WrapperLoaded' }

Invoke-NovivoScenario -Group 'RdpWrap' -Name 'no listener => Ok false' `
    -Machine @{ Listeners=@(); TermServicePid=444; TermServiceModules=@('rdpwrap.dll') } `
    -Act { Test-RdpWrapActive -Port 3389 } `
    -Assert { param($a,$log) Should-Be $a.Ok $false 'Ok' }

# ════════════════════════════════════════════════════════════════════════════
#  GROUP 6 — Tailscale login detection  ("cài xong không tự đăng nhập")
#  The installer must trust the real state, never the `up` exit code alone.
# ════════════════════════════════════════════════════════════════════════════
$tsLoggedInText  = "100.99.187.108   sam        aisamad.naga@  windows  -`n100.96.112.29    dell       aisamad.naga@  windows  active"
$tsNotReadyText  = "failed to connect to local Tailscale service; is Tailscale running?"
$tsLoggedOutText = "Logged out."
$tsStoppedText   = "Tailscale is stopped."
$tsNeedsLoginTxt = "To authenticate, visit:`n`n`thttps://login.tailscale.com/a/abc123`n`nLog in at: https://login.tailscale.com/a/abc123"

$tsBackendCases = @(
    @{ n='normal status => backend ready';           txt=$tsLoggedInText;  want=$true  }
    @{ n='"failed to connect" => backend NOT ready';  txt=$tsNotReadyText;  want=$false }
)
foreach ($c in $tsBackendCases) {
    Invoke-NovivoScenario -Group 'Tailscale' -Name $c.n -Machine @{ Txt=$c.txt } `
        -Act { Test-TailscaleBackendReady -StatusText $global:__N.Txt } `
        -Assert ([scriptblock]::Create("param(`$a,`$log) Should-Be `$a `$$($c.want) 'ready'"))
}

$tsLoginCases = @(
    @{ n='has 100.x IP => logged in';         txt=$tsLoggedInText;  want=$true  }
    @{ n='"Logged out." => NOT logged in';     txt=$tsLoggedOutText; want=$false }
    @{ n='backend not ready => NOT logged in'; txt=$tsNotReadyText;  want=$false }
    @{ n='"stopped" => NOT logged in';         txt=$tsStoppedText;   want=$false }
    @{ n='needs browser login => NOT logged in';txt=$tsNeedsLoginTxt;want=$false }
    @{ n='empty output => NOT logged in';      txt='';               want=$false }
)
foreach ($c in $tsLoginCases) {
    Invoke-NovivoScenario -Group 'Tailscale' -Name $c.n -Machine @{ Txt=$c.txt } `
        -Act { Test-TailscaleLoggedIn -StatusText $global:__N.Txt } `
        -Assert ([scriptblock]::Create("param(`$a,`$log) Should-Be `$a `$$($c.want) 'loggedIn'"))
}

# ============================================================================
#  GROUP 7 - Boot service (Tailscale must be up at the LOGIN SCREEN)
#  delayed-auto starts ~2 min after boot: the login screen came up unreachable.
# ============================================================================
function New-SimService { param([string]$Name,[string]$Mode='Auto',[bool]$Delayed=$true)
    [pscustomobject]@{ Name=$Name; StartMode=$Mode; DelayedAutoStart=$Delayed } }

Invoke-NovivoScenario -Group 'BootService' -Name 'delayed-auto Tailscale => plain Auto, read back' `
    -Machine @{ Services=@{ Tailscale=(New-SimService 'Tailscale' 'Auto' $true) } } `
    -Act { Set-NovivoBootService -Name 'Tailscale' } `
    -Assert { param($a,$log)
        Should-Be $a $true 'ok'
        $svc = $global:__N.Services['Tailscale']
        Should-Be $svc.StartMode 'Auto' 'StartMode'; Should-Be $svc.DelayedAutoStart $false 'DelayedAutoStart'
        Should-Be $global:__N.Reg['HKLM:\SYSTEM\CurrentControlSet\Services\Tailscale|DelayedAutostart'] 0 'DelayedAutostart reg'
        if (-not ($global:__N.ScCalls -contains 'config Tailscale start= auto')) { throw 'sc config start= auto not issued' }
        if ($global:__N.ScCalls | Where-Object { $_ -match 'delayed-auto' }) { throw 'delayed-auto issued' }
        if (-not ($global:__N.ScCalls | Where-Object { $_ -match '^failure Tailscale .*restart/5000' })) { throw 'recovery not set' }
        if (-not ($log | Where-Object { $_ -match '^\[OK\].*not delayed' })) { throw 'no OK line' } }

Invoke-NovivoScenario -Group 'BootService' -Name 'manual service => Auto' `
    -Machine @{ Services=@{ Tailscale=(New-SimService 'Tailscale' 'Manual' $false) } } `
    -Act { Set-NovivoBootService -Name 'Tailscale' } `
    -Assert { param($a,$log) Should-Be $a $true 'ok'; Should-Be $global:__N.Services['Tailscale'].StartMode 'Auto' 'StartMode' }

Invoke-NovivoScenario -Group 'BootService' -Name 'sc.exe changes nothing (policy) => NOT ok + warning' `
    -Machine @{ ScIgnored=$true; Services=@{ Tailscale=(New-SimService 'Tailscale' 'Auto' $true) } } `
    -Act { Set-NovivoBootService -Name 'Tailscale' } `
    -Assert { param($a,$log) Should-Be $a $false 'ok'
        if (-not ($log | Where-Object { $_ -match '^\[WARNING\].*delayed' })) { throw 'no delayed warning' } }

Invoke-NovivoScenario -Group 'BootService' -Name 'service missing => NOT ok + warning' `
    -Machine @{} `
    -Act { Set-NovivoBootService -Name 'Tailscale' } `
    -Assert { param($a,$log) Should-Be $a $false 'ok'
        if (-not ($log | Where-Object { $_ -match '^\[WARNING\].*read' })) { throw 'no warning' } }

# ============================================================================
#  GROUP 8 - Never sleep (every power plan, AC + battery, re-applied at boot)
# ============================================================================
$BAL = '381b4222-f694-41f0-9685-ff5bb260df2e'
$HIP = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$UNATTEND = '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'
$NETSTBY  = 'f15576e8-98b7-4186-b944-eafa664402d9'
function New-SimPower { param([string]$Lang='en',[bool]$Locked=$false)
    @{ Schemes=@($BAL,$HIP); Active=$BAL; V=@{}; Hibernate=$true; Locked=$Locked; Lang=$Lang } }
function PV { param($s,$sub,$set,$m) $global:__N.Power.V["$($s.ToLower())|$sub|$($set.ToLower())|$m"] }

foreach ($lang in 'en','vi') {
    Invoke-NovivoScenario -Group 'NoSleep' -Name "two power plans, $lang labels => never sleep everywhere" `
        -Machine @{ Power=(New-SimPower -Lang $lang) } `
        -Act { Set-NovivoNoSleep } `
        -Assert { param($a,$log)
            Should-Be $a $true 'ok'
            foreach ($s in $BAL,$HIP) {
                foreach ($m in 'AC','DC') {
                    Should-Be (PV $s 'SUB_SLEEP' 'STANDBYIDLE' $m)   0 "$s sleep $m"
                    Should-Be (PV $s 'SUB_SLEEP' 'HIBERNATEIDLE' $m) 0 "$s hibernate $m"
                    Should-Be (PV $s 'SUB_SLEEP' $UNATTEND $m)       0 "$s unattended $m"
                }
                Should-Be (PV $s 'SUB_BUTTONS' 'LIDACTION' 'AC') 0 "$s lid AC"
                if ($null -ne (PV $s 'SUB_BUTTONS' 'LIDACTION' 'DC')) { throw "$s lid on battery must be left alone" }
                Should-Be (PV $s 'SUB_NONE' $NETSTBY 'AC') 1 "$s network in standby"
            }
            Should-Be $global:__N.Power.Hibernate $false 'hibernate'
            Should-Be $global:__N.Reg['HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power|HiberbootEnabled'] 0 'fast startup'
            if (-not ($log | Where-Object { $_ -match '^\[OK\] Sleep turned off permanently \(2 power plan' })) { throw 'no OK line' } }
}

Invoke-NovivoScenario -Group 'NoSleep' -Name 'Group Policy ignores writes => NOT ok + warning' `
    -Machine @{ Power=(New-SimPower -Locked $true) } `
    -Act { Set-NovivoNoSleep } `
    -Assert { param($a,$log) Should-Be $a $false 'ok'
        if (-not ($log | Where-Object { $_ -match '^\[WARNING\].*AC=1800s DC=900s.*Group Policy' })) { throw "no warning: $($log -join ' | ')" } }

Invoke-NovivoScenario -Group 'NoSleep' -Name 'plan list: GUIDs only, de-duplicated, lower-case' `
    -Machine @{ Power=@{ Schemes=@($BAL.ToUpper(),$HIP,$HIP); Active=$HIP; V=@{}; Hibernate=$true; Locked=$false; Lang='vi' } } `
    -Act { ,@(Get-NovivoPowerSchemes) } `
    -Assert { param($a,$log) Should-Be ($a -join ',') "$BAL,$HIP" 'schemes' }

Invoke-NovivoScenario -Group 'NoSleep' -Name 'boot script: parses, carries the same functions, calls Set-NovivoNoSleep' `
    -Machine @{} `
    -Act { Get-NovivoKeepAwakeScript } `
    -Assert { param($a,$log)
        $tok=$null; $err=$null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($a, [ref]$tok, [ref]$err)
        if ($err -and $err.Count) { throw "parse: $($err[0].Message)" }
        $fns = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Name })
        foreach ($f in 'Write-Output-Box','Get-NovivoPowerSchemes','Get-NovivoPowerValue','Set-NovivoNoSleep') {
            if ($fns -notcontains $f) { throw "missing function $f" } }
        if ($a -notmatch '(?m)^\[void\]\(Set-NovivoNoSleep\)\s*$') { throw 'does not call Set-NovivoNoSleep' }
        if ($a -match 'tskey-') { throw 'secret in boot script' } }

# ============================================================================
#  GROUP 9 - Static wiring checks on the backend source
# ============================================================================
$bsrc = Get-Content $backend -Raw
Invoke-NovivoScenario -Group 'Static' -Name 'no service is set to delayed-auto' -Machine @{ Src=$bsrc } `
    -Act { $global:__N.Src } -Assert { param($a,$log) if ($a -match 'start=\s*delayed-auto') { throw 'delayed-auto still used' } }
Invoke-NovivoScenario -Group 'Static' -Name 'Tailscale service goes through Set-NovivoBootService' -Machine @{ Src=$bsrc } `
    -Act { $global:__N.Src } -Assert { param($a,$log) if ($a -notmatch 'Set-NovivoBootService -Name \$tsSvcName2') { throw 'not wired' } }
Invoke-NovivoScenario -Group 'Static' -Name 'install applies never-sleep + registers keep-awake task' -Machine @{ Src=$bsrc } `
    -Act { $global:__N.Src } -Assert { param($a,$log)
        if ($a -notmatch '(?m)^\[void\]\(Set-NovivoNoSleep\)') { throw 'Set-NovivoNoSleep not called at top level' }
        if ($a -notmatch '(?m)^Register-NovivoKeepAwakeTask') { throw 'keep-awake task not registered' } }
Invoke-NovivoScenario -Group 'Static' -Name 'logon autostart never targets the console CLI' -Machine @{ Src=$bsrc } `
    -Act { $global:__N.Src } -Assert { param($a,$log)
        # case-sensitive: the CLI path list (\Tailscale\tailscale.exe) is legitimate
        if ($a -cmatch '\\Tailscale\\Tailscale\.exe') { throw 'Startup shortcut still targets the old tray path (= the CLI)' }
        if ($a -match '\$tsRunExe') { throw 'Run key still targets the CLI' } }

# -- verdict ------------------------------------------------------------------
$failed = Write-NovivoSummary
exit $failed
