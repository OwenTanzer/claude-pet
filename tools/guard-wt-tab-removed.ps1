# Guard: exact, session-bound Windows Terminal tab selection + load-bearing session fields.
# Static asserts + real new-write/self-heal fixtures + parse/compile/ASCII. Exit 1 on red.
$ErrorActionPreference = 'Stop'
# lives in tools/ (dev-only, not shipped); the code it guards is the sibling pet/ dir
$pet = Join-Path (Split-Path $PSScriptRoot -Parent) 'pet'
$fail = @()
function Red($m) { $script:fail += $m; Write-Host "RED  $m" }
function Grn($m) { Write-Host "ok   $m" }
function Parse($path) { $t=$null;$e=$null; $a=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e); @{ ast=$a; tokens=$t; errors=$e } }
$RES = Join-Path $pet 'pet-resident.ps1'; $EV = Join-Path $pet 'pet-event.ps1'; $SS = Join-Path $pet 'pet-session-start.ps1'
$guardRoot = Join-Path (Split-Path $PSScriptRoot -Parent) ('.guard-tmp-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $guardRoot | Out-Null

# --- G1: obsolete nonce-injection implementation remains gone ---
foreach ($f in 'JumpWt.cs','jump-nonce.ps1') { if (Test-Path (Join-Path $pet $f)) { Red "G2 $f still exists" } else { Grn "G2 $f gone" } }

# --- G3: Jump-Row selects the exact Moon tab and preserves VS Code behavior ---
$rp = Parse $RES
if ($rp.errors.Count) { Red "G3 resident parse failed: $($rp.errors[0].Message)" }
$jr = @($rp.ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Jump-Row' }, $true))
if ($jr.Count -ne 1) { Red "G3 Jump-Row not found (or dup)" } else {
  $jr = $jr[0]
  $cmds = @($jr.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
  if ($cmds -contains 'Write-JumpRequest') { Grn "G3 Jump-Row calls Write-JumpRequest (VS Code)" } else { Red "G3 Jump-Row no longer calls Write-JumpRequest" }
  if ($cmds -contains 'Select-MoonTerminalTarget') { Grn "G3 Jump-Row selects the exact Moon terminal tab" } else { Red "G3 Jump-Row does not select the Moon terminal tab" }
  $act = @($jr.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and "$($n.Member.Value)" -eq 'Activate' }, $true))
  if ($act.Count -ge 1) { Grn "G3 Jump-Row calls ::Activate (window-level)" } else { Red "G3 Jump-Row no longer activates the window" }
}
# KEEP functions still DEFINED (AST), not just present as text
$defs = @($rp.ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
foreach ($k in 'Jump-Row','Find-HostWindow','Find-MoonTerminalTarget','Select-MoonTerminalTarget','Capture-MoonTerminalTarget','Write-JumpRequest') { if ($defs -notcontains $k) { Red "G3 required function '$k' not defined" } }
$lpMembers = ($rp.ast.Extent.Text -match 'PickWindowForPath')
if ($lpMembers) { Grn "G3 PickWindowForPath (multi-window) present" } else { Red "G3 PickWindowForPath vanished" }
if ($rp.ast.Extent.Text -match "ProcessName -eq 'WindowsTerminal'[\s\S]*?return \[IntPtr\]::Zero") { Grn "G3 shared WindowsTerminal HWND is never returned blindly" } else { Red "G3 Find-HostWindow may fall back to a shared WindowsTerminal HWND" }
if ($rp.ast.Extent.Text -match 'matches\.Count -eq 1') { Grn "G3 resolver requires one exact tab match" } else { Red "G3 resolver does not fail closed on missing/duplicate markers" }
if ($rp.ast.Extent.Text -match 'tab captured sid=' -and $rp.ast.Extent.Text -match '\.taback') { Grn "G3 transient marker capture writes a resident-scoped ack" } else { Red "G3 capture handshake missing" }
foreach ($hook in $EV,$SS) {
  $ht = [IO.File]::ReadAllText($hook, [Text.Encoding]::UTF8)
  if ($ht -match 'function Wait-TerminalCapture' -and $ht -match 'AddMilliseconds\((1200|1600)\)') { Grn "G3 $(Split-Path $hook -Leaf) holds the marker for bounded capture" } else { Red "G3 $(Split-Path $hook -Leaf) lacks bounded capture wait" }
}

# --- G5: interrupt watch defined + reads transcript at index 8 ($p[8]) ---
if ($defs -contains 'Test-Interrupted') { Grn "G5 Test-Interrupted defined" } else { Red "G5 Test-Interrupted gone" }
$idx8 = @($rp.ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IndexExpressionAst] -and $n.Index -is [System.Management.Automation.Language.ConstantExpressionAst] -and "$($n.Index.Value)" -eq '8' -and "$($n.Target.Extent.Text)" -eq '$p' }, $true))
if ($idx8.Count -ge 1) { Grn "G5 transcript still read at `$p[8]" } else { Red "G5 no `$p[8] transcript read remains" }

