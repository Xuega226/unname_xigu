# Render the code-native valley/stream mark used by brand.svg and Android.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskBitmap = [System.Drawing.Bitmap]::new(256, 256)
$taskGraphics = [System.Drawing.Graphics]::FromImage($taskBitmap)
try {
    $taskGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $taskGraphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#152D35'))
    $taskGraphics.ScaleTransform(256 / 48, 256 / 48)
    $taskBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#66C9B9'))
    $taskPoints = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new(6,31),[System.Drawing.PointF]::new(17,13),[System.Drawing.PointF]::new(28,31),[System.Drawing.PointF]::new(36,14),[System.Drawing.PointF]::new(44,31))
    $taskGraphics.FillPolygon($taskBrush, $taskPoints)
    $taskPen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 2.5)
    $taskPen.StartCap = $taskPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $taskGraphics.DrawBezier($taskPen,18,33,32,33,32,38,24,39)
    $taskGraphics.DrawBezier($taskPen,24,39,17,40,18,43,29,44)
    $taskMemory = [System.IO.MemoryStream]::new()
    $taskBitmap.Save($taskMemory, [System.Drawing.Imaging.ImageFormat]::Png)
    $taskBytes = $taskMemory.ToArray()
    $taskFile = [System.IO.File]::Create((Join-Path $taskRoot 'app/windows/runner/resources/app_icon.ico'))
    $taskWriter = [System.IO.BinaryWriter]::new($taskFile)
    try {
        $taskWriter.Write([uint16]0); $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]1)
        $taskWriter.Write([byte]0); $taskWriter.Write([byte]0); $taskWriter.Write([byte]0); $taskWriter.Write([byte]0)
        $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]32)
        $taskWriter.Write([uint32]$taskBytes.Length); $taskWriter.Write([uint32]22); $taskWriter.Write($taskBytes)
    } finally { $taskWriter.Dispose(); $taskFile.Dispose() }
    $taskMemory.Dispose(); $taskBrush.Dispose(); $taskPen.Dispose()
} finally { $taskGraphics.Dispose(); $taskBitmap.Dispose() }
