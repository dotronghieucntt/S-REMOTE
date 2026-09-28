# ============================================================================
#  NovivoTest.Engine.ps1  -  dependency-free scenario harness
# ----------------------------------------------------------------------------
#  Loads the real installer functions out of NOVIVO-Backend.ps1 WITHOUT running
#  the top-level install block, then runs them against simulated machines by
#  shadowing the Windows cmdlets they call (Get-CimInstance, Get-NetTCPConnection,
#  reg.exe, services, ...) with fakes driven from a per-scenario hashtable.
#
#  No Pester, no internet, no admin, nothing to install: `powershell -File`.
# ============================================================================

# NOTE: intentionally does NOT set Set-StrictMode / $ErrorActionPreference here.
# This file is dot-sourced, so those settings would leak into the caller's scope
# and can abort the runner silently. Each scenario's try/catch handles errors.

# --- The simulated machine for the scenario currently under test. ------------
#     Fakes below read from here. Reset by Invoke-NovivoScenario.
$global:__N = @{}

# --- Pull the named functions' source text out of a .ps1 via the AST. --------
#     Only real top-level functions are returned; code inside here-strings
#     (e.g. the generated repair script) is a string literal, never a function.
function Get-NovivoFunctionSource {
    param([string]$Path, [string[]]$Names)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) {
        throw "Parse errors in $Path : $(($errors | ForEach-Object { $_.Message }) -join '; ')"
    }
    $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $hit = $fns | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $hit) { throw "Function '$name' not found in $Path" }
        $out.Add($hit.Extent.Text)
    }
    return ($out -join "`n`n")
}

# --- Fakes for the Windows surface the installer touches. --------------------
#     Composed into the sandbox module ahead of the real functions so that
#     command resolution inside those functions binds to these.
$FakesSource = @'
function Write-Output-Box { param([string]$Message,[string]$Color="Lime"); $global:__N.Log.Add("$Message") | Out-Null }
function Write-Log        { param([string]$m); $global:__N.Log.Add("LOG: $m") | Out-Null }
function Start-Sleep      { param([int]$Seconds,[int]$Milliseconds) }   # time does not pass in the sim

function Get-ItemProperty {
    param([string]$Path,[string]$Name,$ErrorAction)
    $key = "$Path|$Name"
    if ($global:__N.Reg.ContainsKey($key)) {
        return [pscustomobject]@{ $Name = $global:__N.Reg[$key] }
    }
    if ($ErrorAction -eq 'Stop') { throw "reg value not present: $key" }
    return $null
}

function Get-CimInstance {
    param($ClassName,[string]$Namespace,[string]$Filter,$ErrorAction)
    $cls = if ($ClassName) { "$ClassName" } else { '' }
    if ($cls -match 'Win32_OperatingSystem') {
        if (-not $global:__N.OS) { if ($ErrorAction -eq 'Stop') { throw 'no OS' } else { return $null } }
        return $global:__N.OS
    }
    if ($cls -match 'Win32_Service') {
        if ($null -eq $global:__N.TermServicePid) { if ($ErrorAction -eq 'Stop') { throw 'no svc' } else { return $null } }
        return [pscustomobject]@{ Name='TermService'; ProcessId=$global:__N.TermServicePid }
    }
    if ($ErrorAction -eq 'Stop') { throw "unhandled CIM class: $cls" }
    return $null
}
function Get-WmiObject { param($Class,[string]$Namespace,$ErrorAction); return (Get-CimInstance -ClassName $Class -ErrorAction $ErrorAction) }

function Get-NetTCPConnection {
    param([int]$LocalPort,[string]$State,$ErrorAction)
    $conns = @($global:__N.Listeners | Where-Object { $_.LocalPort -eq $LocalPort })
    return $conns
}

function Get-Process {
    param([int]$Id,$ErrorAction)
    if ($null -ne $global:__N.TermServicePid -and $Id -eq $global:__N.TermServicePid) {
        $mods = @($global:__N.TermServiceModules | ForEach-Object { [pscustomobject]@{ ModuleName = $_ } })
        return [pscustomobject]@{ Id=$Id; Modules=$mods }
    }
    if ($ErrorAction -eq 'SilentlyContinue') { return $null }
    throw "no such process $Id"
}
'@

# --- Build the sandbox module once: fakes + the real functions under test. ---
function New-NovivoSandbox {
    param([string]$BackendPath, [string[]]$Functions)
    $realSrc = Get-NovivoFunctionSource -Path $BackendPath -Names $Functions
    $composed = $FakesSource + "`n`n" + $realSrc + "`n`nExport-ModuleMember -Function *"
    return (New-Module -Name 'NovivoSandbox' -ScriptBlock ([scriptblock]::Create($composed)))
}

# --- Assertion helpers -------------------------------------------------------
$script:Results = New-Object System.Collections.Generic.List[object]

function Invoke-NovivoScenario {
    param(
        [string]$Group,          # which function / area
        [string]$Name,           # scenario label
        [hashtable]$Machine,     # simulated machine state
        [scriptblock]$Act,       # runs inside the sandbox module, returns the value under test
        [scriptblock]$Assert     # given ($actual,$log) -> throws on failure
    )
    $global:__N = @{
        Reg=@{}; OS=$null; Listeners=@(); TermServicePid=$null; TermServiceModules=@()
        Log=(New-Object System.Collections.Generic.List[string])
    }
    foreach ($k in $Machine.Keys) { $global:__N[$k] = $Machine[$k] }

    $pass=$true; $err=$null; $actual=$null
    try {
        $actual = & $script:Sandbox $Act
        & $Assert $actual $global:__N.Log
    } catch {
        $pass=$false; $err=$_.Exception.Message
    }
    $script:Results.Add([pscustomobject]@{ Group=$Group; Scenario=$Name; Pass=$pass; Detail=$err })
    $mark = if ($pass) { '  PASS' } else { '  FAIL' }
    Write-Host ("{0}  [{1}] {2}" -f $mark, $Group, $Name) -ForegroundColor ($(if($pass){'Green'}else{'Red'}))
    if (-not $pass) { Write-Host ("        -> {0}" -f $err) -ForegroundColor DarkYellow }
}

function Write-NovivoSummary {
    $total=$script:Results.Count
    $failed=@($script:Results | Where-Object { -not $_.Pass })
    Write-Host ""
    Write-Host ("=" * 68)
    Write-Host ("  SCENARIO MATRIX: {0} run, {1} passed, {2} failed" -f $total, ($total-$failed.Count), $failed.Count) -ForegroundColor Cyan
    Write-Host ("=" * 68)
    if ($failed.Count) {
        Write-Host "  Failing scenarios:" -ForegroundColor Red
        foreach ($f in $failed) { Write-Host ("   - [{0}] {1}: {2}" -f $f.Group,$f.Scenario,$f.Detail) -ForegroundColor Red }
    }
    return $failed.Count
}

# --- Small factory for simulated Win32_OperatingSystem -----------------------
function New-SimOS {
    param([string]$Caption,[int]$ProductType=1,$Sku=$null)
    $o=[ordered]@{ Caption=$Caption; ProductType=$ProductType }
    $o['OperatingSystemSKU']=$Sku
    return [pscustomobject]$o
}
function New-SimListener { param([int]$Port,[int]$ProcId) ; [pscustomobject]@{ LocalPort=$Port; State='Listen'; OwningProcess=$ProcId } }
