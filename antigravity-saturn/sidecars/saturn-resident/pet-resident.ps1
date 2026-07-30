param(
  [switch]$SmokeTest,
  [switch]$CompileTest,
  [switch]$CardModelTest,
  [string]$DataRoot
)

$ErrorActionPreference = 'SilentlyContinue'

$pluginRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$assetRoot = Join-Path $pluginRoot 'assets'
if (-not $DataRoot) {
  if ($env:SATURN_DATA_DIR) { $DataRoot = $env:SATURN_DATA_DIR }
  else { $DataRoot = Join-Path $env:USERPROFILE '.gemini\antigravity-saturn' }
}
$eventsDir = Join-Path $DataRoot 'events'
$pidPath = Join-Path $DataRoot 'resident.pid'
$posPath = Join-Path $DataRoot 'position.txt'
$logPath = Join-Path $DataRoot 'resident.log'
$collapsePath = Join-Path $DataRoot 'card-collapsed.flag'
$dismissDir = Join-Path $DataRoot 'dismissed'
$namesDir = Join-Path $DataRoot 'names'

function Read-Utf8([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    try { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } catch {}
  }
  return ''
}

function Write-Utf8([string]$Path, [string]$Value) {
  [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
}

function Write-Log([string]$Message) {
  try {
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 262144) {
      Remove-Item -LiteralPath $logPath -Force
    }
    Add-Content -LiteralPath $logPath -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
  } catch {}
}

$assetNames = @('saturn-idle.png', 'saturn-working.png', 'saturn-done.png')
if ($SmokeTest) {
  Add-Type -AssemblyName System.Drawing
  $assets = @()
  $ok = $true
  foreach ($name in $assetNames) {
    $path = Join-Path $assetRoot $name
    $entry = [ordered]@{ name = $name; exists = (Test-Path -LiteralPath $path); width = 0; height = 0; cornerAlpha = @() }
    if ($entry.exists) {
      try {
        $image = [System.Drawing.Bitmap]::FromFile($path)
        $entry.width = $image.Width; $entry.height = $image.Height
        $entry.cornerAlpha = @($image.GetPixel(0,0).A, $image.GetPixel($image.Width-1,0).A, $image.GetPixel(0,$image.Height-1).A, $image.GetPixel($image.Width-1,$image.Height-1).A)
        if ($image.Width -ne 360 -or $image.Height -ne 360 -or @($entry.cornerAlpha | Where-Object { $_ -ne 0 }).Count -gt 0) { $ok = $false }
        $image.Dispose()
      } catch { $ok = $false }
    } else { $ok = $false }
    $assets += [pscustomobject]$entry
  }
  [pscustomobject]@{
    ok = $ok
    mutex = 'Local\AntigravitySaturnPetResidentV1'
    dataRoot = $DataRoot
    pidFile = $pidPath
    positionFile = $posPath
    assets = $assets
  } | ConvertTo-Json -Depth 5
  if ($ok) { exit 0 } else { exit 1 }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName Microsoft.VisualBasic

$native = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class SaturnWindow : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000; // WS_EX_LAYERED
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            return cp;
        }
    }
}

public class SaturnCardWindow : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            return cp;
        }
    }
}

