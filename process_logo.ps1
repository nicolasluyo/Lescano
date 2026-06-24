Add-Type -AssemblyName System.Drawing

$src = "c:\Users\nicol\OneDrive\Escritorio\Lescano\brand_assets\logo.jpg"
$outDir = "c:\Users\nicol\OneDrive\Escritorio\Lescano\brand_assets"

# Load and normalize to 32bpp ARGB
$orig = [System.Drawing.Image]::FromFile($src)
$w = $orig.Width; $h = $orig.Height
$bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($orig, 0, 0, $w, $h)
$g.Dispose()
$orig.Dispose()

$rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$bmp.UnlockBits($data)

# Per-row dark pixel counts (to separate icon from wordmark)
$rowDark = New-Object int[] $h
$minX = $w; $maxX = 0
for ($y = 0; $y -lt $h; $y++) {
  $rowOff = $y * $stride
  $cnt = 0
  for ($x = 0; $x -lt $w; $x++) {
    $i = $rowOff + $x * 4
    $b = $bytes[$i]; $gg = $bytes[$i+1]; $r = $bytes[$i+2]
    $L = (0.299 * $r + 0.587 * $gg + 0.114 * $b)
    if ($L -lt 190) { $cnt++ }
  }
  $rowDark[$y] = $cnt
}

# Find icon region: first run of dark rows from top, ending at a gap of >=18 empty rows
$iconTop = -1; $iconBottom = -1; $gap = 0
for ($y = 0; $y -lt $h; $y++) {
  if ($rowDark[$y] -gt 2) {
    if ($iconTop -lt 0) { $iconTop = $y }
    $iconBottom = $y
    $gap = 0
  } else {
    if ($iconTop -ge 0) {
      $gap++
      if ($gap -ge 18) { break }
    }
  }
}

# Column bounds within icon rows
$minX = $w; $maxX = 0
for ($y = $iconTop; $y -le $iconBottom; $y++) {
  $rowOff = $y * $stride
  for ($x = 0; $x -lt $w; $x++) {
    $i = $rowOff + $x * 4
    $b = $bytes[$i]; $gg = $bytes[$i+1]; $r = $bytes[$i+2]
    $L = (0.299 * $r + 0.587 * $gg + 0.114 * $b)
    if ($L -lt 190) { if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x } }
  }
}

Write-Output "Icon bbox: top=$iconTop bottom=$iconBottom left=$minX right=$maxX"

$pad = 12
$ix = [Math]::Max(0, $minX - $pad)
$iy = [Math]::Max(0, $iconTop - $pad)
$iw = [Math]::Min($w - $ix, ($maxX - $minX) + 2*$pad)
$ih = [Math]::Min($h - $iy, ($iconBottom - $iconTop) + 2*$pad)

# Build white-transparent and color-transparent full-size buffers
$whiteBytes = New-Object byte[] ($stride * $h)
$colorBytes = New-Object byte[] ($stride * $h)
for ($p = 0; $p -lt $bytes.Length; $p += 4) {
  $b = $bytes[$p]; $gg = $bytes[$p+1]; $r = $bytes[$p+2]
  $L = (0.299 * $r + 0.587 * $gg + 0.114 * $b)
  $a = [int](255 * (248 - $L) / 108)
  if ($a -lt 0) { $a = 0 } elseif ($a -gt 255) { $a = 255 }
  # white version
  $whiteBytes[$p] = 255; $whiteBytes[$p+1] = 255; $whiteBytes[$p+2] = 255; $whiteBytes[$p+3] = $a
  # color version (keep original color, premultiply not needed for PNG straight alpha)
  $colorBytes[$p] = $b; $colorBytes[$p+1] = $gg; $colorBytes[$p+2] = $r; $colorBytes[$p+3] = $a
}

function Save-Cropped($buffer, $cropX, $cropY, $cropW, $cropH, $path) {
  $full = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $fr = New-Object System.Drawing.Rectangle 0, 0, $w, $h
  $fd = $full.LockBits($fr, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  [System.Runtime.InteropServices.Marshal]::Copy($buffer, 0, $fd.Scan0, $buffer.Length)
  $full.UnlockBits($fd)
  if ($cropW -gt 0 -and $cropH -gt 0) {
    $crop = New-Object System.Drawing.Bitmap $cropW, $cropH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $cg = [System.Drawing.Graphics]::FromImage($crop)
    $srcR = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropW, $cropH
    $dstR = New-Object System.Drawing.Rectangle 0, 0, $cropW, $cropH
    $cg.DrawImage($full, $dstR, $srcR, [System.Drawing.GraphicsUnit]::Pixel)
    $cg.Dispose()
    $crop.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose()
  } else {
    $full.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  $full.Dispose()
}

# Icon only, white
Save-Cropped $whiteBytes $ix $iy $iw $ih (Join-Path $outDir "logo-icon-white.png")
# Icon only, original color
Save-Cropped $colorBytes $ix $iy $iw $ih (Join-Path $outDir "logo-icon-color.png")
# Full mark white (whole canvas, transparent)
Save-Cropped $whiteBytes 0 0 0 0 (Join-Path $outDir "logo-white-full.png")

$bmp.Dispose()
Write-Output "Done. Saved logo-icon-white.png ($iw x $ih), logo-icon-color.png, logo-white-full.png"
