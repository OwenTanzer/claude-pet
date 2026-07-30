param(
  [ValidateSet('new','waxing-crescent','first-quarter','waxing-gibbous','full','waning-gibbous','last-quarter','waning-crescent')]
  [string]$DefaultPhase = 'waning-gibbous'
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

# lives in tools/ (dev-only); writes the sprites into the sibling pet/ dir (the shipped assets)
$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'pet'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

function B([int]$r,[int]$g2,[int]$b,[int]$a=255){ New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a,$r,$g2,$b)) }
function P([int]$r,[int]$g2,[int]$b,[single]$w=3){ New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($r,$g2,$b)), $w }

# Moonlit-warm palette
$moon     = B 242 190 76       # harvest gold
$moonHot  = B 255 208 92       # brighter gold (excited)
$moonShade = B 218 151 54      # crater / lower-edge shading
$moonLine = P 151 99 45 5
$night    = B 42 49 68          # moon's unlit face
$nightSpot = B 62 72 98         # subtle shadow-side craters
$eyeDk   = B 58 52 46
$eyeLine = P 58 52 46 9; $eyeLine.StartCap='Round'; $eyeLine.EndCap='Round'
$smile   = P 70 60 52 7; $smile.StartCap='Round'; $smile.EndCap='Round'
$blush   = B 236 150 120 150
$gold    = B 245 190 90
$mouthB  = B 95 60 55
$eyeShine = B 255 255 255
$featureLt = B 232 236 255
$eyeLineLt = P 232 236 255 9; $eyeLineLt.StartCap='Round'; $eyeLineLt.EndCap='Round'
$smileLt = P 232 236 255 7; $smileLt.StartCap='Round'; $smileLt.EndCap='Round'
$blushLt = B 141 130 184 220

function Star4($g,$cx,$cy,$s,$brush){
  $i = $s * 0.36
  $p = New-Object 'System.Drawing.Point[]' 8
  $p[0]=New-Object System.Drawing.Point([int]$cx,[int]($cy-$s))
  $p[1]=New-Object System.Drawing.Point([int]($cx+$i),[int]($cy-$i))
  $p[2]=New-Object System.Drawing.Point([int]($cx+$s),[int]$cy)
  $p[3]=New-Object System.Drawing.Point([int]($cx+$i),[int]($cy+$i))
  $p[4]=New-Object System.Drawing.Point([int]$cx,[int]($cy+$s))
  $p[5]=New-Object System.Drawing.Point([int]($cx-$i),[int]($cy+$i))
  $p[6]=New-Object System.Drawing.Point([int]($cx-$s),[int]$cy)
  $p[7]=New-Object System.Drawing.Point([int]($cx-$i),[int]($cy-$i))
  $g.FillPolygon($brush,$p)
}

function Draw-Face($g,$eyes,$excited,$fx,$fy,$eyeBrush,$eyePen,$smilePen,$blushBrush,$mouthBrush,$shineBrush){
  switch ($eyes) {
    'open' {
      $g.FillEllipse($eyeBrush, ($fx-52), ($fy-24), 28, 36)
      $g.FillEllipse($eyeBrush, ($fx+24), ($fy-24), 28, 36)
      $g.FillEllipse($shineBrush, ($fx-44), ($fy-16), 10, 10)
      $g.FillEllipse($shineBrush, ($fx+32), ($fy-16), 10, 10)
    }
    'blink' {
      $g.DrawArc($eyePen, ($fx-52), ($fy-12), 28, 16, 180, 180)
      $g.DrawArc($eyePen, ($fx+24), ($fy-12), 28, 16, 180, 180)
    }
    'happy' {
      $g.DrawArc($eyePen, ($fx-54), ($fy-20), 30, 25, 0, 180)
      $g.DrawArc($eyePen, ($fx+24), ($fy-20), 30, 25, 0, 180)
    }
  }
  $g.FillEllipse($blushBrush, ($fx-67), ($fy+11), 32, 18)
  $g.FillEllipse($blushBrush, ($fx+35), ($fy+11), 32, 18)
  if ($excited) { $g.FillEllipse($mouthBrush, ($fx-14), ($fy+20), 28, 23) }
  else { $g.DrawArc($smilePen, ($fx-27), ($fy+10), 54, 34, 20, 140) }
}

function New-ShadowRegion([string]$phase, $outerMoon) {
  $shadow = New-Object System.Drawing.Region($outerMoon)
  $shape = $null
  switch ($phase) {
    'new' { return $shadow }
    'full' { $shadow.Exclude($outerMoon); return $shadow }
    'first-quarter' {
      $shadow.Intersect((New-Object System.Drawing.RectangleF(58, 48, 123, 264)))
      return $shadow
    }
    'last-quarter' {
      $shadow.Intersect((New-Object System.Drawing.RectangleF(181, 48, 123, 264)))
      return $shadow
    }
    'waxing-crescent' {
      $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
      $shape.AddEllipse(10, 48, 246, 264)
      $shadow.Intersect($shape)
    }
    'waning-crescent' {
      $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
      $shape.AddEllipse(106, 48, 246, 264)
      $shadow.Intersect($shape)
    }
    'waxing-gibbous' {
      $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
      $shape.AddEllipse(106, 48, 246, 264)
      $shadow.Exclude($shape)
    }
    'waning-gibbous' {
      $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
      $shape.AddEllipse(10, 48, 246, 264)
      $shadow.Exclude($shape)
    }
  }
  if ($shape) { $shape.Dispose() }
  return $shadow
}

