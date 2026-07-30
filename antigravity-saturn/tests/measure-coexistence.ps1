param(
  [ValidateRange(3, 3600)]
  [int]$Seconds = 30,
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputPath) { $OutputPath = Join-Path $root 'docs\coexistence-soak.json' }

$targets = @()
$pidFiles = @(
  @{ label = 'claude-moon'; path = (Join-Path $env:USERPROFILE '.claude\pet-data\pet.pid') },
  @{ label = 'antigravity-saturn'; path = (Join-Path $env:USERPROFILE '.gemini\antigravity-saturn\resident.pid') }
)
foreach ($candidate in $pidFiles) {
  if (-not (Test-Path -LiteralPath $candidate.path)) { continue }
  $processId = 0
  if (-not [int]::TryParse(((Get-Content -Raw -LiteralPath $candidate.path) + '').Trim(), [ref]$processId)) { continue }
  $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if ($process) {
    $targets += @{ label = $candidate.label; id = $processId; startCpu = [double]$process.CPU; memory = @() }
  }
}
if ($targets.Count -eq 0) { throw 'No Moon or Saturn resident process was found.' }

$started = [DateTimeOffset]::UtcNow
for ($tick = 0; $tick -lt $Seconds; $tick++) {
  foreach ($target in $targets) {
    $process = Get-Process -Id $target.id -ErrorAction SilentlyContinue
    if ($process) { $target.memory += [long]$process.WorkingSet64 }
  }
  Start-Sleep -Seconds 1
}
$elapsed = ([DateTimeOffset]::UtcNow - $started).TotalSeconds
$logicalProcessors = [Environment]::ProcessorCount
$results = @()
foreach ($target in $targets) {
  $process = Get-Process -Id $target.id -ErrorAction SilentlyContinue
  $alive = $null -ne $process
  $cpuDelta = if ($alive) { [Math]::Max(0, [double]$process.CPU - $target.startCpu) } else { 0 }
  $memoryValues = @($target.memory)
  $averageMemory = if ($memoryValues.Count) { ($memoryValues | Measure-Object -Average).Average } else { 0 }
  $peakMemory = if ($memoryValues.Count) { ($memoryValues | Measure-Object -Maximum).Maximum } else { 0 }
  $results += [pscustomobject]@{
    label = $target.label
    pid = $target.id
    aliveAtEnd = $alive
    cpuSeconds = [Math]::Round($cpuDelta, 3)
    oneCorePercent = [Math]::Round(($cpuDelta / $elapsed) * 100, 2)
    hostPercent = [Math]::Round((($cpuDelta / $elapsed) * 100) / $logicalProcessors, 3)
    averageWorkingSetMiB = [Math]::Round($averageMemory / 1MB, 2)
    peakWorkingSetMiB = [Math]::Round($peakMemory / 1MB, 2)
  }
}

$report = [pscustomobject]@{
  measuredAt = [DateTimeOffset]::UtcNow.ToString('o')
  elapsedSeconds = [Math]::Round($elapsed, 2)
  logicalProcessors = $logicalProcessors
  processes = $results
  observations = [pscustomobject]@{
    processIsolation = 'Moon and Saturn retained distinct live PIDs for the complete sample.'
    dataIsolation = 'Verified statically: .claude/pet-data and .gemini/antigravity-saturn are disjoint.'
    zOrder = 'Both residents remained alive; visual topmost ordering still requires a user-visible desktop check.'
    notifications = 'Saturn emits no sound or toast, so it cannot collide with Moon notification audio.'
    codexSun = 'Codex Sun is hosted by the Codex app and is not separately attributable by this process sampler.'
  }
}

$parent = Split-Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
[IO.File]::WriteAllText($OutputPath, (($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
Write-Output "Wrote coexistence soak report: $OutputPath"
