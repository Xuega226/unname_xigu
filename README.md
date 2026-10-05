# 未名溪谷 v0.7.3

Windows / Android 共用的 Flutter 研究与账户风控工具。默认保留虚构演示，真实研究从空白工作区开始。第七轮增加可配置因子规则、筛选与评分、贡献及公司对照图、历史行情与带日期资金流水；保留年报获取、财务核验、研究复查、风险图表和单账户持仓历史。

v0.7.3 增加财报选页、期间与单位建议、AI 二次复核和一次报告级确认；旧版逐项确认与新报告级确认分开记录，备份升级为 schema8。研究摘要和参数按需展开，双端继续使用项目未名子股票分析图标。常用入口见 [页面操作说明](docs/ui-simplification.md)。

## 使用流程

1. 从右上角「数据与设置」导出需要保留的演示记录，再新建空白工作区。
2. 在「公司研究」添加真实公司，选择交易所并输入六位代码，核验名称与行业后加入自选。最多 10 家，会同时建立空白研究卡。
3. 手动更新自选日线。每家公司显示价格、交易日期、获取时间、来源与上次错误。采用东方财富未复权收盘价；北京时间 17:00 前排除当日可能尚未完成的日线。停牌、节假日或来源缺失可能导致旧交易日期，不表示当前可成交价格。
4. 在真实研究卡的「资料与财务 → 自动查找年报」查询最近三个已结束年度的巨潮年报正文。核对来源公司、报告期、披露日与修订标志，勾选公告后批量下载；每份下载后预览建议页、期间与单位，一次采用范围保存原文。修订版单独选择，旧版本不覆盖；普通导入的重复公告或相同 PDF 自动跳过，失败项可以重试，取消保留已经确认保存的项目。沪深 A 股可自动获取，北交所及其他市场先手动导入。也可手动选择文字 PDF 或粘贴 HTTPS 公告片段。原 PDF 按 SHA-256 保存在本机；选页原文、公告身份、出处及获取时间进入备份，原文件需要另行传输。扫描件、加密文件暂不支持。
5. 下载或导入文字 PDF 后，本机建议关键页、期间和单位；可预览调整，主动「AI 选页与预填」最多一次请求。采用范围保存原文后，在「财务核验」点击「AI 预核验」，选择一份报告并确认发送范围、期间和口径，提取与复核最多两次请求。正常唯一候选默认纳入，异常和缺失单列；查看摘要后一次「确认并保存可采纳字段」，不再逐项勾选正常字段。语义例外需记录人工依据，程序硬错误不能绕过。空字段保留资料不足，利润和现金流允许负数；混合单位和版本不强拼。可继续人工录入；原文更正或重新准备时新增版本，保留旧引用。「多年度财务变化」统一显示万元，相邻年度、每期唯一、原披露且基数为正时才计算同比，金融行业需专用口径。
6. 在右上角「DeepSeek 本地设置」录入自己的密钥，检查连接并选择可用模型后保存。官方接口固定为 api.deepseek.com，模型 ID 可编辑，默认 deepseek-flash。密钥保存到 Windows DPAPI / Android Keystore 保护的安全存储，与研究备份分开。
7. 点击真实研究卡的「生成 AI 草稿」，手动发送所选公司的原文与来源元数据。模型调用由自己的 DeepSeek 账户计费，不发送账户持仓。应用检查来源 ID 及逐字摘录；检查通过仍需人工确认原文是否支持判断。勾选核验后接受，才写入研究卡，同时在日志保留旧版本与接受版本。未接受的草稿只保留在当前窗口。
8. 在「账户风控 → 导入券商持仓」选择完整 CSV / 标准 JSON，逐页核对新旧数量、市价、现金和将移除的旧持仓后确认。首次已有资金记录或来源改变时，额外确认入金、出金仍属同一账户；其他账户请先备份并新建空白工作区。导入保留资金流，不从资产推算本金。Windows 标准 JSON 可绑定同一文件，每15秒前台读取更新；文件需由券商导出或外部工具生成，应用尚无账户登录或直连。安卓支持手动导入。也可手动维护资金与持仓；所有价格使用同一估值日期，只有取得全部有效同日自选行情时才能确认更新估值。人工改动现金、持仓或估值日期后自动读取关闭。
9. 在研究卡设置「复查计划与清单」，记录待验证条件、证据、人工状态和下次复查日期；到期在应用内提示。每次编辑研究或接受 AI 草稿保留旧快照，通过「研究版本对照」查看字段变化。
10. 在「量化研究」新建规则，设置观察日、指标、阈值、权重、筛选及人工复查约定。示例默认不启用，每次修改后须重新勾选核对确认；仅对当前最多10家自选计算。缺失或不适用的数据不会按零分处理，也不重新分配权重。总股本需单独核验，持仓数量不能代替公司股份。结果可返回对应公司研究。详细方法见 [规则说明](docs/quant-rules.md)。
11. 在量化页获取或预览导入未复权历史日线，最多10份、每份500根。启用带日期资金流水前确认覆盖起点，旧累计金额保留为期初，不补造过去的流水。新增实际入出金只更新累计本金，现金余额仍需核对账户快照。见 [数据说明](docs/quant-data.md)。
12. 用 JSON 导出备份，在另一端粘贴导入。导入替换整个工作区，不自动合并；成功恢复后关闭文件自动读取，需重新预览绑定。密钥需在另一设备重新配置。schema8 备份携带参数版本、股本证据、历史行情、资金流水、导入历史、持仓来源、选页原文、准备建议、财务与复核证据、确认方式、复查计划与研究历史，**不嵌入 PDF 原件、密钥或本机绑定路径**。原文件需单独传输，再用「重新关联原 PDF」核对 SHA-256；未关联时仍可阅读已保存文字，但重新准备仅覆盖已有片段。

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