public static class SaturnNative {
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    public static void EnableDpi() {
        try { SetProcessDpiAwarenessContext((IntPtr)(-4)); }
        catch { try { SetProcessDPIAware(); } catch {} }
    }

    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void KeepTopmost(IntPtr h) {
        try { SetWindowPos(h, (IntPtr)(-1), 0, 0, 0, 0, 0x0013); } catch {}
    }

    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int command);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    public static bool IsValidWindow(IntPtr h) { try { return h != IntPtr.Zero && IsWindow(h); } catch { return false; } }

    public static bool Activate(IntPtr h) {
        try {
            if (h == IntPtr.Zero) return false;
            if (IsIconic(h)) ShowWindow(h, 9);
            if (SetForegroundWindow(h)) return true;
            uint foregroundPid;
            uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out foregroundPid);
            uint currentThread = GetCurrentThreadId();
            if (foregroundThread != 0 && foregroundThread != currentThread) {
                AttachThreadInput(currentThread, foregroundThread, true);
                bool ok = SetForegroundWindow(h);
                AttachThreadInput(currentThread, foregroundThread, false);
                return ok;
            }
        } catch {}
        return false;
    }

    delegate bool EnumWindowsProc(IntPtr h, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder text, int max);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT rect);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    public static string WindowTitle(IntPtr h) {
        try { StringBuilder text = new StringBuilder(512); GetWindowText(h, text, text.Capacity); return text.ToString(); }
        catch { return ""; }
    }
    public static int WindowPid(IntPtr h) {
        try { uint pid; GetWindowThreadProcessId(h, out pid); return (int)pid; } catch { return 0; }
    }

    public static IntPtr FindAntigravityWindow() {
        IntPtr best = IntPtr.Zero;
        long bestArea = 0;
        try {
            EnumWindows((h, l) => {
                if (!IsWindowVisible(h) || GetWindowTextLength(h) == 0) return true;
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                string processName = "";
                try { processName = Process.GetProcessById((int)pid).ProcessName; } catch {}
                StringBuilder titleBuffer = new StringBuilder(512);
                GetWindowText(h, titleBuffer, titleBuffer.Capacity);
                string title = titleBuffer.ToString();
                bool processMatch = processName.StartsWith("Antigravity", StringComparison.OrdinalIgnoreCase);
                if (!processMatch) return true;
                RECT rect;
                long area = 1;
                if (GetWindowRect(h, out rect)) area = Math.Max(1, (long)(rect.Right - rect.Left) * (rect.Bottom - rect.Top));
                if (area > bestArea) { bestArea = area; best = h; }
                return true;
            }, IntPtr.Zero);
        } catch {}
        return best;
    }

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; public POINT(int x, int y) { X=x; Y=y; } }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx, cy; public SIZE(int x, int y) { cx=x; cy=y; } }
    [StructLayout(LayoutKind.Sequential, Pack=1)] public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [DllImport("user32.dll", SetLastError=true)] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr dstDc, ref POINT dstPoint, ref SIZE size, IntPtr srcDc, ref POINT srcPoint, int colorKey, ref BLENDFUNCTION blend, int flags);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);

    public static Bitmap Prepare(string path, int width, int height) {
        Bitmap result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (Graphics graphics = Graphics.FromImage(result)) {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            using (Image source = Image.FromFile(path)) graphics.DrawImage(source, 0, 0, width, height);
        }
        BitmapData data = result.LockBits(new Rectangle(0,0,width,height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int length = data.Stride * data.Height;
        byte[] pixels = new byte[length];
        Marshal.Copy(data.Scan0, pixels, 0, length);
        for (int index=0; index<length; index+=4) {
            byte alpha = pixels[index+3];
            pixels[index] = (byte)(pixels[index] * alpha / 255);
            pixels[index+1] = (byte)(pixels[index+1] * alpha / 255);
            pixels[index+2] = (byte)(pixels[index+2] * alpha / 255);
        }
        Marshal.Copy(pixels, 0, data.Scan0, length);
        result.UnlockBits(data);
        return result;
    }

    public static void SetBitmap(IntPtr hwnd, Bitmap bitmap, int x, int y) {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memoryDc = CreateCompatibleDC(screenDc);
        IntPtr hBitmap = IntPtr.Zero;
        IntPtr previous = IntPtr.Zero;
        try {
            hBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
            previous = SelectObject(memoryDc, hBitmap);
            SIZE size = new SIZE(bitmap.Width, bitmap.Height);
            POINT source = new POINT(0,0);
            POINT destination = new POINT(x,y);
            BLENDFUNCTION blend = new BLENDFUNCTION();
            blend.SourceConstantAlpha = 255; blend.AlphaFormat = 1;
            UpdateLayeredWindow(hwnd, screenDc, ref destination, ref size, memoryDc, ref source, 0, ref blend, 2);
        } finally {
            ReleaseDC(IntPtr.Zero, screenDc);
            if (previous != IntPtr.Zero) SelectObject(memoryDc, previous);
            if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
            DeleteDC(memoryDc);
        }
    }
}
"@

Add-Type -TypeDefinition $native -ReferencedAssemblies System.Windows.Forms, System.Drawing
[SaturnNative]::EnableDpi()

if ($CompileTest) {
  Write-Output '{"ok":true,"compiled":true}'
  exit 0
}

if (-not (Test-Path -LiteralPath $DataRoot)) { New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null }
if (-not (Test-Path -LiteralPath $eventsDir)) { New-Item -ItemType Directory -Force -Path $eventsDir | Out-Null }
if (-not (Test-Path -LiteralPath $dismissDir)) { New-Item -ItemType Directory -Force -Path $dismissDir | Out-Null }
if (-not (Test-Path -LiteralPath $namesDir)) { New-Item -ItemType Directory -Force -Path $namesDir | Out-Null }

if (-not $CardModelTest) {
  $script:residentMutex = New-Object System.Threading.Mutex($false, 'Local\AntigravitySaturnPetResidentV1')
  $acquired = $false
  try { $acquired = $script:residentMutex.WaitOne(0) }
  catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { exit 0 }
}

function Get-DismissPath([string]$SessionId) { return (Join-Path $dismissDir ($SessionId + '.dismiss')) }
function Get-NamePath([string]$SessionId) { return (Join-Path $namesDir ($SessionId + '.name')) }

function Get-SessionStatuses {
  $latest = @{}
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  foreach ($file in @(Get-ChildItem -LiteralPath $eventsDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
    $event = $null
    try { $event = (Read-Utf8 $file.FullName) | ConvertFrom-Json } catch { continue }
    if (-not $event) { continue }
    $sid = [string]$event.conversationKey
    if ($sid -notmatch '^[0-9a-f]{20}$' -or $latest.ContainsKey($sid)) { continue }
    $timestampMs = 0L
    if (-not [long]::TryParse(($event.timestampMs + ''), [ref]$timestampMs)) { continue }
    $age = $nowMs - $timestampMs; if ($age -lt 0) { $age = 0 }
    $hostPid = 0
    if ($event.PSObject.Properties['hostPid']) { [void][int]::TryParse(($event.hostPid + ''), [ref]$hostPid) }
    elseif ($event.PSObject.Properties['hookParentPid']) { [void][int]::TryParse(($event.hookParentPid + ''), [ref]$hostPid) }
    $terminalPid = 0
    if ($event.PSObject.Properties['terminalPid']) { [void][int]::TryParse(($event.terminalPid + ''), [ref]$terminalPid) }
    $terminalKey = ''
    if ($event.PSObject.Properties['terminalKey'] -and (($event.terminalKey + '') -match '^[0-9a-f]{10}$')) { $terminalKey = [string]$event.terminalKey }
    $state = 'idle'
    switch ([string]$event.state) {
      'done' { if ($age -le 10000) { $state = 'done' } }
      'attention' { if ($age -le 1800000) { $state = 'attention' } }
      'working' { if ($age -le 1800000) { $state = 'working' } }
    }
    $latest[$sid] = [pscustomobject]@{
      sessionId = $sid; state = $state; timestampMs = $timestampMs
      hostPid = $hostPid; terminalPid = $terminalPid; terminalKey = $terminalKey
      eventId = $file.Name
    }
  }
  return @($latest.Values | Sort-Object timestampMs -Descending)
}

function Get-SessionName([string]$SessionId) {
  $custom = (Read-Utf8 (Get-NamePath $SessionId)).Trim()
  if ($custom) { return $custom }
  if ($SessionId -match '^[0-9a-f]{20}$') { return ('Antigravity CLI [{0}]' -f $SessionId.Substring(0, 4)) }
  return 'Antigravity CLI'
}

function Test-SessionDismissed($Status) {
  if (-not $Status) { return $false }
  $dismissedEvent = (Read-Utf8 (Get-DismissPath $Status.sessionId)).Trim()
  return [bool]($dismissedEvent -and $dismissedEvent -eq $Status.eventId)
}

if ($CardModelTest) {
  $model = @()
  foreach ($status in @(Get-SessionStatuses)) {
    $model += [pscustomobject]@{
      sessionId = $status.sessionId; state = $status.state; timestampMs = $status.timestampMs
      hostPid = $status.hostPid; terminalPid = $status.terminalPid; terminalKey = $status.terminalKey
      eventId = $status.eventId; title = Get-SessionName $status.sessionId
      dismissed = Test-SessionDismissed $status
    }
  }
  @($model) | ConvertTo-Json -Depth 4
  exit 0
}

$desktopGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$scale = $desktopGraphics.DpiX / 96.0
$desktopGraphics.Dispose()
$size = [int](148 * $scale)
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:defaultX = $workArea.Right - (2 * $size) - [int](72 * $scale)
$script:defaultY = $workArea.Bottom - $size - [int](42 * $scale)
$script:x = $script:defaultX
$script:y = $script:defaultY
if (Test-Path -LiteralPath $posPath) {
  $parts = ((Read-Utf8 $posPath) + '').Trim() -split ','
  $px = 0; $py = 0
  if ($parts.Count -eq 2 -and [int]::TryParse($parts[0], [ref]$px) -and [int]::TryParse($parts[1], [ref]$py)) {
    $virtual = [System.Windows.Forms.SystemInformation]::VirtualScreen
    if ($px -ge $virtual.Left -and $px -le ($virtual.Right - 40) -and $py -ge $virtual.Top -and $py -le ($virtual.Bottom - 40)) {
      $script:x = $px; $script:y = $py
    }
  }
}

$script:frames = @{
  idle = [SaturnNative]::Prepare((Join-Path $assetRoot 'saturn-idle.png'), $size, $size)
  working = [SaturnNative]::Prepare((Join-Path $assetRoot 'saturn-working.png'), $size, $size)
  done = [SaturnNative]::Prepare((Join-Path $assetRoot 'saturn-done.png'), $size, $size)
}

$form = New-Object SaturnWindow
$form.FormBorderStyle = 'None'
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.Bounds = New-Object System.Drawing.Rectangle($script:x, $script:y, $size, $size)
$form.Text = ''

$MAXCARDS = 3
$cardWidth = [int](292 * $scale)
$cardHeight = [int](62 * $scale)
$cardGap = [int](7 * $scale)
$script:cards = @(); $script:cardTitles = @(); $script:cardDots = @()
$script:cardStates = @(); $script:cardEdits = @(); $script:cardCloses = @(); $script:cardMore = @()
$script:rowSids = New-Object 'string[]' $MAXCARDS
$script:visibleCardCount = 0

for ($i = 0; $i -lt $MAXCARDS; $i++) {
  $card = New-Object SaturnCardWindow
  $card.FormBorderStyle = 'None'; $card.ShowInTaskbar = $false; $card.StartPosition = 'Manual'; $card.TopMost = $true
  $card.Size = New-Object System.Drawing.Size($cardWidth, $cardHeight)
  $card.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 245); $card.Tag = $i
  $roundPath = New-Object System.Drawing.Drawing2D.GraphicsPath
  $radius = [int](18 * $scale)
  $roundPath.AddArc(0, 0, $radius, $radius, 180, 90)
  $roundPath.AddArc($cardWidth-$radius-1, 0, $radius, $radius, 270, 90)
  $roundPath.AddArc($cardWidth-$radius-1, $cardHeight-$radius-1, $radius, $radius, 0, 90)
  $roundPath.AddArc(0, $cardHeight-$radius-1, $radius, $radius, 90, 90)
  $roundPath.CloseFigure(); $card.Region = New-Object System.Drawing.Region($roundPath); $roundPath.Dispose()

  $title = New-Object System.Windows.Forms.Label
  $title.AutoSize = $false; $title.Location = New-Object System.Drawing.Point([int](18*$scale), [int](8*$scale))
  $title.Size = New-Object System.Drawing.Size([int](210*$scale), [int](24*$scale))
  $title.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
  $title.ForeColor = [System.Drawing.Color]::FromArgb(44, 43, 48); $title.BackColor = [System.Drawing.Color]::Transparent
  $title.Cursor = [System.Windows.Forms.Cursors]::Hand; $title.Tag = $i

  $dot = New-Object System.Windows.Forms.Label
  $dot.AutoSize = $false; $dot.Location = New-Object System.Drawing.Point([int](18*$scale), [int](34*$scale))
  $dot.Size = New-Object System.Drawing.Size([int](14*$scale), [int](20*$scale))
  $dot.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 9, [System.Drawing.FontStyle]::Bold)
  $dot.Text = [string][char]0x25CF; $dot.BackColor = [System.Drawing.Color]::Transparent
  $dot.Cursor = [System.Windows.Forms.Cursors]::Hand; $dot.Tag = $i

  $stateLabel = New-Object System.Windows.Forms.Label
  $stateLabel.AutoSize = $false; $stateLabel.Location = New-Object System.Drawing.Point([int](36*$scale), [int](34*$scale))
  $stateLabel.Size = New-Object System.Drawing.Size([int](178*$scale), [int](21*$scale))
  $stateLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
  $stateLabel.BackColor = [System.Drawing.Color]::Transparent; $stateLabel.Cursor = [System.Windows.Forms.Cursors]::Hand; $stateLabel.Tag = $i

  $edit = New-Object System.Windows.Forms.Label
  $edit.AutoSize = $false; $edit.Location = New-Object System.Drawing.Point([int](238*$scale), [int](7*$scale))
  $edit.Size = New-Object System.Drawing.Size([int](20*$scale), [int](20*$scale))
  $edit.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 9)
  $edit.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 126); $edit.BackColor = [System.Drawing.Color]::Transparent
  $edit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $edit.Text = [string][char]0x270E; $edit.Cursor = [System.Windows.Forms.Cursors]::Hand; $edit.Tag = $i

  $close = New-Object System.Windows.Forms.Label
  $close.AutoSize = $false; $close.Location = New-Object System.Drawing.Point([int](263*$scale), [int](7*$scale))
  $close.Size = New-Object System.Drawing.Size([int](20*$scale), [int](20*$scale))
  $close.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $close.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 155); $close.BackColor = [System.Drawing.Color]::Transparent
  $close.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $close.Text = 'x'; $close.Cursor = [System.Windows.Forms.Cursors]::Hand; $close.Tag = $i

  $more = New-Object System.Windows.Forms.Label
  $more.AutoSize = $false; $more.Location = New-Object System.Drawing.Point([int](226*$scale), [int](35*$scale))
  $more.Size = New-Object System.Drawing.Size([int](52*$scale), [int](19*$scale))
  $more.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
  $more.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 150); $more.BackColor = [System.Drawing.Color]::Transparent
  $more.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight

  [void]$card.Controls.Add($title); [void]$card.Controls.Add($dot); [void]$card.Controls.Add($stateLabel)
  [void]$card.Controls.Add($edit); [void]$card.Controls.Add($close); [void]$card.Controls.Add($more)
  $script:cards += $card; $script:cardTitles += $title; $script:cardDots += $dot
  $script:cardStates += $stateLabel; $script:cardEdits += $edit; $script:cardCloses += $close; $script:cardMore += $more
}

