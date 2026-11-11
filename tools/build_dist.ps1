# Builds dist\CoopGhost\ (launcher + everything that goes into a game folder) and dist\CoopGhost.zip.
#   CoopLauncher.exe          the launcher (compiled here from launcher\CoopLauncher.cs)
#   game_files\               copied into <game>\SHProto\Binaries\Win64 by the launcher's Install button
#   README.txt
param(
    [string]$GameWin64 = 'C:\Program Files (x86)\SILENT HILL 2 REMAKE\SHProto\Binaries\Win64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$out = Join-Path $dist 'CoopGhost'
if (Test-Path $out) { Remove-Item $out -Recurse -Force -Confirm:$false }
$files = Join-Path $out 'game_files'
New-Item -ItemType Directory -Force $files | Out-Null

# launcher
$csc = Get-ChildItem 'C:\Windows\Microsoft.NET\Framework64\v4*\csc.exe' | Sort-Object FullName | Select-Object -Last 1
if (-not $csc) { throw 'C# compiler (csc.exe) not found' }
& $csc.FullName /nologo /target:winexe /optimize+ "/out:$(Join-Path $out 'CoopLauncher.exe')" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll (Join-Path $root 'launcher\CoopLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'launcher failed to compile' }

# mod loader as installed here, minus the dev junction, dumps and logs
Copy-Item (Join-Path $GameWin64 'dwmapi.dll') $files
robocopy (Join-Path $GameWin64 'ue4ss') (Join-Path $files 'ue4ss') /E /XJ /XD CXXHeaderDump /XF UE4SS.log *.dmp /NFL /NDL /NJH /NJS | Out-Null

# the mod itself, as a real copy
$mod = Join-Path $files 'ue4ss\Mods\CoopGhost'
New-Item -ItemType Directory -Force (Join-Path $mod 'Scripts'), (Join-Path $mod 'ipc') | Out-Null
Copy-Item (Join-Path $root 'CoopGhost\Scripts\main.lua'), (Join-Path $root 'CoopGhost\Scripts\core.lua') (Join-Path $mod 'Scripts')
Copy-Item (Join-Path $root 'CoopGhost\enabled.txt') $mod
Copy-Item (Join-Path $root 'README.md') (Join-Path $out 'README.txt')

$zip = Join-Path $dist 'CoopGhost.zip'
if (Test-Path $zip) { Remove-Item $zip -Confirm:$false }
Compress-Archive -Path $out -DestinationPath $zip
"built $out"
"built $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
