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
    'Test-RdpWrapActive'
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

# ── verdict ──────────────────────────────────────────────────────────────────
$failed = Write-NovivoSummary
exit $failed
