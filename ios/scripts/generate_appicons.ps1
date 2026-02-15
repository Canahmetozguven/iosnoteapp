$src = "ios/Resources/AppIcon-1024.png"
$dstDir = "ios/Resources/Assets.xcassets/AppIcon.appiconset"

Add-Type -AssemblyName System.Drawing

if (!(Test-Path $src)) {
  throw "Missing $src"
}

New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

function Resize-Png([string]$inPath, [string]$outPath, [int]$w, [int]$h) {
  $img = [System.Drawing.Image]::FromFile($inPath)
  try {
    # App icons must not contain transparency. Use 24bpp RGB and paint an opaque background.
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $g.Clear([System.Drawing.Color]::White)
      $g.DrawImage($img, 0, 0, $w, $h)
    }
    finally {
      $g.Dispose()
    }

    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
  finally {
    $img.Dispose()
  }
}

$icons = @(
  # iPad notifications/settings/spotlight sizes
  @{ name="Icon-ipad-20@1x.png"; w=20; h=20 },
  @{ name="Icon-ipad-20@2x.png"; w=40; h=40 },
  @{ name="Icon-ipad-29@1x.png"; w=29; h=29 },
  @{ name="Icon-ipad-29@2x.png"; w=58; h=58 },
  @{ name="Icon-ipad-40@1x.png"; w=40; h=40 },
  @{ name="Icon-ipad-40@2x.png"; w=80; h=80 },
  @{ name="Icon-ipad-76@1x.png"; w=76; h=76 },
  @{ name="Icon-20@2x.png"; w=40; h=40 },
  @{ name="Icon-20@3x.png"; w=60; h=60 },
  @{ name="Icon-29@2x.png"; w=58; h=58 },
  @{ name="Icon-29@3x.png"; w=87; h=87 },
  @{ name="Icon-40@2x.png"; w=80; h=80 },
  @{ name="Icon-40@3x.png"; w=120; h=120 },
  @{ name="Icon-60@2x.png"; w=120; h=120 },
  @{ name="Icon-60@3x.png"; w=180; h=180 },
  @{ name="Icon-76@2x.png"; w=152; h=152 },
  @{ name="Icon-83.5@2x.png"; w=167; h=167 },
  @{ name="Icon-1024.png"; w=1024; h=1024 }
)

foreach ($ic in $icons) {
  $outPath = Join-Path $dstDir $ic.name
  Resize-Png $src $outPath $ic.w $ic.h
}

$contentsJson = @"
{
  "images": [
    { "idiom": "iphone", "size": "20x20", "scale": "2x", "filename": "Icon-20@2x.png" },
    { "idiom": "iphone", "size": "20x20", "scale": "3x", "filename": "Icon-20@3x.png" },

    { "idiom": "iphone", "size": "29x29", "scale": "2x", "filename": "Icon-29@2x.png" },
    { "idiom": "iphone", "size": "29x29", "scale": "3x", "filename": "Icon-29@3x.png" },

    { "idiom": "iphone", "size": "40x40", "scale": "2x", "filename": "Icon-40@2x.png" },
    { "idiom": "iphone", "size": "40x40", "scale": "3x", "filename": "Icon-40@3x.png" },

    { "idiom": "iphone", "size": "60x60", "scale": "2x", "filename": "Icon-60@2x.png" },
    { "idiom": "iphone", "size": "60x60", "scale": "3x", "filename": "Icon-60@3x.png" },

    { "idiom": "ipad", "size": "20x20", "scale": "1x", "filename": "Icon-ipad-20@1x.png" },
    { "idiom": "ipad", "size": "20x20", "scale": "2x", "filename": "Icon-ipad-20@2x.png" },
    { "idiom": "ipad", "size": "29x29", "scale": "1x", "filename": "Icon-ipad-29@1x.png" },
    { "idiom": "ipad", "size": "29x29", "scale": "2x", "filename": "Icon-ipad-29@2x.png" },
    { "idiom": "ipad", "size": "40x40", "scale": "1x", "filename": "Icon-ipad-40@1x.png" },
    { "idiom": "ipad", "size": "40x40", "scale": "2x", "filename": "Icon-ipad-40@2x.png" },
    { "idiom": "ipad", "size": "76x76", "scale": "1x", "filename": "Icon-ipad-76@1x.png" },
    { "idiom": "ipad", "size": "76x76", "scale": "2x", "filename": "Icon-76@2x.png" },
    { "idiom": "ipad", "size": "83.5x83.5", "scale": "2x", "filename": "Icon-83.5@2x.png" },

    { "idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "Icon-1024.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
"@

Set-Content -Encoding utf8 -NoNewline -Path (Join-Path $dstDir "Contents.json") -Value $contentsJson

Write-Output ("Generated {0} icon files in {1}" -f $icons.Count, $dstDir)
