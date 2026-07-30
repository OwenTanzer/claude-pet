param(
  [string]$PluginDirectory = (Join-Path $env:USERPROFILE '.gemini\config\plugins\antigravity-saturn'),
  [string]$ConfigPath = (Join-Path $env:USERPROFILE '.gemini\config\config.json'),
  [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'
$sidecarId = 'antigravity-saturn/saturn-resident'
$dataDirectory = Join-Path $env:USERPROFILE '.gemini\antigravity-saturn'

function Write-JsonAtomic([string]$Path, $Value) {
  $parent = Split-Path $Path -Parent
  $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  $json = $Value | ConvertTo-Json -Depth 20
  [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

if (Test-Path -LiteralPath $ConfigPath) {
  $raw = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
  if ($raw.Trim()) {
    try { $config = $raw | ConvertFrom-Json }
    catch { throw "Antigravity config is not valid JSON; uninstall stopped before deleting the plugin: $ConfigPath" }
    if ($config.PSObject.Properties['sidecars'] -and $config.sidecars.PSObject.Properties[$sidecarId]) {
      Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.saturn-backup') -Force
      $config.sidecars.PSObject.Properties.Remove($sidecarId)
      Write-JsonAtomic $ConfigPath $config
    }
  }
}

$resolvedParent = [IO.Path]::GetFullPath((Split-Path $PluginDirectory -Parent))
$resolvedTarget = [IO.Path]::GetFullPath($PluginDirectory)
if ([IO.Path]::GetFileName($resolvedTarget) -ne 'antigravity-saturn' -or -not $resolvedTarget.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to delete unexpected plugin path: $resolvedTarget"
}
if (Test-Path -LiteralPath $resolvedTarget) { Remove-Item -LiteralPath $resolvedTarget -Recurse -Force }

if ($RemoveData -and (Test-Path -LiteralPath $dataDirectory)) {
  $resolvedData = [IO.Path]::GetFullPath($dataDirectory)
  if ([IO.Path]::GetFileName($resolvedData) -ne 'antigravity-saturn') { throw "Refusing to delete unexpected data path: $resolvedData" }
  Remove-Item -LiteralPath $resolvedData -Recurse -Force
}

Write-Output "Removed Antigravity Saturn plugin: $resolvedTarget"
if ($RemoveData) { Write-Output "Removed Saturn runtime data: $dataDirectory" }
else { Write-Output "Kept Saturn runtime data: $dataDirectory" }
Write-Output 'Restart Antigravity if Saturn is still visible.'
