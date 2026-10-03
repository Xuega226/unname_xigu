$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPubspec = Get-Content -LiteralPath "$taskRoot/app/pubspec.yaml" -Raw
if ($taskPubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+') { throw 'Missing app version.' }
$taskVersion = 'v' + (($Matches[1] -split '\.')[0..1] -join '.')
$taskRelease = Join-Path $taskRoot 'app/build/windows/x64/runner/Release'
$taskApk = Join-Path $taskRoot 'app/build/app/outputs/flutter-apk/app-release.apk'
if (!(Test-Path -LiteralPath "$taskRelease/weiming_xigu.exe") -or !(Test-Path -LiteralPath $taskApk)) {
    throw 'Build Windows and Android release packages first.'
}
$taskArtifacts = Join-Path $taskRoot 'artifacts'
$taskBundle = Join-Path $taskArtifacts "windows-$taskVersion"
New-Item -ItemType Directory -Path $taskBundle -Force | Out-Null
Get-ChildItem -LiteralPath $taskRelease | Where-Object { $_.Name -ne 'lianghua_assistant.exe' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $taskBundle -Recurse -Force
}
$taskRedist = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Redist/MSVC'
$taskRuntime = Get-ChildItem -LiteralPath $taskRedist -Directory | Where-Object {
    Test-Path -LiteralPath "$($_.FullName)/x64/Microsoft.VC143.CRT"
} | Sort-Object Name -Descending | Select-Object -First 1
if (!$taskRuntime) { throw 'Visual C++ redistributable DLLs were not found.' }
Get-ChildItem -LiteralPath "$($taskRuntime.FullName)/x64/Microsoft.VC143.CRT" -Filter '*.dll' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $taskBundle -Force
}
Copy-Item -LiteralPath "$taskRoot/README.md" -Destination "$taskBundle/README.md" -Force
@"
未名溪谷 $taskVersion

Windows：完整解压后双击 weiming_xigu.exe，保留 DLL 与 data 目录。
原 Windows 数据目录继续使用 APPDATA/com.lianghua/lianghua_assistant，旧版会自动迁移并保留 v1/v2 备份。
Android：安装 weiming-xigu-android-$taskVersion.apk，可覆盖相同测试签名的旧包；卸载前先导出备份。

从默认演示体验；真实研究请在菜单新建空白工作区，再添加真实自选。
DeepSeek 密钥在「数据与设置 → DeepSeek 本地设置」录入。密钥不会放入研究备份，换设备需重新设置。
模型草稿需要原始资料片段、引用检查和人工确认；当前安装包没有预置密钥。
资料与财务中可按沪深 A 股代码自动查询近三年年报，批量下载后逐份选页、核对单位并确认保存；失败项可重试。
修订版请自行核对选择，已导入公告和相同 PDF 跳过，旧资料不覆盖；也可手动导入文字 PDF、核验 AI 财务候选。
JSON 备份携带选页原文和公告出处，原 PDF 需单独复制并重新关联。北交所自动获取、季报批量获取与 OCR 尚未实现。
研究卡可查看多年度变化、保存复查计划、对照历史研究版本。
行情须手动刷新，只有全部持仓取得同一天的有效日线时才可确认更新账户估值。
JSON 导入会替换工作区，建议先导出当前资料。

Android 为测试签名包，Windows 尚未进行其他电脑的完整部署验证。
"@ | Set-Content -LiteralPath "$taskBundle/快速开始.txt" -Encoding utf8
$taskZip = Join-Path $taskArtifacts "weiming-xigu-windows-$taskVersion.zip"
$taskAndroid = Join-Path $taskArtifacts "weiming-xigu-android-$taskVersion.apk"
Compress-Archive -Path "$taskBundle/*" -DestinationPath $taskZip -Force
Copy-Item -LiteralPath $taskApk -Destination $taskAndroid -Force
@($taskZip,$taskAndroid) | ForEach-Object {
    $taskHash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
    "$($taskHash.Hash.ToLower())  $([System.IO.Path]::GetFileName($_))"
} | Set-Content -LiteralPath "$taskArtifacts/SHA256SUMS-$taskVersion.txt" -Encoding ascii
Get-Item -LiteralPath $taskZip,$taskAndroid | Select-Object Name,Length