`v04_acceptance_test.dart` 在真实磁盘工作区增加公告查询、下载失败与取消重试、选页核验、公告出处和去重，再核验两年财务、同比、复查计划及跨端备份。原生入口使用生产 PDF 引擎；目录响应与模型响应采用明确虚构夹具。`V04_EXPORT_FIXTURE` 与 `V04_IMPORT_FIXTURE` 分别指定 Windows 导出路径和另一端可读的同份文件路径。

`v05_acceptance_test.dart` 使用独立磁盘快照、工作区和绑定设置，走通 CSV / JSON 人工确认、Windows 周期读取、错误保留、停止、备份重开及跨端恢复，断言资金、财务负值、公告出处和研究历史保持。文件选择注入虚构样例，不代表系统选择器或券商账户直连联调。

```powershell
cd app
../.tools/flutter/bin/flutter.bat test integration_test/v03_acceptance_test.dart -d windows --dart-define=V03_EXPORT_FIXTURE=C:/temp/v03-backup.json
# 将上述 JSON 单独传入测试模拟器后运行；不含 PDF 原件。
../.tools/flutter/bin/flutter.bat test integration_test/v03_acceptance_test.dart -d emulator-5574 --no-enable-impeller --dart-define=V03_IMPORT_FIXTURE=/data/local/tmp/v03-backup.json
../.tools/flutter/bin/flutter.bat test integration_test/v04_acceptance_test.dart -d windows --dart-define=V04_EXPORT_FIXTURE=C:/temp/v04-backup.json
../.tools/flutter/bin/flutter.bat test integration_test/v04_acceptance_test.dart -d emulator-5574 --no-enable-impeller --dart-define=V04_IMPORT_FIXTURE=/data/local/tmp/v04-backup.json
../.tools/flutter/bin/flutter.bat test integration_test/v05_acceptance_test.dart -d windows --dart-define=V05_EXPORT_FIXTURE=C:/temp/v05-backup.json
../.tools/flutter/bin/flutter.bat test integration_test/v05_acceptance_test.dart -d emulator-5574 --no-enable-impeller --dart-define=V05_IMPORT_FIXTURE=/data/local/tmp/v05-backup.json
```

已在应用保存密钥后，可显式运行真实 DeepSeek 测试（会产生账户费用）：

```powershell
cd app
../.tools/flutter/bin/flutter.bat test integration_test/live_deepseek_test.dart -d windows
```

该测试仅发送虚构资料，验证鉴权、五节 JSON 草稿及引用检查，将无密钥报告写入 artifacts/deepseek-live-test.json，不改研究卡。Windows 应用与测试须使用同一用户及相同运行环境；Codex 的 MSIX 容器可能将 AppData 重定向，造成测试与外部启动的应用读取不同配置。

## 升级、数据与恢复

Android applicationId 保留 com.lianghua.lianghua_assistant，可覆盖安装测试签名相同的旧包。Windows 新 exe 为 weiming_xigu.exe，产品显示名更改后仍使用用户 APPDATA 下 com.lianghua/lianghua_assistant 目录。Android 继续使用应用支持目录。

