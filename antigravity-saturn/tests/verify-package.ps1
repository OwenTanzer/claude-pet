$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

$plugin = Get-Content -Raw -LiteralPath (Join-Path $root 'plugin.json') | ConvertFrom-Json
$hooks = Get-Content -Raw -LiteralPath (Join-Path $root 'hooks.json') | ConvertFrom-Json
$sidecar = Get-Content -Raw -LiteralPath (Join-Path $root 'sidecars\saturn-resident\sidecar.json') | ConvertFrom-Json
$residentPath = Join-Path $root 'sidecars\saturn-resident\pet-resident.ps1'
$resident = Get-Content -Raw -LiteralPath $residentPath

Assert-True ($plugin.name -eq 'antigravity-saturn') 'plugin name mismatch'
foreach ($event in @('PreInvocation','PostInvocation','PreToolUse','PostToolUse','Stop')) {
  Assert-True ($null -ne $hooks.'saturn-state'.$event) "missing hook event: $event"
}
Assert-True ($sidecar.command -eq 'powershell.exe') 'sidecar must use Windows PowerShell without requiring pwsh'
Assert-True ($sidecar.restart_policy -eq 'on-failure') 'sidecar restart policy mismatch'
Assert-True ($resident.Contains('Local\AntigravitySaturnPetResidentV1')) 'Saturn mutex is not namespaced'
Assert-True ($resident.Contains('.gemini\antigravity-saturn')) 'Saturn data root is not namespaced'
Assert-True (-not $resident.Contains('ClaudePetResident')) 'Saturn collides with the Claude pet mutex'
Assert-True (-not $resident.Contains('.claude\pet-data')) 'Saturn collides with the Claude pet data root'
Assert-True ($resident.Contains('Find-HostWindow')) 'Saturn does not resolve CLI host terminals'
Assert-True ($resident.Contains('Select-TerminalTab')) 'Saturn does not select its Windows Terminal tab'
Assert-True (-not $resident.Contains("tabTitle={2}")) 'Saturn persists the captured terminal tab title in its log'
Assert-True ($resident.Contains('Antigravity CLI')) 'Saturn status card is missing'
Assert-True ($resident.Contains('card-collapsed.flag')) 'Saturn card collapse state is not remembered'

$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('saturn-smoke-' + [Guid]::NewGuid().ToString('N'))
try {
  $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $residentPath -SmokeTest -DataRoot $smokeRoot
  Assert-True ($LASTEXITCODE -eq 0) "resident smoke test failed: $raw"
  $smoke = $raw | ConvertFrom-Json
  Assert-True ($smoke.ok -eq $true) 'resident asset smoke test did not pass'
  Assert-True ($smoke.assets.Count -eq 3) 'resident did not validate all three assets'
  $compiledRaw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $residentPath -CompileTest -DataRoot $smokeRoot
  Assert-True ($LASTEXITCODE -eq 0) "resident compile test failed: $compiledRaw"
  $compiled = $compiledRaw | ConvertFrom-Json
  Assert-True ($compiled.compiled -eq $true) 'resident C# bridge did not compile'
} finally {
  if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force }
}

Write-Output 'Antigravity Saturn package verification passed.'
