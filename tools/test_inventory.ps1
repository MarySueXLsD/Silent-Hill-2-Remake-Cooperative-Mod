# Solo test of shared inventory: pretends to be the other player by writing in.txt by hand.
# Leaves the inventory as it found it. Needs the game running with a save loaded, relay NOT running.
$root = Split-Path $PSScriptRoot -Parent
$ipc = Join-Path $root 'CoopGhost\ipc'
$run = Join-Path $PSScriptRoot 'run.ps1'
function Game($file) { powershell -NoProfile -ExecutionPolicy Bypass -File $run -LuaFile (Join-Path $PSScriptRoot "cmd\$file") }
function Out { Get-Content (Join-Path $ipc 'out.txt') }
function Peer($text) { [IO.File]::WriteAllText((Join-Path $ipc 'in.txt'), $text) }
function MaxId { $ids = Out | Where-Object { $_ -match '^E (\d+) ' } | ForEach-Object { [int]$Matches[1] }; if ($ids) { ($ids | Measure-Object -Maximum).Maximum } else { 0 } }

'--- 1. fake peer connects and reports picking up a health drink'
Peer "S aaaaaa 1 0.0 0.0 0.0 0.0 0.0 0 join`nE 1 inv HealthDrink 1"
Start-Sleep -Milliseconds 1200
Out | ForEach-Object { if ($_.Length -gt 160) { $_.Substring(0, 160) + '...' } else { $_ } }

'--- 2. fake peer acknowledges everything and reports using the drink'
$ack = MaxId
Peer "S aaaaaa 2 0.0 0.0 0.0 0.0 0.0 $ack join`nE 1 inv HealthDrink 1`nE 2 inv HealthDrink -1"
Start-Sleep -Milliseconds 1200
Out

'--- 3. local player gains one handgun round'
Game '06_local_item_change.lua'
Start-Sleep -Milliseconds 800
Out

'--- 4. put it back, fake peer acknowledges'
Game '07_restore_ammo.lua'
Start-Sleep -Milliseconds 800
Out
$ack = MaxId
Peer "S aaaaaa 3 0.0 0.0 0.0 0.0 0.0 $ack join`nE 1 inv HealthDrink 1`nE 2 inv HealthDrink -1"
Start-Sleep -Milliseconds 800
Out
Remove-Item (Join-Path $ipc 'in.txt') -Confirm:$false
