param(
  [string]$PluginDirectory = (Join-Path $env:USERPROFILE '.gemini\config\plugins\antigravity-saturn'),
  [string]$ConfigPath = (Join-Path $env:USERPROFILE '.gemini\config\config.json')
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$sidecarId = 'antigravity-saturn/saturn-resident'

function Write-JsonAtomic([string]$Path, $Value) {
  $parent = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  $json = $Value | ConvertTo-Json -Depth 20
  [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$required = @(
  'plugin.json',
  'hooks.json',
  'scripts\saturn-hook.js',
  'sidecars\saturn-resident\sidecar.json',
  'sidecars\saturn-resident\pet-resident.ps1',
  'assets\saturn-idle.png',
  'assets\saturn-working.png',
  'assets\saturn-done.png'
)
foreach ($relative in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative))) { throw "Missing package file: $relative" }
}

foreach ($directory in @('', 'scripts', 'assets', 'sidecars\saturn-resident')) {
  $destination = if ($directory) { Join-Path $PluginDirectory $directory } else { $PluginDirectory }
  if (-not (Test-Path -LiteralPath $destination)) { New-Item -ItemType Directory -Force -Path $destination | Out-Null }
}
foreach ($relative in $required) {
  Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination (Join-Path $PluginDirectory $relative) -Force
}

$config = [pscustomobject]@{}
if (Test-Path -LiteralPath $ConfigPath) {
  $raw = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
  if ($raw.Trim()) {
    try { $config = $raw | ConvertFrom-Json }
    catch { throw "Antigravity config is not valid JSON; no config changes were made: $ConfigPath" }
  }
  Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.saturn-backup') -Force
}
if (-not $config.PSObject.Properties['sidecars']) {
  $config | Add-Member -NotePropertyName sidecars -NotePropertyValue ([pscustomobject]@{})
}
$entry = [pscustomobject]@{ enabled = $true }
if ($config.sidecars.PSObject.Properties[$sidecarId]) { $config.sidecars.$sidecarId = $entry }
else { $config.sidecars | Add-Member -NotePropertyName $sidecarId -NotePropertyValue $entry }
Write-JsonAtomic $ConfigPath $config

Write-Output "Installed Antigravity Saturn plugin: $PluginDirectory"
Write-Output "Enabled sidecar: $sidecarId"
Write-Output 'Restart Antigravity if Saturn does not appear automatically.'
