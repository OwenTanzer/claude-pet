param(
  [string]$Output = (Join-Path (Split-Path $PSScriptRoot -Parent) 'moon-phase-preview.png')
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$phases = @('new','waxing-crescent','first-quarter','waxing-gibbous','full','waning-gibbous','last-quarter','waning-crescent')
$tileW = 210; $tileH = 218; $columns = 4
$canvas = New-Object System.Drawing.Bitmap(($tileW * $columns), ($tileH * 2))
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(247, 246, 242))
$font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$text = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(58, 52, 46))
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center

for ($i = 0; $i -lt $phases.Count; $i++) {
  $phase = $phases[$i]
  $x = ($i % $columns) * $tileW
  $y = [Math]::Floor($i / $columns) * $tileH
  $imagePath = Join-Path $root "pet\phases\$phase\claude-idle.png"
  $image = [System.Drawing.Image]::FromFile($imagePath)
  $g.DrawImage($image, ($x + 15), ($y + 4), 180, 180)
  $image.Dispose()
  $label = (Get-Culture).TextInfo.ToTitleCase(($phase -replace '-', ' '))
  $rect = New-Object System.Drawing.RectangleF($x, ($y + 184), $tileW, 28)
  $g.DrawString($label, $font, $text, $rect, $format)
}

$canvas.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
$format.Dispose(); $text.Dispose(); $font.Dispose(); $g.Dispose(); $canvas.Dispose()
$Output