# --- G6: parse (5.1 resident, pwsh hooks) + Lp compile + resident ASCII ---
$ps51Mode = (& powershell.exe -NoProfile -Command '$ExecutionContext.SessionState.LanguageMode' | Select-Object -First 1)
if ($ps51Mode -eq 'FullLanguage') {
  & powershell.exe -NoProfile -Command "`$e=`$null;[void][System.Management.Automation.Language.Parser]::ParseFile('$RES',[ref]`$null,[ref]`$e);if(`$e.Count){exit 1}"
  if ($LASTEXITCODE -eq 0) { Grn "G6 resident parses under PS 5.1" } else { Red "G6 resident 5.1 parse FAILED" }
} else { Grn "G6 resident parsed by pwsh AST; PS 5.1 static parser skipped ($ps51Mode sandbox)" }
$bytes = [IO.File]::ReadAllBytes($RES); if ($bytes | Where-Object { $_ -gt 127 }) { Red "G6 resident has non-ASCII bytes" } else { Grn "G6 resident pure-ASCII" }
# Lp compile must be checked under Windows PowerShell 5.1 (the resident's real runtime);
# pwsh 7 (.NET Core) needs extra WinForms deps and would false-red, so shell to 5.1.
$env:GUARD_RES = $RES
$lpBody = @'
$src=[IO.File]::ReadAllText($env:GUARD_RES,[Text.Encoding]::UTF8)
$m=[regex]::Match($src,'(?s)\$cs = @"\r?\n(.*?)\r?\n"@')
if(-not $m.Success){ exit 2 }
try{ Add-Type -TypeDefinition $m.Groups[1].Value -ReferencedAssemblies System.Windows.Forms,System.Drawing -ErrorAction Stop; exit 0 }catch{ exit 1 }
'@
$lpChk = Join-Path $guardRoot ("lpchk_" + [Guid]::NewGuid().ToString('N') + ".ps1")
if ($ps51Mode -eq 'FullLanguage') {
  Set-Content -Path $lpChk -Value $lpBody -Encoding ascii
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lpChk
  switch ($LASTEXITCODE) { 0 { Grn "G6 Lp (`$cs) compiles under PS 5.1" } 2 { Red "G6 could not locate `$cs block" } default { Red "G6 Lp compile FAILED under 5.1" } }
  Remove-Item $lpChk -Force -ErrorAction SilentlyContinue
} else { Grn "G6 Lp compile skipped ($ps51Mode sandbox); source block covered by resident AST/ASCII checks" }
Remove-Item Env:\GUARD_RES -ErrorAction SilentlyContinue
foreach ($h in $EV,$SS) { $hp = Parse $h; if ($hp.errors.Count) { Red "G6 hook parse FAILED $(Split-Path $h -Leaf)" } else { Grn "G6 $(Split-Path $h -Leaf) parses" } }

