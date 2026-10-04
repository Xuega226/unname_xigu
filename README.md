# 未名溪谷 v0.3.1

Windows / Android 共用的 Flutter 研究与账户风控工具。默认保留虚构演示，真实研究从空白工作区开始。第三轮增加文字 PDF 导入、AI 财务候选核验、多年度变化、研究版本与复查计划，保留第二轮自选、日线更新和账户风控。

## 使用流程

1. 从右上角「数据与设置」导出需要保留的演示记录，再新建空白工作区。
2. 在「公司研究」添加真实公司，选择交易所并输入六位代码，核验名称与行业后加入自选。最多 10 家，会同时建立空白研究卡。
3. 手动更新自选日线。每家公司显示价格、交易日期、获取时间、来源与上次错误。采用东方财富未复权收盘价；北京时间 17:00 前排除当日可能尚未完成的日线。停牌、节假日或来源缺失可能导致旧交易日期，不表示当前可成交价格。
4. 在研究卡的「资料与财务」手动选择文字型 PDF，核对公司、报告期、披露日和单位，勾选需要的原文页后保存。原 PDF 按 SHA-256 存放在本机，页码和选页原文进入工作区，可查看原页及提取文字。也可粘贴公告片段并注明 HTTPS 出处。扫描件、加密文件暂不支持。
5. 点击「AI 提取财务候选值」，选择发给模型的原文、报告期间和合并/母公司口径。逐项核对指标名称、原始数值、当前年度列及引用后，选择候选并勾选人工核验才保存。空字段保留为资料不足；利润和现金流允许负数。可继续人工录入；原文更正时新增，保留旧引用。「同期间财务比较」要求起止日期、单位和口径相同；「多年度财务变化」按期间类型与口径分组，金额统一为万元。相邻年度、每期唯一、原披露且基数为正时才计算同比，金融行业需专用口径。
6. 在右上角「DeepSeek 本地设置」录入自己的密钥，检查连接并选择可用模型后保存。官方接口固定为 api.deepseek.com，模型 ID 可编辑，默认 deepseek-flash。密钥保存到 Windows DPAPI / Android Keystore 保护的安全存储，与研究备份分开。
7. 点击真实研究卡的「生成 AI 草稿」，手动发送所选公司的原文与来源元数据。模型调用由自己的 DeepSeek 账户计费，不发送账户持仓。应用检查来源 ID 及逐字摘录；检查通过仍需人工确认原文是否支持判断。勾选核验后接受，才写入研究卡，同时在日志保留旧版本与接受版本。未接受的草稿只保留在当前窗口。
8. 手动录入资金与持仓，保持所有价格对应同一估值日期。只有全部持仓均匹配唯一有效的自选行情、交易日相同且不早于现有估值日时，才能确认将日线价格应用到整个账户。部分更新或混合日期不会改变风险计算。
9. 在研究卡设置「复查计划与清单」，记录待验证条件、证据、人工状态和下次复查日期；到期在应用内提示。每次编辑研究或接受 AI 草稿保留旧快照，通过「研究版本对照」查看字段变化。
10. 用 JSON 导出备份，在另一端粘贴导入。导入替换整个工作区，不自动合并；密钥需在另一设备重新配置。备份携带选页原文、财务证据、复查计划与研究历史，**不嵌入 PDF 原件**。原文件需单独传输，再用「重新关联原 PDF」核对 SHA-256；未关联时仍可阅读已保存文字。

关联自选或原始资料后的研究卡保留公司代码与名称，仍可编辑研究内容；研究另一家公司时请新建研究卡，避免将原公司的证据用于新公司。

约一年持有期可以延长。20% 是相对净投入本金的亏损偏好提醒，不能保证亏损上限。账户高点回撤仍缺少现金流调整后的历史序列。当前只计算现金与股票资产，不支持融资负债。

## 开发

在项目根目录的 PowerShell 中运行：

```powershell
./tools/flutter.ps1 -Task run-win
./tools/flutter.ps1 -Task check
./tools/flutter.ps1 -Task build-win
./tools/flutter.ps1 -Task build-android
./tools/package.ps1
```

脚本优先使用项目 .tools/flutter，也支持 PATH 中的 Flutter。构建需要 Visual Studio C++、Android SDK 与兼容 JDK。Windows 无符号链接权限时使用项目内 junction；不修改系统开发者模式。Java 构建与 Dart Windows 行情客户端支持复用系统配置的简单 HTTP 代理，暂不处理 PAC、代理认证或复杂分协议配置。

本机 SDK 来自 Flutter 官方 stable 源码压缩包，保留 engine.version，并建立本地 Git 快照启动工具。迁移环境建议使用官方完整 stable SDK，保留 pubspec.lock。本机报告 Flutter 3.47.4-0.0.pre-1 / Dart 3.13.4。

原生服务测试：

