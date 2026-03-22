# Parse PE header to map RVA to file offset
$src = "C:\Windows\System32\termsrv.dll"
$bytes = [System.IO.File]::ReadAllBytes($src)

# Read DOS header e_lfanew at offset 0x3C
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
Write-Host "PE header at offset: 0x$($peOffset.ToString('X'))"

# Verify PE signature
$peSig = [System.Text.Encoding]::ASCII.GetString($bytes[$peOffset..($peOffset+3)])
Write-Host "PE signature: $peSig"

# Machine type (0x10B = PE32, 0x20B = PE32+/x64)
$machine = [BitConverter]::ToUInt16($bytes, ($peOffset + 4))
$numSections = [BitConverter]::ToUInt16($bytes, ($peOffset + 6))
$optionalHeaderSize = [BitConverter]::ToUInt16($bytes, ($peOffset + 20))
$magic = [BitConverter]::ToUInt16($bytes, ($peOffset + 24))
Write-Host "Machine: 0x$($machine.ToString('X')) (0x8664=x64)"
Write-Host "Sections: $numSections"
Write-Host "Optional header: $optionalHeaderSize bytes"
Write-Host "Magic: 0x$($magic.ToString('X')) (0x20B=PE32+)"

# Section table starts after PE header (0x18 COFF size) + optional header
$sectionTableOffset = $peOffset + 24 + $optionalHeaderSize

Write-Host ""
Write-Host "Sections:"
for ($i = 0; $i -lt $numSections; $i++) {
    $secOffset = $sectionTableOffset + ($i * 40)
    $name = [System.Text.Encoding]::ASCII.GetString($bytes[$secOffset..($secOffset+7)]).TrimEnd([char]0)
    $virtSize = [BitConverter]::ToUInt32($bytes, ($secOffset + 8))
    $virtAddr = [BitConverter]::ToUInt32($bytes, ($secOffset + 12))
    $rawSize  = [BitConverter]::ToUInt32($bytes, ($secOffset + 16))
    $rawAddr  = [BitConverter]::ToUInt32($bytes, ($secOffset + 20))
    Write-Host "  [$name] VirtAddr=0x$($virtAddr.ToString('X')) RawAddr=0x$($rawAddr.ToString('X')) VirtSize=0x$($virtSize.ToString('X'))"
}

Write-Host ""
Write-Host "RVA to file offset conversion:"

function RvaToFileOffset($rva, $sections, $numSec) {
    for ($i = 0; $i -lt $numSec; $i++) {
        $secOffset = $sectionTableOffset + ($i * 40)
        $virtAddr = [BitConverter]::ToUInt32($bytes, ($secOffset + 12))
        $virtSize = [BitConverter]::ToUInt32($bytes, ($secOffset + 8))
        $rawAddr  = [BitConverter]::ToUInt32($bytes, ($secOffset + 20))
        if ($rva -ge $virtAddr -and $rva -lt ($virtAddr + $virtSize)) {
            return $rawAddr + ($rva - $virtAddr)
        }
    }
    return -1
}

$rvas = @{
    "LocalOnly"  = 0x91A61
    "SingleUser" = 0x1842B
    "DefPolicy"  = 0x1F415
    "SLInit"     = 0x70B68
}

foreach ($name in $rvas.Keys) {
    $rva = $rvas[$name]
    $fileOff = RvaToFileOffset $rva $null $numSections
    $rvaHex = $rva.ToString('X'); $fileHex = $fileOff.ToString('X')
    Write-Host "  ${name}: RVA=0x$rvaHex -> FileOff=0x$fileHex"
    if ($fileOff -gt 0 -and $fileOff -lt $bytes.Length - 16) {
        $b = $bytes[$fileOff..($fileOff+15)]
        $hex = ($b | ForEach-Object { $_.ToString("X2") }) -join " "
        Write-Host "    Bytes: $hex"
    }
}