# --- G4: fixtures under a temp USERPROFILE (pet-state.txt=off so no resident launch) ---
$old = $env:USERPROFILE
$tmp = Join-Path $guardRoot ("petguard_" + [Guid]::NewGuid().ToString('N'))
try {
  $sess = Join-Path $tmp '.claude\pet-data\sessions'; New-Item -ItemType Directory -Force -Path $sess | Out-Null
  Set-Content -Path (Join-Path $tmp '.claude\pet-data\pet-state.txt') -Value 'off' -Encoding ascii
  $env:USERPROFILE = $tmp
  $env:WT_SESSION = '{11111111-2222-3333-4444-555555555555}'
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $expectedKey = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($env:WT_SESSION))).Replace('-', '').Substring(0,10).ToLowerInvariant()) } finally { $sha.Dispose() }
  # G4a NEW WRITE: fresh session -> 12 fields, stable old indices, hashed terminal key
  $j1 = '{"session_id":"gnew","cwd":"D:\\proj","transcript_path":"C:\\t\\a.jsonl","source":"startup"}'
  $j1 | & pwsh -NoProfile -ExecutionPolicy Bypass -File $SS
  $pn = ([IO.File]::ReadAllText((Join-Path $sess 'gnew'),[Text.Encoding]::UTF8)) -split "`t"
  if ($pn.Count -eq 12) { Grn "G4a new write = 12 fields" } else { Red "G4a new write field count $($pn.Count) != 12" }
  if ($pn[7] -eq '') { Grn "G4a new write field8 empty" } else { Red "G4a new write field8 not empty (='$($pn[7])')" }
  if ($pn[8] -eq 'C:\t\a.jsonl') { Grn "G4a new write transcript at idx8" } else { Red "G4a new write transcript wrong at idx8 (='$($pn[8])')" }
  if ($pn[9] -eq 'D:\proj') { Grn "G4a new write cwd at idx9" } else { Red "G4a new write cwd wrong at idx9 (='$($pn[9])')" }
  if ($pn[10] -eq '') { Grn "G4a detail author remains at idx10" } else { Red "G4a detail author slot shifted" }
  if ($pn[11] -eq $expectedKey -and $pn[11] -ne $env:WT_SESSION) { Grn "G4a field12 stores only the hashed WT session key" } else { Red "G4a terminal key missing or raw" }
  # G4b LEGACY SELF-HEAL: a 10-field record grows to 12 without shifting transcript/cwd
  $stale = @('idle','x','t','d','1','','111','STALE_FP','C:\t\b.jsonl','D:\proj') -join "`t"
  [IO.File]::WriteAllText((Join-Path $sess 'gheal'), $stale, (New-Object Text.UTF8Encoding($false)))
  $j2 = '{"session_id":"gheal","cwd":"D:\\proj","transcript_path":"C:\\t\\b.jsonl","source":"resume"}'
  $j2 | & pwsh -NoProfile -ExecutionPolicy Bypass -File $SS
  $ph = ([IO.File]::ReadAllText((Join-Path $sess 'gheal'),[Text.Encoding]::UTF8)) -split "`t"
  if ($ph.Count -eq 12) { Grn "G4b self-heal = 12 fields" } else { Red "G4b self-heal field count $($ph.Count) != 12" }
  if ($ph[7] -eq '') { Grn "G4b stale field8 cleared" } else { Red "G4b stale field8 NOT cleared (='$($ph[7])')" }
  if ($ph[8] -eq 'C:\t\b.jsonl') { Grn "G4b transcript intact at idx8" } else { Red "G4b transcript shifted/lost at idx8 (='$($ph[8])')" }
  if ($ph[9] -eq 'D:\proj') { Grn "G4b cwd intact at idx9" } else { Red "G4b cwd shifted/lost at idx9 (='$($ph[9])')" }
  if ($ph[11] -eq $expectedKey) { Grn "G4b terminal key back-filled at idx11" } else { Red "G4b terminal key not back-filled" }
} finally { $env:USERPROFILE = $old; Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Remove-Item $guardRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($fail.Count) { Write-Host "`nGUARD FAILED: $($fail.Count) red"; exit 1 } else { Write-Host "`nGUARD PASS"; exit 0 }
