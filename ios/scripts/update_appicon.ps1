param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePng,

  # If set, will run git add/commit/push at the end.
  [switch]$CommitAndPush,

  [string]$CommitMessage = "Update app icon"
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  $here = Get-Location
  $p = $here.Path
  while ($true) {
    if (Test-Path (Join-Path $p ".git")) { return $p }
    $parent = Split-Path -Parent $p
    if ($parent -eq $p) { throw "Could not find repo root (.git). Run from inside the repo." }
    $p = $parent
  }
}

function Ensure-1024SquarePng([string]$inPath, [string]$outPath) {
  Add-Type -AssemblyName System.Drawing

  if (!(Test-Path $inPath)) { throw "Source not found: $inPath" }

  $img = [System.Drawing.Image]::FromFile($inPath)
  try {
    # Center-crop to square then scale to 1024x1024
    $side = [Math]::Min($img.Width, $img.Height)
    $x = [int](($img.Width - $side) / 2)
    $y = [int](($img.Height - $side) / 2)

    $bmp = New-Object System.Drawing.Bitmap 1024, 1024
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $g.Clear([System.Drawing.Color]::Transparent)

      $srcRect = New-Object System.Drawing.Rectangle $x, $y, $side, $side
      $dstRect = New-Object System.Drawing.Rectangle 0, 0, 1024, 1024
      $g.DrawImage($img, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally {
      $g.Dispose()
    }

    $dir = Split-Path -Parent $outPath
    if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
  finally {
    $img.Dispose()
  }
}

$repo = Get-RepoRoot
Set-Location $repo

$dst1024 = "ios/Resources/AppIcon-1024.png"
$genScript = "ios/scripts/generate_appicons.ps1"

if (!(Test-Path $genScript)) {
  throw "Missing generator script: $genScript"
}

Write-Host "Source: $SourcePng"
Write-Host "Destination: $dst1024"

Ensure-1024SquarePng -inPath $SourcePng -outPath $dst1024

Write-Host "Generating AppIcon asset set..."
pwsh -NoProfile -File $genScript | Write-Host

Write-Host "Done. Updated:"
Write-Host "  $dst1024"
Write-Host "  ios/Resources/Assets.xcassets/AppIcon.appiconset/"

if ($CommitAndPush) {
  git add ios/Resources/AppIcon-1024.png ios/Resources/Assets.xcassets/AppIcon.appiconset | Out-Null
  git commit -m $CommitMessage
  git push
}

