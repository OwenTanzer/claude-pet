Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failed = $false

foreach ($relative in 'pet\pet-resident.ps1','pet\pet-session-start.ps1','tools\claude-draw.ps1') {
  $tokens = $null; $parseErrors = $null
  $path = Join-Path $root $relative
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
  if ($parseErrors.Count) {
    $failed = $true
    Write-Output "$relative PARSE_FAIL"
    $parseErrors | ForEach-Object { Write-Output $_.Message }
  } else {
    Write-Output "$relative PARSE_OK"
  }
}

$assets = @(Get-ChildItem (Join-Path $root 'pet\phases') -Recurse -Filter *.png)
$invalid = @()
foreach ($asset in $assets) {
  $image = [System.Drawing.Bitmap]::FromFile($asset.FullName)
  if ($image.Width -ne 360 -or $image.Height -ne 360 -or $image.GetPixel(0, 0).A -ne 0) {
    $invalid += $asset.FullName
  }
  $image.Dispose()
}

Write-Output "ASSETS=$($assets.Count) INVALID=$($invalid.Count)"
if ($assets.Count -ne 24 -or $invalid.Count) {
  $failed = $true
  $invalid | ForEach-Object { Write-Output $_ }
}

if ($failed) { exit 1 }
