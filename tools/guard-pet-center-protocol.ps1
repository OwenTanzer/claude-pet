$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path $PSScriptRoot -Parent) 'pet\pet-center-protocol.ps1'
$probe = Join-Path $PSScriptRoot ('.tmp-pet-center-' + [Guid]::NewGuid().ToString('N'))
$oldHome = $env:KLEZMOBALL_HOME

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

try {
  $env:KLEZMOBALL_HOME = $probe
  $script:testVisible = $true
  $script:setCount = 0
  . $module
  Start-PetCenterAdapter -PetId 'claude-moon' -DisplayName 'Moon' -Provider 'Claude Code' -DataRoot 'C:\safe\moon' -PositionFile 'C:\safe\moon\position.txt' -MutexName 'MoonTest' -GetVisible { $script:testVisible } -SetVisible { param($value) $script:testVisible = [bool]$value; $script:setCount++ } -GetState { 'working' }

  $registryPath = Join-Path $probe 'registry\claude-moon.json'
  Assert-True (Test-Path -LiteralPath $registryPath) 'adapter did not publish a registry heartbeat'
  $registryRaw = [IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)
  $registry = $registryRaw | ConvertFrom-Json
  Assert-True ($registry.schemaVersion -eq 1 -and $registry.protocol -eq 'klezmoball.pet-control') 'registry protocol mismatch'
  Assert-True ($registry.runtime.running -eq $true -and $registry.runtime.visible -eq $true -and $registry.runtime.state -eq 'working') 'registry runtime state mismatch'
  Assert-True ($registry.capabilities.visibility -eq 'show-hide' -and $registry.capabilities.lifecycle -eq 'none') 'unsafe lifecycle capability exposed'
  Assert-True ($registryRaw -notmatch '(?i)prompt|response|transcript|artifact') 'registry leaked a content-bearing field'

  $commandPath = Join-Path $probe 'commands\claude-moon.json'
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $hide = [ordered]@{ schemaVersion=1; protocol='klezmoball.pet-control'; petId='claude-moon'; commandId='hide-1'; action='hide'; createdAtMs=$now; expiresAtMs=($now+10000) }
  Write-PetCenterJsonAtomic $commandPath $hide
  Assert-True (Invoke-PetCenterCommand) 'valid hide command was not applied'
  Assert-True (-not $script:testVisible -and $script:setCount -eq 1) 'hide did not call the visibility adapter exactly once'
  $ack = [IO.File]::ReadAllText((Join-Path $probe 'acks\claude-moon.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
  Assert-True ($ack.commandId -eq 'hide-1' -and $ack.status -eq 'applied' -and $ack.observedVisible -eq $false) 'hide acknowledgement mismatch'

  $expired = [ordered]@{ schemaVersion=1; protocol='klezmoball.pet-control'; petId='claude-moon'; commandId='show-expired'; action='show'; createdAtMs=($now-20000); expiresAtMs=($now-10000) }
  Write-PetCenterJsonAtomic $commandPath $expired
  Assert-True (-not (Invoke-PetCenterCommand)) 'expired command was accepted'
  Assert-True (-not $script:testVisible -and $script:setCount -eq 1) 'expired command changed visibility'

  $stop = [ordered]@{ schemaVersion=1; protocol='klezmoball.pet-control'; petId='claude-moon'; commandId='stop-1'; action='stop'; createdAtMs=$now; expiresAtMs=($now+10000) }
  Write-PetCenterJsonAtomic $commandPath $stop
  Assert-True (-not (Invoke-PetCenterCommand)) 'lifecycle command was accepted'
  Assert-True (-not $script:testVisible -and $script:setCount -eq 1) 'unsupported lifecycle command reached the adapter'

  $show = [ordered]@{ schemaVersion=1; protocol='klezmoball.pet-control'; petId='claude-moon'; commandId='show-1'; action='show'; createdAtMs=$now; expiresAtMs=($now+10000) }
  Write-PetCenterJsonAtomic $commandPath $show
  Assert-True (Invoke-PetCenterCommand) 'valid show command was not applied'
  Assert-True ($script:testVisible -and $script:setCount -eq 2) 'show did not restore visibility'

  Stop-PetCenterAdapter
  $stopped = [IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  Assert-True ($stopped.runtime.running -eq $false -and $stopped.runtime.visible -eq $false) 'shutdown heartbeat is not honest'
  Write-Output 'Klezmoball pet-control adapter verification passed.'
} finally {
  if ($null -eq $oldHome) { Remove-Item Env:\KLEZMOBALL_HOME -ErrorAction SilentlyContinue } else { $env:KLEZMOBALL_HOME = $oldHome }
  if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Recurse -Force }
}