function Get-StateRank([string]$State) {
  switch ($State) { 'attention' { return 0 }; 'working' { return 1 }; 'done' { return 2 }; default { return 9 } }
}

function Refresh-SessionModel {
  $script:sessions = @(Get-SessionStatuses)
  $script:sessionsById = @{}
  foreach ($status in $script:sessions) { $script:sessionsById[$status.sessionId] = $status }
  $script:latestSid = $(if ($script:sessions.Count -gt 0) { [string]$script:sessions[0].sessionId } else { '' })
  if (@($script:sessions | Where-Object { $_.state -eq 'attention' }).Count -gt 0) { $script:state = 'attention' }
  elseif (@($script:sessions | Where-Object { $_.state -eq 'working' }).Count -gt 0) { $script:state = 'working' }
  elseif (@($script:sessions | Where-Object { $_.state -eq 'done' }).Count -gt 0) { $script:state = 'done' }
  else { $script:state = 'idle' }
}

function Place-Cards {
  $count = $script:visibleCardCount
  if ($count -le 0) { return }
  $cx = $script:x - $cardWidth - $cardGap
  if ($cx -lt $workArea.Left) { $cx = $script:x + $size + $cardGap }
  $total = ($count * $cardHeight) + (($count - 1) * $cardGap)
  $startY = $script:y + [int](($size - $total) / 2)
  for ($i = 0; $i -lt $count; $i++) {
    $script:cards[$i].Location = New-Object System.Drawing.Point($cx, ($startY + ($i * ($cardHeight + $cardGap))))
  }
}

