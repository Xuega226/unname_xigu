# Regenerate launcher resources from the checked-in v2 artwork, preserving
# its entire frame. Run flutter pub get in app first when dependencies are absent.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskDart = Join-Path $taskRoot '.tools/flutter/bin/dart.bat'
if (-not (Test-Path -LiteralPath $taskDart)) {
    throw 'Flutter SDK not found at .tools/flutter. Configure it before generating icons.'
}
Push-Location (Join-Path $taskRoot 'app')
try {
    & $taskDart run tool/generate_brand_icons.dart
    if ($LASTEXITCODE -ne 0) { throw 'Brand icon generation failed.' }
} finally {
    Pop-Location
}
