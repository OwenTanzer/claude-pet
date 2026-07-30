$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$probeRoot = Join-Path $PSScriptRoot ('.tmp-install-' + [Guid]::NewGuid().ToString('N'))
$pluginDirectory = Join-Path $probeRoot 'plugins\antigravity-saturn'
$configPath = Join-Path $probeRoot 'config.json'

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

try {
  & (Join-Path $root 'tools\install.ps1') -PluginDirectory $pluginDirectory -ConfigPath $configPath | Out-Null
  Assert-True (Test-Path -LiteralPath (Join-Path $pluginDirectory 'plugin.json')) 'installer did not copy plugin.json'
  Assert-True (Test-Path -LiteralPath (Join-Path $pluginDirectory 'assets\saturn-done.png')) 'installer did not copy Saturn assets'
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  Assert-True ($config.sidecars.'antigravity-saturn/saturn-resident'.enabled -eq $true) 'installer did not enable the sidecar'

  & (Join-Path $root 'tools\install.ps1') -PluginDirectory $pluginDirectory -ConfigPath $configPath | Out-Null
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  Assert-True ($config.sidecars.'antigravity-saturn/saturn-resident'.enabled -eq $true) 'repeat install did not preserve the enabled sidecar'

  & (Join-Path $root 'tools\uninstall.ps1') -PluginDirectory $pluginDirectory -ConfigPath $configPath | Out-Null
  Assert-True (-not (Test-Path -LiteralPath $pluginDirectory)) 'uninstaller did not remove the plugin directory'
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  Assert-True ($null -eq $config.sidecars.PSObject.Properties['antigravity-saturn/saturn-resident']) 'uninstaller did not remove the sidecar config entry'
  Write-Output 'Antigravity Saturn install/uninstall roundtrip passed.'
} finally {
  $resolvedTests = [IO.Path]::GetFullPath($PSScriptRoot)
  $resolvedProbe = [IO.Path]::GetFullPath($probeRoot)
  if ($resolvedProbe.StartsWith($resolvedTests, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedProbe).StartsWith('.tmp-install-')) {
    if (Test-Path -LiteralPath $resolvedProbe) { Remove-Item -LiteralPath $resolvedProbe -Recurse -Force }
  }
}
