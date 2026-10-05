$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPubspec = Get-Content -LiteralPath "$taskRoot/app/pubspec.yaml" -Raw
if ($taskPubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+') {
    throw 'Application version was not found in pubspec.yaml.'
}
$taskVersion = $Matches[1]
$taskRelease = Join-Path $taskRoot 'app/build/windows/x64/runner/Release'
$taskApk = Join-Path $taskRoot 'app/build/app/outputs/flutter-apk/app-release.apk'
if (!(Test-Path -LiteralPath "$taskRelease/weiming_xigu.exe") -or !(Test-Path -LiteralPath $taskApk)) {
    throw 'Build Windows and Android release packages first.'
}
$taskArtifacts = Join-Path $taskRoot 'artifacts'
$taskBundle = Join-Path $taskArtifacts "windows-v$taskVersion"
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
if (Test-Path -LiteralPath "$taskRoot/assets/branding") {
    New-Item -ItemType Directory -Path "$taskBundle/assets/branding" -Force | Out-Null
    Get-ChildItem -LiteralPath "$taskRoot/assets/branding" -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination "$taskBundle/assets/branding" -Force
    }
}
New-Item -ItemType Directory -Path "$taskBundle/docs" -Force | Out-Null
$taskSourceRef = (& git -C $taskRoot rev-parse --abbrev-ref HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Source reference could not be resolved.' }
if ($taskSourceRef -eq 'HEAD') { $taskSourceRef = (& git -C $taskRoot rev-parse HEAD).Trim() }
foreach ($taskDoc in (Get-ChildItem -LiteralPath "$taskRoot/docs" -Filter '*.md' -File)) {
    if ($taskDoc.Name -match 'acceptance|validation') {
        # The current acceptance record contains this ZIP's checksum. Link to
        # its source instead of embedding a self-referential checksum in it.
        $taskRecordUrl = "https://github.com/Xuega226/unname_xigu/blob/$taskSourceRef/docs/$($taskDoc.Name)"
        "# $($taskDoc.BaseName)`n`n完整验收记录见 [源代码文档]($taskRecordUrl)。" |
            Set-Content -LiteralPath "$taskBundle/docs/$($taskDoc.Name)" -Encoding utf8
    } else {
        Copy-Item -LiteralPath $taskDoc.FullName -Destination "$taskBundle/docs" -Force
    }
}
if (Test-Path -LiteralPath "$taskRoot/docs/broker-holdings-import.md") {
    New-Item -ItemType Directory -Path "$taskBundle/docs" -Force | Out-Null
    Copy-Item -LiteralPath "$taskRoot/docs/broker-holdings-import.md" -Destination "$taskBundle/docs" -Force
    New-Item -ItemType Directory -Path "$taskBundle/examples" -Force | Out-Null
    Get-ChildItem -LiteralPath "$taskRoot/examples" -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination "$taskBundle/examples" -Force
    }
}
@"
未名溪谷 v$taskVersion

Windows：完整解压后双击 weiming_xigu.exe，保留 DLL 与 data 目录。
原 Windows 数据目录继续使用 APPDATA/com.lianghua/lianghua_assistant，旧版会自动迁移并保留 v1/v2/v3/v4/v6/v7 原始备份。
Android：安装 weiming-xigu-android-v$taskVersion.apk，可覆盖相同测试签名的旧包；卸载前先导出备份。

从默认演示体验；真实研究请在菜单新建空白工作区，再添加真实自选。
研究卡先显示摘要，完整内容点「阅读完整研究」，AI 草稿、复查与版本在「更多研究操作」；操作说明见 docs/ui-simplification.md。
DeepSeek 密钥在「数据与设置 → DeepSeek 本地设置」录入。密钥不会放入研究备份，换设备需重新设置。
模型草稿需要原始资料片段、引用检查和人工确认；当前安装包没有预置密钥。
资料原文页直接「自动查找年报」可按沪深 A 股代码查询近三年年报。下载或本地导入后，本机建议关键页、期间和单位；主动 AI 准备最多一次请求，可预览调整后一次采用范围。
修订版请自行核对选择，已导入公告和相同 PDF 跳过；重新准备保存有父版本的选页资料，保留旧引用。财务页「AI 预核验」通常提取和复核两次请求，正常字段默认纳入，处理异常后一次确认保存；不自动采纳。
JSON 备份携带选页原文和公告出处，原 PDF 需单独复制并重新关联。北交所自动获取、季报批量获取与 OCR 尚未实现。
研究卡可查看多年度变化、保存复查计划、对照历史研究版本。
行情须手动刷新，只有全部持仓取得同一天的有效日线时才可确认更新账户估值。
账户风控可导入完整券商 CSV / 标准 JSON，逐页预览并核对账户、现金、日期和持仓后确认；已有资金流需核对归属。
Windows 标准 JSON 可绑定同一文件，每 15 秒前台读取外部工具更新；Android 手动导入。文件需由券商导出或外部工具生成，当前没有券商登录和账户直连。
人工修改持仓、现金、日期或应用行情后关闭自动读取，需要重新预览绑定。导入保留入金与出金，不从资产推算本金。
风险图表可查看资产、集中度、压力情景与本金盈亏；明细与滑块不改变持仓。
量化研究支持自选因子规则、筛选、评分、分项贡献与同因子对照。示例默认不启用，每次修改后需明确核对参数；缺失资料不按零分或重新分配权重。
历史行情支持手动获取或 JSON 预览导入，动量按未复权观测间隔计算。观察日前、不含观察日的数据才参与评分。
资金流水首次启用需确认覆盖起点，原累计入出金保留为期初，不补造旧流水。新增流水更新本金，不自动改现金；不生成净值、回撤或回测。
量化规则与数据说明见 docs/quant-rules.md 和 docs/quant-data.md；参数、股本证据、行情及流水、准备建议和核验审计随 schema8 备份传输。
导入历史可预览差异并恢复持仓，保留当前研究和资金；恢复成功后关闭自动读取。
CSV 支持 UTF-8、BOM UTF-16 与确认后的 GBK，以及三种分隔符和人工列映射。
导入说明见 docs/broker-holdings-import.md，examples 中样例全部为虚构数据。
JSON 导入会替换工作区，建议先导出当前资料。

Android 为测试签名包，Windows 尚未进行其他电脑的完整部署验证。
"@ | Set-Content -LiteralPath "$taskBundle/快速开始.txt" -Encoding utf8
$taskZip = Join-Path $taskArtifacts "weiming-xigu-windows-v$taskVersion.zip"
$taskAndroid = Join-Path $taskArtifacts "weiming-xigu-android-v$taskVersion.apk"
Compress-Archive -Path "$taskBundle/*" -DestinationPath $taskZip -Force
Copy-Item -LiteralPath $taskApk -Destination $taskAndroid -Force
@($taskZip,$taskAndroid) | ForEach-Object {
    $taskHash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
    "$($taskHash.Hash.ToLower())  $([System.IO.Path]::GetFileName($_))"
} | Set-Content -LiteralPath "$taskArtifacts/SHA256SUMS-v$taskVersion.txt" -Encoding ascii
Get-Item -LiteralPath $taskZip,$taskAndroid | Select-Object Name,Length