function Make-Frame([string]$phase, [string]$eyes, [bool]$excited, [string]$outDir, [string]$outFile){
  $W = 360; $H = 360
  $cx = 180; $cy = 184
  $fx = 180; $fy = 184
  $bmp = New-Object System.Drawing.Bitmap($W, $H)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)

  # Begin with a full warm disk, then add the unlit region for the chosen phase.
  # The illuminated side follows the Northern Hemisphere convention: waxing on
  # the right, waning on the left.
  $mb = if ($excited) { $moonHot } else { $moon }
  $outerMoon = New-Object System.Drawing.Drawing2D.GraphicsPath
  $outerMoon.AddEllipse(58, 48, 246, 264)
  $shadowRegion = New-ShadowRegion $phase $outerMoon
  $lightRegion = New-Object System.Drawing.Region($outerMoon)
  $lightRegion.Exclude($shadowRegion)
  $g.FillPath($mb, $outerMoon)
  $g.FillRegion($night, $shadowRegion)

  # Soft crater marks keep the body readable as a moon at small desktop sizes.
  $lightClip = $g.Save()
  $g.SetClip($lightRegion, [System.Drawing.Drawing2D.CombineMode]::Replace)
  $g.FillEllipse($moonShade, 78, 91, 26, 38)
  $g.FillEllipse($moonShade, 90, 258, 34, 22)
  $g.FillEllipse($moonShade, 157, 286, 20, 14)
  $g.FillEllipse($moonShade, 252, 92, 22, 29)
  $g.FillEllipse($moonShade, 245, 246, 28, 17)
  $g.Restore($lightClip)

  # Cool, low-contrast texture remains visible on the unlit face.
  $shadowClip = $g.Save()
  $g.SetClip($shadowRegion, [System.Drawing.Drawing2D.CombineMode]::Replace)
  $g.FillEllipse($nightSpot, 82, 104, 24, 17)
  $g.FillEllipse($nightSpot, 98, 242, 20, 27)
  $g.FillEllipse($nightSpot, 235, 86, 27, 18)
  $g.FillEllipse($nightSpot, 252, 214, 20, 27)
  $g.Restore($shadowClip)

  # Draw once in dark ink, then redraw only the shadowed portion in cream.
  # Clipping makes crossing strokes invert exactly at the moon's terminator.
  Draw-Face $g $eyes $excited $fx $fy $eyeDk $eyeLine $smile $blush $mouthB $eyeShine
  $faceClip = $g.Save()
  $g.SetClip($shadowRegion, [System.Drawing.Drawing2D.CombineMode]::Replace)
  Draw-Face $g $eyes $excited $fx $fy $featureLt $eyeLineLt $smileLt $blushLt $featureLt $eyeDk
  $g.Restore($faceClip)

  # A single outer contour keeps every phase reading as the same character.
  $g.DrawPath($moonLine, $outerMoon)

  # sparkles when excited
  if ($excited) {
    Star4 $g ($cx+96) ($cy-86) 16 $gold
    Star4 $g ($cx-104) ($cy-40) 12 $gold
    Star4 $g ($cx+108) ($cy+44) 10 $gold
  }

  $g.Dispose()
  $shadowRegion.Dispose()
  $lightRegion.Dispose()
  $outerMoon.Dispose()
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
  $out = Join-Path $outDir $outFile
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  "Saved: $out ($((Get-Item $out).Length) bytes)"
}

$phases = @('new','waxing-crescent','first-quarter','waxing-gibbous','full','waning-gibbous','last-quarter','waning-crescent')
foreach ($phase in $phases) {
  $phaseDir = Join-Path (Join-Path $dir 'phases') $phase
  Make-Frame $phase 'open'  $false $phaseDir 'claude-idle.png'
  Make-Frame $phase 'blink' $false $phaseDir 'claude-blink.png'
  Make-Frame $phase 'happy' $true  $phaseDir 'claude-happy.png'
}

# Keep a useful fallback set at the historical top-level paths. SessionStart
# replaces these with the calculated phase in the writable pet-data directory.
$defaultDir = Join-Path (Join-Path $dir 'phases') $DefaultPhase
foreach ($name in 'claude-idle.png','claude-blink.png','claude-happy.png') {
  Copy-Item (Join-Path $defaultDir $name) (Join-Path $dir $name) -Force
}
