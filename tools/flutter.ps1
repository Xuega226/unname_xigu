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
    $taskCmakeCache = Join-Path $taskRoot 'app/build/windows/x64/CMakeCache.txt'
    if ($Task -in @('run-win','build-win') -and (Test-Path -LiteralPath $taskCmakeCache)) {
        # A previous v0.1 build caches the old executable target. Drop only
        # this generated cache file when upgrading, never application data.
        $taskCachedConfig = Get-Content -LiteralPath $taskCmakeCache -Raw
        if ($taskCachedConfig.Contains('TARGET_FILE_DIR:lianghua_assistant>')) {
            Remove-Item -LiteralPath $taskCmakeCache
        }
    }
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
        # The first pub get stopped before regenerating native registrants.
        # A second pass with unchanged metadata preserves the junctions and
        # completes Android / Windows registration for newly added plugins.
        & $taskFlutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Native plugin registration could not be regenerated.' }
    }
    switch ($Task) {
        # Builds must regenerate the native registrant for their own mode;
        # --no-pub would retain debug-only integration_test in a release APK.
        'run-win' { & $taskFlutter run -d windows }
        'build-win' { & $taskFlutter build windows --release }
        'build-android' { & $taskFlutter build apk --release }
        'check' {
            & $taskFlutter analyze --no-pub
            if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
            & $taskFlutter test --no-pub
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "Flutter task failed: $Task" }
} finally { Pop-Location }
