# Klezmoball pet-control protocol v1.
# This adapter is intentionally visibility-only: it never starts/stops agent work and
# publishes no prompt, response, transcript, or artifact content.

function Get-PetCenterProtocolRoot {
  if ($env:KLEZMOBALL_HOME) { return [IO.Path]::GetFullPath($env:KLEZMOBALL_HOME) }
  if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'Klezmoball\v1') }
  return (Join-Path $env:USERPROFILE '.klezmoball\v1')
}

function Write-PetCenterJsonAtomic([string]$Path, $Value) {
  $parent = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + $PID + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
  $json = $Value | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function New-PetCenterSnapshot([bool]$Running) {
  $ctx = $script:PetCenterAdapter
  if (-not $ctx) { return $null }
  $visible = $false
  if ($Running) { try { $visible = [bool](& $ctx.GetVisible) } catch {} }
  $state = 'unknown'
  if ($Running -and $ctx.GetState) { try { $state = [string](& $ctx.GetState) } catch {} }
  if ($state -notmatch '^[a-z][a-z0-9-]{0,31}$') { $state = 'unknown' }
  return [ordered]@{
    schemaVersion = 1
    protocol = 'klezmoball.pet-control'
    pet = [ordered]@{ id = $ctx.PetId; displayName = $ctx.DisplayName; provider = $ctx.Provider; adapterVersion = '1.0.0' }
    runtime = [ordered]@{ pid = $PID; running = $Running; visible = $visible; state = $state; startedAtMs = $ctx.StartedAtMs }
    capabilities = [ordered]@{ visibility = 'show-hide'; lifecycle = 'none'; focus = 'native-pet'; trackingWhenHidden = $true }
    ownership = [ordered]@{ dataRoot = $ctx.DataRoot; positionFile = $ctx.PositionFile; mutex = $ctx.MutexName }
    updatedAtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  }
}

function Publish-PetCenterStatus {
  if (-not $script:PetCenterAdapter) { return }
  Write-PetCenterJsonAtomic $script:PetCenterAdapter.RegistryPath (New-PetCenterSnapshot $true)
}

function Start-PetCenterAdapter {
  param(
    [Parameter(Mandatory=$true)][string]$PetId,
    [Parameter(Mandatory=$true)][string]$DisplayName,
    [Parameter(Mandatory=$true)][string]$Provider,
    [Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$PositionFile,
    [Parameter(Mandatory=$true)][string]$MutexName,
    [Parameter(Mandatory=$true)][scriptblock]$GetVisible,
    [Parameter(Mandatory=$true)][scriptblock]$SetVisible,
    [scriptblock]$GetState
  )
  if ($PetId -notmatch '^[a-z0-9][a-z0-9.-]{1,63}$') { throw "Invalid pet id: $PetId" }
  $base = Get-PetCenterProtocolRoot
  $registry = Join-Path $base 'registry'
  $commands = Join-Path $base 'commands'
  $acks = Join-Path $base 'acks'
  foreach ($directory in $registry, $commands, $acks) {
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  }
  $script:PetCenterAdapter = [ordered]@{
    PetId = $PetId; DisplayName = $DisplayName; Provider = $Provider
    DataRoot = $DataRoot; PositionFile = $PositionFile; MutexName = $MutexName
    GetVisible = $GetVisible; SetVisible = $SetVisible; GetState = $GetState
    RegistryPath = (Join-Path $registry ($PetId + '.json'))
    CommandPath = (Join-Path $commands ($PetId + '.json'))
    AckPath = (Join-Path $acks ($PetId + '.json'))
    StartedAtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    LastCommandId = ''
  }
  Publish-PetCenterStatus
}

function Invoke-PetCenterCommand {
  if (-not $script:PetCenterAdapter) { return $false }
  $ctx = $script:PetCenterAdapter
  if (-not (Test-Path -LiteralPath $ctx.CommandPath)) { return $false }
  $command = $null
  try { $command = [IO.File]::ReadAllText($ctx.CommandPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $false }
  $commandId = [string]$command.commandId
  if (-not $commandId -or $commandId.Length -gt 128 -or $commandId -eq $ctx.LastCommandId) { return $false }
  $ctx.LastCommandId = $commandId
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $status = 'rejected'; $reason = 'invalid-command'
  $desired = $null
  if ([int]$command.schemaVersion -ne 1 -or [string]$command.petId -cne $ctx.PetId) { $reason = 'protocol-mismatch' }
  elseif ($command.expiresAtMs -and [long]$command.expiresAtMs -lt $nowMs) { $reason = 'expired' }
  elseif ([string]$command.action -eq 'show') { $desired = $true }
  elseif ([string]$command.action -eq 'hide') { $desired = $false }
  else { $reason = 'unsupported-action' }
  if ($null -ne $desired) {
    try {
      & $ctx.SetVisible ([bool]$desired)
      $observed = [bool](& $ctx.GetVisible)
      if ($observed -eq [bool]$desired) { $status = 'applied'; $reason = '' }
      else { $reason = 'visibility-not-applied' }
    } catch { $reason = 'adapter-error' }
  }
  $visible = $false
  try { $visible = [bool](& $ctx.GetVisible) } catch {}
  $ack = [ordered]@{
    schemaVersion = 1; protocol = 'klezmoball.pet-control'; petId = $ctx.PetId
    commandId = $commandId; action = [string]$command.action; status = $status
    reason = $reason; observedVisible = $visible; updatedAtMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  }
  Write-PetCenterJsonAtomic $ctx.AckPath $ack
  Publish-PetCenterStatus
  try { Remove-Item -LiteralPath $ctx.CommandPath -Force -ErrorAction SilentlyContinue } catch {}
  return ($status -eq 'applied')
}

function Stop-PetCenterAdapter {
  if (-not $script:PetCenterAdapter) { return }
  try { Write-PetCenterJsonAtomic $script:PetCenterAdapter.RegistryPath (New-PetCenterSnapshot $false) } catch {}
  $script:PetCenterAdapter = $null
}