function Update-Cards {
  $active = @($script:sessions | Where-Object { $_.state -ne 'idle' -and -not (Test-SessionDismissed $_) } |
    Sort-Object @{Expression={ Get-StateRank $_.state }}, @{Expression={$_.timestampMs};Descending=$true})
  $shown = @($active | Select-Object -First $MAXCARDS)
  $script:visibleCardCount = $shown.Count
  for ($i = 0; $i -lt $MAXCARDS; $i++) {
    $card = $script:cards[$i]
    if ($script:cardCollapsed -or $i -ge $shown.Count) {
      $script:rowSids[$i] = ''
      if ($card.Visible) { $card.Hide() }
      continue
    }
    $status = $shown[$i]; $script:rowSids[$i] = [string]$status.sessionId
    switch ($status.state) {
      'working' { $label = 'Working'; $color = [System.Drawing.Color]::FromArgb(76, 119, 190) }
      'attention' { $label = 'Needs attention'; $color = [System.Drawing.Color]::FromArgb(214, 139, 45) }
      default { $label = 'Done'; $color = [System.Drawing.Color]::FromArgb(59, 166, 91) }
    }
    $script:cardTitles[$i].Text = Get-SessionName $status.sessionId
    $script:cardDots[$i].ForeColor = $color; $script:cardStates[$i].ForeColor = $color; $script:cardStates[$i].Text = $label
    $script:cardMore[$i].Text = $(if ($i -eq ($MAXCARDS - 1) -and $active.Count -gt $MAXCARDS) { '+' + ($active.Count - $MAXCARDS) } else { '' })
    $card.BackColor = $(if ($script:selectedSid -eq $status.sessionId) { [System.Drawing.Color]::FromArgb(244, 238, 224) } else { [System.Drawing.Color]::FromArgb(250, 249, 245) })
    if (-not $card.Visible) { $card.Show($form) }
  }
  Place-Cards
}

