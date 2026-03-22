$src = "$env:SystemRoot\System32\termsrv.dll"
$bytes = [System.IO.File]::ReadAllBytes($src)
Write-Host "termsrv.dll size: $($bytes.Length) bytes"
Write-Host ""

# Offsets from rdpwrap.ini [10.0.19041.6456]
$offsets = @{
    "LocalOnly(0x91A61)"    = 0x91A61   # jmpshort
    "SingleUser(0x1842B)"   = 0x1842B   # mov_eax_1_nop_2
    "DefPolicy(0x1F415)"    = 0x1F415   # CDefPolicy_Query
    "SLInit(0x70B68)"       = 0x70B68   # SLInitHook
}

foreach ($name in $offsets.Keys) {
    $off = $offsets[$name]
    if ($off -lt $bytes.Length - 16) {
        $b = $bytes[$off..($off+15)]
        $hex = ($b | ForEach-Object { $_.ToString("X2") }) -join " "
        Write-Host "${name}: $hex"
    } else {
        Write-Host "${name}: offset out of range!"
    }
}
