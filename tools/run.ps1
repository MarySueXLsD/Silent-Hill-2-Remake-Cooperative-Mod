# Dev helper: run a Lua file inside the running game through the CoopGhost dev channel
# and print what it reported.   Usage: tools\run.ps1 tools\cmd\something.lua [-TimeoutSec 20]
#   -Legacy  talk to the pre-hot-reload mod (reads cmd.lua instead of run.lua)
param(
    [Parameter(Mandatory = $true)][string]$LuaFile,
    [int]$TimeoutSec = 20,
    [switch]$Legacy
)
$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'CoopGhost\ipc'
$cmd = Join-Path $dir $(if ($Legacy) { 'cmd.lua' } else { 'run.lua' })
$res = Join-Path $dir 'result.txt'
$tmp = Join-Path $dir 'cmd.tmp'

if (-not (Get-Process | Where-Object { $_.Name -match 'SHProto' })) { Write-Output 'GAME NOT RUNNING'; exit 1 }
if (Test-Path $res) { Remove-Item $res -Confirm:$false }
Copy-Item $LuaFile $tmp -Force
Move-Item $tmp $cmd -Force

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $res) {
        $text = $null
        try { $text = Get-Content $res -Raw -ErrorAction Stop } catch { }
        if ($text -and $text -match '<<END>>') { Write-Output ($text -replace '<<END>>', ''); exit 0 }
    }
    Start-Sleep -Milliseconds 100
}
Write-Output "TIMEOUT after $TimeoutSec s (command picked up: $(-not (Test-Path $cmd)))"
if (Test-Path $res) { Write-Output '--- partial output ---'; Get-Content $res }
exit 2