function Toggle-Cards {
  $script:cardCollapsed = -not $script:cardCollapsed
  if ($script:cardCollapsed) { Write-Utf8 $collapsePath '1' }
  elseif (Test-Path -LiteralPath $collapsePath) { Remove-Item -LiteralPath $collapsePath -Force -ErrorAction SilentlyContinue }
  if ($toggleCardItem) { $toggleCardItem.Checked = -not $script:cardCollapsed }
  Update-Cards
  Write-Log ('card-collapsed={0}' -f [int]$script:cardCollapsed)
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$closeItem = $menu.Items.Add('Close Saturn')
$closeItem.add_Click({ [System.Windows.Forms.Application]::Exit() })
$resetItem = $menu.Items.Add('Reset position')
$resetItem.add_Click({
  $script:x = $script:defaultX; $script:y = $script:defaultY
  Write-Utf8 $posPath "$($script:x),$($script:y)"
})
$toggleCardItem = New-Object System.Windows.Forms.ToolStripMenuItem
$toggleCardItem.Text = 'Show status cards'; $toggleCardItem.Checked = -not (Test-Path -LiteralPath $collapsePath)
$toggleCardItem.add_Click({ Toggle-Cards })
[void]$menu.Items.Add($toggleCardItem)

$script:sessions = @(); $script:sessionsById = @{}
$script:latestSid = ''; $script:selectedSid = ''; $script:state = 'idle'
$script:targetCache = @{}
$script:lastModelSig = ''
$script:cardCollapsed = Test-Path -LiteralPath $collapsePath
Refresh-SessionModel
$script:pointerDown = $false
$script:dragging = $false
$script:dragStartX = 0; $script:dragStartY = 0
$script:dragOffsetX = 0; $script:dragOffsetY = 0
$dragSize = [System.Windows.Forms.SystemInformation]::DragSize
$script:dragThresholdX = [Math]::Max(8, [int]($dragSize.Width * 2))
$script:dragThresholdY = [Math]::Max(8, [int]($dragSize.Height * 2))
$script:shakeTicks = 0
$script:frameTick = 0
$script:lastStatePoll = [DateTime]::MinValue
$script:lastTopmost = [DateTime]::MinValue

function Render-Saturn {
  $key = $script:state
  if ($key -eq 'attention') { $key = 'working' }
  if (-not $script:frames.ContainsKey($key)) { $key = 'idle' }
  $bob = 0
  if (-not $script:dragging) {
    $amplitude = if ($key -eq 'working') { 3 } elseif ($key -eq 'done') { 4 } else { 2 }
    $period = if ($key -eq 'working') { 9.0 } elseif ($key -eq 'done') { 7.0 } else { 18.0 }
    $bob = [int]([Math]::Sin($script:frameTick / $period) * $amplitude * $scale)
  }
  $shake = 0
  if ($script:shakeTicks -gt 0) {
    $shake = [int](($(if (($script:shakeTicks % 2) -eq 0) { -6 } else { 6 })) * $scale)
    $script:shakeTicks--
  }
  [SaturnNative]::SetBitmap($form.Handle, $script:frames[$key], $script:x + $shake, $script:y + $bob)
}

function Find-HostWindow([int]$StartPid) {
  if ($StartPid -le 0) { return [IntPtr]::Zero }
  $all = @{}
  foreach ($processInfo in @(Get-CimInstance -Query 'SELECT ProcessId,ParentProcessId,CreationDate FROM Win32_Process' -ErrorAction SilentlyContinue)) {
    $all[[int]$processInfo.ProcessId] = $processInfo
  }
  $current = $StartPid; $childBorn = $null
  for ($depth = 0; $depth -lt 10; $depth++) {
    if ($current -le 0 -or -not $all.ContainsKey($current)) { break }
    $info = $all[$current]
    $born = $null; try { $born = [DateTime]$info.CreationDate } catch {}
    if ($childBorn -and $born -and $born -gt $childBorn.AddSeconds(2)) { break }
    $process = Get-Process -Id $current -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -ne 'WindowsTerminal' -and $process.MainWindowHandle.ToInt64() -ne 0) { return $process.MainWindowHandle }
    if ($born) { $childBorn = $born }
    $current = 0; if ($info.ParentProcessId) { $current = [int]$info.ParentProcessId }
  }
  return [IntPtr]::Zero
}