```powershell
cd app
../.tools/flutter/bin/flutter.bat test integration_test/native_services_test.dart -d windows
../.tools/flutter/bin/flutter.bat test integration_test/native_services_test.dart -d emulator-5554 --no-enable-impeller
../.tools/flutter/bin/flutter.bat test integration_test/native_pdf_test.dart -d windows
../.tools/flutter/bin/flutter.bat test integration_test/native_pdf_test.dart -d emulator-5554 --no-enable-impeller
../.tools/flutter/bin/dart.bat run tool/live_market_probe.dart
../.tools/flutter/bin/flutter.bat test tool/preview_test.dart --no-pub
```

最后两条是手动联网验证与中文 UI 预览工具，预览需 Windows 字体。普通功能测试不调用外部模型、不使用真实密钥。

`v02_acceptance_test.dart` 在临时数据目录使用模拟服务跑完整录入、草稿核验、风险、复查及备份导入流程，不读取真实密钥。可用 `--dart-define=V02_EXPORT_FIXTURE=绝对路径` 导出验收备份，并在另一端通过 `--dart-define=V02_IMPORT_FIXTURE=该端可读的绝对路径` 核对实际跨端恢复。Android 原生测试请指定独立测试模拟器，避免替换日常应用。

`v03_acceptance_test.dart` 增加真实磁盘 PDF、逐项财务确认、历史与复查计划、缺原件文字恢复及 SHA-256 重新关联验收。原生入口调用生产 PDF 解析和渲染，选择文件使用固定虚构样本；普通 widget 入口使用解析/渲染替身。两者均使用模拟模型与内存测试密钥。

```powershell
cd app
../.tools/flutter/bin/flutter.bat test integration_test/v03_acceptance_test.dart -d windows --dart-define=V03_EXPORT_FIXTURE=C:/temp/v03-backup.json
# 将上述 JSON 单独传入测试模拟器后运行；不含 PDF 原件。
../.tools/flutter/bin/flutter.bat test integration_test/v03_acceptance_test.dart -d emulator-5574 --no-enable-impeller --dart-define=V03_IMPORT_FIXTURE=/data/local/tmp/v03-backup.json
```

已在应用保存密钥后，可显式运行真实 DeepSeek 测试（会产生账户费用）：

```powershell
cd app
../.tools/flutter/bin/flutter.bat test integration_test/live_deepseek_test.dart -d windows
```

该测试仅发送虚构资料，验证鉴权、五节 JSON 草稿及引用检查，将无密钥报告写入 artifacts/deepseek-live-test.json，不改研究卡。Windows 应用与测试须使用同一用户及相同运行环境；Codex 的 MSIX 容器可能将 AppData 重定向，造成测试与外部启动的应用读取不同配置。

## 升级、数据与恢复

Android applicationId 保留 com.lianghua.lianghua_assistant，可覆盖安装测试签名相同的旧包。Windows 新 exe 为 weiming_xigu.exe，产品显示名更改后仍使用用户 APPDATA 下 com.lianghua/lianghua_assistant 目录。Android 继续使用应用支持目录。

workspace.json 备份格式为 schemaVersion 3，兼容导入 v1/v2。首次读取旧主文件或仅剩的旧备份时，先保留原始字节至 workspace.json.v1.bak 或 .v2.bak，再保存新格式；已有原版本归档不会覆盖。每次保存保留 workspace.json.bak。主文件损坏时报告错误并保留，不用演示覆盖。主文件缺失时可读取备份。备份文本限制 800 万字符。单份 PDF 最多 25 MB、1000 页，选存最多 25 页/24 万字符，每次发给模型最多 6 万字符。

研究与持仓备份是明文，需自行妥善保存。Android 自动系统备份关闭，以免密钥密文在缺少 Keystore 的设备上恢复。卸载或清除应用数据前请手动导出研究资料。

## 文件与边界

核心模型与账户计算在 app/lib/domain.dart 和 research.dart；网络适配在 services.dart；密钥在 credentials.dart；本机数据在 storage.dart。Android 网络直接访问 HTTPS，不依赖 Windows 电脑开机。

Windows 便携包必须完整解压，保留 exe、DLL 与 data 一起使用。Android Release APK 仍使用测试签名，供本地体验，不作为商店发行包。行情公共接口可变，当前仅验证小范围自选；没有稳定性服务承诺。

当前没有自动财报抓取、OCR、全市场排名、系统后台通知、云端同步或自动交易。按代码查找下载财报计划第四轮。AI 仅整理选定资料；引用及数字存在于原文，并不证明指标含义、公司归属或本期列正确，仍须人工核对。其他设备需配置自己的密钥。

本轮计划见 [v0.3 计划](docs/v0.3-plan.md)，历史验证见 [v0.3 验证记录](docs/v0.3-validation.md)，本次结果见 [v0.3.1 验收记录](docs/v0.3-acceptance.md)。第二轮结果保留在 [v0.2.1 验收记录](docs/v0.2-acceptance.md)。