workspace.json 备份格式为 schemaVersion 8，兼容导入 v1/v2/v3/v4/v6/v7；不兼容另一实验分支的多账户 schema5。首次读取旧主文件或仅剩的旧备份时，先保留原始字节至 workspace.json.v1.bak、.v2.bak、.v3.bak、.v4.bak、.v6.bak 或 .v7.bak，再保存新格式；已有原版本归档不会覆盖。旧财务记录不追认为 AI 复核通过。每次保存保留 workspace.json.bak。主文件损坏时报告错误并保留，不用演示覆盖。主文件缺失时可读取备份。备份文本限制 800 万字符。单份 PDF 最多 25 MB、1000 页，选存最多 25 页/24 万字符，每次发给模型最多 6 万字符。

研究与持仓备份是明文，需自行妥善保存。Android 自动系统备份关闭，以免密钥密文在缺少 Keystore 的设备上恢复。卸载或清除应用数据前请手动导出研究资料。

## 文件与边界

核心模型与账户计算在 app/lib/domain.dart 和 research.dart；行情/模型网络适配在 services.dart，财报查询下载在 report_fetch.dart；密钥在 credentials.dart；本机数据在 storage.dart。Android 网络直接访问 HTTPS，不依赖 Windows 电脑开机。

Windows 便携包必须完整解压，保留 exe、DLL 与 data 一起使用。Android Release APK 仍使用测试签名，供本地体验，不作为商店发行包。行情公共接口可变，当前仅验证小范围自选；没有稳定性服务承诺。

自动获取使用巨潮公开网站的 HTTPS 接口，可能遇到访问限制、缺失公告或接口变化；界面显示错误与不完整结果，可以重试或手动导入。当前自动范围是沪深 A 股近三年年报正文，季报批量获取、OCR、全市场排名、系统后台通知、云端同步或自动交易留待后续。AI 仅整理选定资料；引用及数字存在于原文，并不证明指标含义、公司归属或本期列正确，仍须人工核对。修订公告的数字披露版本默认“未注明”，请核对重述口径后比较；其他设备需配置自己的密钥。

本轮执行依据见 [v0.7.3 规划](docs/v0.7.3-plan.md)，结果见 [v0.7.3 验收](docs/v0.7.3-acceptance.md)。页面简化记录见 [v0.7.2 验收](docs/v0.7.2-acceptance.md)，量化功能验收见 [v0.7.1 验收](docs/v0.7-acceptance.md)。文件格式见 [持仓导入说明](docs/broker-holdings-import.md)。历史记录保留在 [v0.6.1 验收](docs/v0.6-acceptance.md)、[v0.5.1 验收](docs/v0.5-acceptance.md)、[v0.4.3 验收](docs/v0.4-acceptance.md)、[v0.3.1 验收](docs/v0.3-acceptance.md)及 [v0.2.1 验收](docs/v0.2-acceptance.md)。

v0.7 按用户要求继续采用单账户，因子/规则选股与评分已接入；回测安排在 v0.8，见 [量化与风险路线图](docs/quant-risk-roadmap.md)。

根据减少人工核验负担的新要求，[首期需求](docs/ai-verification-requirements.md)按 [v0.7.3 版本规划](docs/v0.7.3-plan.md)开发；验证范围与交付状态见 [验收记录](docs/v0.7.3-acceptance.md)。v0.7.4 仍规划跨报告异常队列与多年度批次，v0.8 保留回测目标；受控自动采纳按 [渐进规划](docs/ai-verification-roadmap.md)另过标注验收后决定。

风险页提供资产构成、个股/行业集中度、压力情景和相对净本金盈亏图表。点按明细、翻页或拖动压力滑块只更新显示，不修改账户。未具备历史估值与带日期的资金流时，不生成净值或高点回撤曲线。

持仓导入历史保留最近20条，按25项查看完整差异。选择记录并预览后，可确认恢复导入前的现金、持仓、日期与来源状态，保留当前研究、资金和风险偏好；成功后关闭自动读取。历史也进入 JSON 备份。CSV 支持逗号、制表符、分号；GBK 必须明确确认，未知/歧义表头须手动映射，不接受可卖量和成本价替代总数量与市价。

v06_acceptance_test.dart 扩展真实磁盘、图表交互、研究与资金修改后恢复、GBK 列映射及跨端历史保留；原生入口位于 integration_test，使用 V06_EXPORT_FIXTURE / V06_IMPORT_FIXTURE 指定传输夹具。

v07_acceptance_test.dart 在真实磁盘走通未启用示例、明确确认、权重与阈值手算、取消保留、证据与研究入口、流水期初与新增、账户累计字段只读和跨端备份。原生入口使用 V07_EXPORT_FIXTURE / V07_IMPORT_FIXTURE。`dart run tool/live_history_probe.dart` 仅手动验证公开历史日线，不写工作区或调用模型。