function Get-TerminalMarker([string]$Key) {
  if ($Key -match '^[0-9a-f]{10}$') { return ('Saturn - Antigravity CLI [{0}]' -f $Key) }
  return 'Saturn - Antigravity CLI'
}

function Find-MarkedTerminalTarget([int]$TerminalPid, [string]$TerminalKey) {
  if ($TerminalPid -le 0 -or $TerminalKey -notmatch '^[0-9a-f]{10}$') { return $null }
  try {
    $rootElement = [System.Windows.Automation.AutomationElement]::RootElement
    $windowCondition = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
      $TerminalPid
    )
    $windows = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $windowCondition)
    $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::TabItem
    )
    $marker = Get-TerminalMarker $TerminalKey
    $matches = @()
    foreach ($windowElement in $windows) {
      $items = $windowElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
      foreach ($item in $items) {
        if ([string]$item.Current.Name -ceq $marker) {
          $matches += @{ Window = [IntPtr]$windowElement.Current.NativeWindowHandle; Tab = $item }
        }
      }
    }
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
  } catch { return $null }
}

function Remember-MarkedTerminalTarget([string]$SessionId, $Status) {
  if (-not $Status) { return $false }
  $target = Find-MarkedTerminalTarget ([int]$Status.terminalPid) ([string]$Status.terminalKey)
  if (-not $target) {
    [void]$script:targetCache.Remove($SessionId)
    return $false
  }
  $script:targetCache[$SessionId] = @{
    TerminalPid = [int]$Status.terminalPid; Key = [string]$Status.terminalKey
    Window = [IntPtr]$target.Window; Tab = $target.Tab
  }
  Write-Log ('target-resolved sid={0} terminalPid={1} hwnd={2} markerMatched=1' -f $SessionId.Substring(0, 6), $Status.terminalPid, ([IntPtr]$target.Window).ToInt64())
  return $true
}

