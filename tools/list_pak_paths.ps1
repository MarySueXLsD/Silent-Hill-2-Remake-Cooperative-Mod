# Lists file paths stored in the game's IoStore container index (.utoc) that match a regex.
# Read-only; used to discover asset paths (e.g. character meshes) without running the game.
#   tools\list_pak_paths.ps1 -Filter 'Characters/.*/Mesh/[^/]*\.uasset$'
param(
    [string]$Utoc = 'C:\Program Files (x86)\SILENT HILL 2 REMAKE\SHProto\Content\Paks\SHProto-Windows.utoc',
    [Parameter(Mandatory = $true)][string]$Filter
)
$bytes = [IO.File]::ReadAllBytes($Utoc)

# The directory index starts with its mount point string: int32 length, then "../../../...".
$needle = [Text.Encoding]::ASCII.GetBytes('../../../')
$start = -1
for ($i = 144; $i -lt $bytes.Length - $needle.Length; $i++) {
    if ($bytes[$i] -eq 0x2E -and $bytes[$i + 1] -eq 0x2E -and $bytes[$i + 2] -eq 0x2F) {
        $ok = $true
        for ($j = 0; $j -lt $needle.Length; $j++) { if ($bytes[$i + $j] -ne $needle[$j]) { $ok = $false; break } }
        if ($ok) { $start = $i - 4; break }
    }
}
if ($start -lt 0) { Write-Output 'directory index not found'; exit 1 }

$ms = New-Object IO.MemoryStream(, $bytes)
$br = New-Object IO.BinaryReader($ms)
$ms.Position = $start
function ReadFString($br) {
    $len = $br.ReadInt32()
    if ($len -eq 0) { return '' }
    if ($len -lt 0) { $b = $br.ReadBytes(-$len * 2); return [Text.Encoding]::Unicode.GetString($b).TrimEnd([char]0) }
    $b = $br.ReadBytes($len)
    return [Text.Encoding]::ASCII.GetString($b, 0, $len - 1)
}
$mount = ReadFString $br
$dirCount = $br.ReadInt32()
$dirs = New-Object 'uint32[]' ($dirCount * 4)
for ($i = 0; $i -lt $dirCount * 4; $i++) { $dirs[$i] = $br.ReadUInt32() }
$fileCount = $br.ReadInt32()
$files = New-Object 'uint32[]' ($fileCount * 3)
for ($i = 0; $i -lt $fileCount * 3; $i++) { $files[$i] = $br.ReadUInt32() }
$strCount = $br.ReadInt32()
$strings = New-Object 'string[]' $strCount
for ($i = 0; $i -lt $strCount; $i++) { $strings[$i] = ReadFString $br }

$NONE = [uint32]::MaxValue
$rx = New-Object Text.RegularExpressions.Regex($Filter, 'IgnoreCase')
$results = New-Object Collections.Generic.List[string]
$stack = New-Object Collections.Generic.Stack[object]
$stack.Push(@(0, ''))
while ($stack.Count -gt 0) {
    $item = $stack.Pop()
    $d = [int]$item[0]; $path = [string]$item[1]
    $f = $dirs[$d * 4 + 3]
    while ($f -ne $NONE) {
        $full = $path + $strings[$files[$f * 3]]
        if ($rx.IsMatch($full)) { $results.Add($full) }
        $f = $files[$f * 3 + 1]
    }
    $c = $dirs[$d * 4 + 1]
    while ($c -ne $NONE) {
        $stack.Push(@($c, ($path + $strings[$dirs[$c * 4]] + '/')))
        $c = $dirs[$c * 4 + 2]
    }
}
"mount: $mount  dirs: $dirCount  files: $fileCount  matches: $($results.Count)"
$results | Sort-Object
