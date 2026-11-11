# SH2-CoopMod relay - carries the mod's messages between the two PCs.
# Works over any network where the PCs can reach each other by IP: Radmin VPN, Hamachi, LAN.
#
# Run it on BOTH PCs, each pointing at the OTHER one's VPN address. One side is the host
# (its world and inventory are the authority), the other joins:
#
#   powershell -ExecutionPolicy Bypass -File relay.ps1 -PeerIP 26.x.x.x -Role host
#   powershell -ExecutionPolicy Bypass -File relay.ps1 -PeerIP 26.x.x.x -Role join
#
# Stop it with Ctrl+C. Uses UDP port 47777 by default (must be the same on both sides).
param(
    [Parameter(Mandatory = $true)][string]$PeerIP,
    [ValidateSet('host', 'join')][string]$Role = 'host',
    [int]$Port = 47777
)

$dir = Join-Path $PSScriptRoot 'ipc'
New-Item -ItemType Directory -Force $dir | Out-Null
$outFile = Join-Path $dir 'out.txt'
$inFile = Join-Path $dir 'in.txt'
if (Test-Path $inFile) { Remove-Item $inFile -Confirm:$false }
[System.IO.File]::WriteAllText((Join-Path $dir 'role.txt'), $Role)

$udp = New-Object System.Net.Sockets.UdpClient($Port)
$peer = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($PeerIP), $Port)
$any = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
$enc = [System.Text.Encoding]::ASCII

Write-Host "SH2-CoopMod relay ($Role): sending to ${PeerIP}:$Port, listening on UDP $Port"
Write-Host "Folder: $dir"

$lastSent = ''
$lastSendTime = [DateTime]::MinValue
$sent = 0; $recv = 0
$lastReport = [DateTime]::UtcNow

try {
    while ($true) {
        # our messages -> peer
        try {
            $fs = [System.IO.File]::Open($outFile, 'Open', 'Read', 'ReadWrite')
            $sr = New-Object System.IO.StreamReader($fs)
            $text = $sr.ReadToEnd()
            $sr.Close()
            if ($text -and $text.StartsWith('S ') -and $text.Length -lt 60000 -and $text -ne $lastSent) {
                $bytes = $enc.GetBytes($text)
                [void]$udp.Send($bytes, $bytes.Length, $peer)
                $lastSent = $text
                $sent++
            }
        } catch { }

        # peer messages -> in.txt (keep only the newest packet)
        $latest = $null
        while ($udp.Available -gt 0) {
            try {
                $data = $udp.Receive([ref]$any)
                if ($any.Address.ToString() -eq $PeerIP) { $latest = $enc.GetString($data); $recv++ }
            } catch { break }
        }
        if ($latest -and $latest.StartsWith('S ') -and $latest.Length -lt 60000) {
            try { [System.IO.File]::WriteAllText($inFile, $latest) } catch { }
        }

        if (([DateTime]::UtcNow - $lastReport).TotalSeconds -ge 5) {
            Write-Host ("{0:HH:mm:ss}  sent {1}  received {2}" -f (Get-Date), $sent, $recv)
            $sent = 0; $recv = 0
            $lastReport = [DateTime]::UtcNow
        }
        Start-Sleep -Milliseconds 15
    }
} finally {
    $udp.Close()
}