function Select-SessionTerminal([string]$SessionId, $Status) {
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    $cached = $null
    if ($script:targetCache.ContainsKey($SessionId)) {
      $candidate = $script:targetCache[$SessionId]
      if ($candidate.TerminalPid -eq [int]$Status.terminalPid -and $candidate.Key -ceq [string]$Status.terminalKey -and [SaturnNative]::IsValidWindow($candidate.Window)) {
        $cached = $candidate
      } else { [void]$script:targetCache.Remove($SessionId) }
    }
    if (-not $cached) {
      if (-not (Remember-MarkedTerminalTarget $SessionId $Status)) { return [IntPtr]::Zero }
      $cached = $script:targetCache[$SessionId]
    }
    try {
      $pattern = $null
      if ($cached.Tab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        $pattern.Select()
        return [IntPtr]$cached.Window
      }
    } catch {}
    [void]$script:targetCache.Remove($SessionId)
  }
  return [IntPtr]::Zero
}

function Focus-Session([string]$SessionId) {
  if (-not $SessionId -or -not $script:sessionsById.ContainsKey($SessionId)) {
    $script:shakeTicks = 8; Write-Log 'focus no-session'; return
  }
  $status = $script:sessionsById[$SessionId]
  $targetPid = [int]$status.hostPid
  $window = [IntPtr]::Zero
  $tabSelected = $false
  if ([int]$status.terminalPid -gt 0) {
    $window = Select-SessionTerminal $SessionId $status
    $tabSelected = ($window -ne [IntPtr]::Zero)
  } else {
    $window = Find-HostWindow $targetPid
    if ($window -eq [IntPtr]::Zero -and $script:sessions.Count -eq 1) { $window = [SaturnNative]::FindAntigravityWindow() }
  }
  $ok = [SaturnNative]::Activate($window)
  if (-not $ok) { $script:shakeTicks = 8 }
  if ($ok) { $script:selectedSid = $SessionId; Update-Cards }
  Write-Log ('focus sid={0} targetPid={1} hwnd={2} tabSelected={3} ok={4}' -f $SessionId.Substring(0, 6), $targetPid, $window.ToInt64(), [int]$tabSelected, [int]$ok)
}

function Dismiss-SessionCard([int]$Index) {
  if ($Index -lt 0 -or $Index -ge $MAXCARDS) { return }
  $sid = $script:rowSids[$Index]
  if (-not $sid -or -not $script:sessionsById.ContainsKey($sid)) { return }
  $status = $script:sessionsById[$sid]
  Write-Utf8 (Get-DismissPath $sid) ([string]$status.eventId)
  Write-Log ('card-dismissed sid={0}' -f $sid.Substring(0, 6))
  Update-Cards
}

function Rename-SessionCard([int]$Index) {
  if ($Index -lt 0 -or $Index -ge $MAXCARDS) { return }
  $sid = $script:rowSids[$Index]; if (-not $sid) { return }
  $current = Get-SessionName $sid
  $value = [Microsoft.VisualBasic.Interaction]::InputBox('Name this Antigravity session:', 'Rename Saturn card', $current)
  $name = ([string]$value -replace '[\x00-\x1F\x7F]', ' ').Trim()
  if (-not $name) { return }
  if ($name.Length -gt 60) { $name = $name.Substring(0, 60) }
  Write-Utf8 (Get-NamePath $sid) $name
  Write-Log ('card-renamed sid={0}' -f $sid.Substring(0, 6))
  Update-Cards
}

$focusHandler = { param($sender, $event) $idx = [int]$sender.Tag; Focus-Session $script:rowSids[$idx] }
$dismissHandler = { param($sender, $event) Dismiss-SessionCard ([int]$sender.Tag) }
$renameHandler = { param($sender, $event) Rename-SessionCard ([int]$sender.Tag) }
$collapseHandler = { Toggle-Cards }
for ($i = 0; $i -lt $MAXCARDS; $i++) {
  $script:cards[$i].add_Click($focusHandler); $script:cardTitles[$i].add_Click($focusHandler)
  $script:cardDots[$i].add_Click($focusHandler); $script:cardStates[$i].add_Click($focusHandler)
  $script:cardCloses[$i].add_Click($dismissHandler); $script:cardEdits[$i].add_Click($renameHandler)
  $script:cards[$i].add_DoubleClick($collapseHandler); $script:cardTitles[$i].add_DoubleClick($collapseHandler)
  $script:cardStates[$i].add_DoubleClick($collapseHandler)
}
$form.add_DoubleClick($collapseHandler)

