$lines = Get-Content "C:\Program Files\RDP Wrapper\rdpwrap.ini"
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq "[10.0.19041.6456]") { $start = $i; break }
}
Write-Host "Section [10.0.19041.6456] found at line $start"
$lines[$start..([Math]::Min($start+20, $lines.Count-1))]
