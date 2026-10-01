param(
    [ValidateSet('run-win', 'check', 'build-win', 'build-android')]
    [string]$Task = 'run-win'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskLocalFlutter = Join-Path $taskRoot '.tools/flutter/bin/flutter.bat'
$taskFlutter = if (Test-Path -LiteralPath $taskLocalFlutter) { $taskLocalFlutter } else {
    (Get-Command flutter -ErrorAction Stop).Source
}
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$taskJbr = 'C:/Program Files/Android/Android Studio/jbr'
if (Test-Path -LiteralPath "$taskJbr/bin/java.exe") { $env:JAVA_HOME = $taskJbr }
$taskNetwork = Get-ItemProperty -LiteralPath 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Internet Settings' -ErrorAction SilentlyContinue
if ($taskNetwork.ProxyEnable -eq 1 -and $taskNetwork.ProxyServer -match '^(?<host>[A-Za-z0-9.-]+):(?<port>[0-9]+)$') {
    # Java does not inherit the Windows proxy automatically. Reuse it for this process only.
    $taskProxyHost = $Matches.host
    $taskProxyPort = $Matches.port
    $env:GRADLE_OPTS = "$env:GRADLE_OPTS -Dhttps.proxyHost=$taskProxyHost -Dhttps.proxyPort=$taskProxyPort -Dhttp.proxyHost=$taskProxyHost -Dhttp.proxyPort=$taskProxyPort"
}
Push-Location (Join-Path $taskRoot 'app')
try {
    $taskPubOutput = & $taskFlutter pub get 2>&1
    $taskPubStatus = $LASTEXITCODE
    $taskPubOutput | ForEach-Object { Write-Host $_ }
    $taskSymlinkError = ($taskPubOutput | Out-String).Contains('Building with plugins requires symlink support')
    if ($taskPubStatus -ne 0 -and !$taskSymlinkError) { throw 'Flutter dependencies could not be restored.' }
    if ($taskSymlinkError) {
        # Workspace-only junctions, without Administrator or system setting changes.
        $taskPlugins = Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
        foreach ($taskPlugin in $taskPlugins.plugins.windows) {
            $taskLink = Join-Path 'windows/flutter/ephemeral/.plugin_symlinks' $taskPlugin.name
            if (!(Test-Path -LiteralPath $taskLink)) {
                New-Item -ItemType Junction -Path $taskLink -Value $taskPlugin.path | Out-Null
            }
        }
    }
    switch ($Task) {
        'run-win' { & $taskFlutter run -d windows --no-pub }
        'build-win' { & $taskFlutter build windows --release --no-pub }
        'build-android' { & $taskFlutter build apk --debug --no-pub }
        'check' {
            & $taskFlutter analyze --no-pub
            if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
            & $taskFlutter test --no-pub
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "Flutter task failed: $Task" }
} finally { Pop-Location }