$form.add_MouseDown({ param($sender, $event)
  if ($event.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    $script:pointerDown = $true; $script:dragging = $false; $form.Capture = $true
    $cursor = [System.Windows.Forms.Cursor]::Position
    $script:dragStartX = $cursor.X; $script:dragStartY = $cursor.Y
    $script:dragOffsetX = $cursor.X - $script:x; $script:dragOffsetY = $cursor.Y - $script:y
  }
})

$form.add_MouseMove({ param($sender, $event)
  if ($script:pointerDown) {
    $cursor = [System.Windows.Forms.Cursor]::Position
    if (-not $script:dragging -and ([Math]::Abs($cursor.X - $script:dragStartX) -ge $script:dragThresholdX -or [Math]::Abs($cursor.Y - $script:dragStartY) -ge $script:dragThresholdY)) {
      $script:dragging = $true
    }
    if ($script:dragging) {
      $script:x = $cursor.X - $script:dragOffsetX; $script:y = $cursor.Y - $script:dragOffsetY
      Place-Cards; Render-Saturn
    }
  }
})

$form.add_MouseUp({ param($sender, $event)
  if ($event.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:pointerDown) {
    $wasDrag = $script:dragging
    $script:pointerDown = $false; $script:dragging = $false; $form.Capture = $false
    if ($wasDrag) {
      Write-Utf8 $posPath "$($script:x),$($script:y)"
      Write-Log 'gesture=drag'
    } else {
      Write-Log ('gesture=click sid={0}' -f $(if ($script:latestSid) { $script:latestSid.Substring(0, 6) } else { 'none' }))
      Focus-Session $script:latestSid
    }
  } elseif ($event.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
    $menu.Show($form, $form.PointToClient([System.Windows.Forms.Cursor]::Position))
  }
})

$watcher = New-Object System.IO.FileSystemWatcher $eventsDir
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite'
$watcher.SynchronizingObject = $form
$script:stateDirty = $true
$eventHandler = { $script:stateDirty = $true }
$watcher.add_Created($eventHandler); $watcher.add_Changed($eventHandler); $watcher.add_Renamed($eventHandler)
$watcher.EnableRaisingEvents = $true

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60
$timer.add_Tick({
  $now = Get-Date
  $script:frameTick++
  if ($script:stateDirty -or ($now - $script:lastStatePoll).TotalMilliseconds -ge 1000) {
    $script:stateDirty = $false; $script:lastStatePoll = $now
    $status = Get-LatestStatus
    $newState = $status.state
    if ([int]$status.hostPid -gt 0) { $script:targetPid = [int]$status.hostPid }
    if ([int]$status.terminalPid -gt 0 -and [int]$status.terminalPid -ne $script:targetTerminalPid) {
      $script:targetTerminalPid = [int]$status.terminalPid
      $script:targetWindow = [IntPtr]::Zero
      $script:targetTabElement = $null
    }
    if ($status.eventId -and $status.eventId -ne $script:lastEventId) {
      $script:lastEventId = $status.eventId
      $newTerminalKey = [string]$status.terminalKey
      if ($newTerminalKey -ne $script:targetTerminalKey) {
        $script:targetTerminalKey = $newTerminalKey
        $script:targetWindow = [IntPtr]::Zero
        $script:targetTabElement = $null
      }
      $script:targetResolveUntil = $now.AddSeconds(3)
      [void](Remember-MarkedTerminalTarget)
    }
    if ($newState -ne $script:state) {
      Write-Log ("state=$newState")
      $script:state = $newState
      Update-Card
    }
  }
  if ($now -lt $script:targetResolveUntil -and (-not [SaturnNative]::IsValidWindow($script:targetWindow) -or -not $script:targetTabElement)) {
    [void](Remember-MarkedTerminalTarget)
  }
  if (($now - $script:lastTopmost).TotalMilliseconds -ge 2000) {
    $script:lastTopmost = $now
    [SaturnNative]::KeepTopmost($form.Handle)
    if ($card.Visible) { [SaturnNative]::KeepTopmost($card.Handle) }
  }
  Render-Saturn
})

$form.add_Shown({ Render-Saturn; Update-Card; $timer.Start() })
$PID | Set-Content -LiteralPath $pidPath -Encoding ASCII
Write-Log ('resident-start pid={0}' -f $PID)
[System.Windows.Forms.Application]::Run($form)

$timer.Stop(); $timer.Dispose(); $watcher.Dispose(); $menu.Dispose(); $card.Dispose()
foreach ($frame in $script:frames.Values) { try { $frame.Dispose() } catch {} }
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
try { $script:residentMutex.ReleaseMutex() } catch {}
try { $script:residentMutex.Dispose() } catch {}
Write-Log 'resident-stop'
