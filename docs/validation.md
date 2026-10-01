# v0.2 验证记录

完成日期：2026-10-01（Asia/Shanghai）。本轮显示名为「未名溪谷」。

## 已通过

- 静态检查：无问题。23 项功能与界面测试通过，包含旧版 13 项回归以及 v1 原文件保留迁移、空财务值与负利润/现金流、报告期间分组、错误来源关联、伪造引用拦截、人工接受前不改研究卡、接受后保留前后版本、行情身份核验、排除未完成日线、前导零、部分/失败/混合日期行情拒绝估值、备份往返一致风险结果、HTTP 重定向不转发密钥及错误响应脱敏。
- Windows 原生集成测试：系统安全存储写入、读取、删除独立的非密钥哨兵成功；固定旧数据目录正确；应用 Dart HTTPS 客户端查询 SZ:000001 平安银行并获取 2026-09-30 收盘价 11.57 成功。
- Android 10 / API 29 / x86_64 模拟器：相同原生安全存储与独立 HTTPS 查询测试通过，同样得到上述交易日期和价格。手机端不依赖 Windows 本地服务。
- 桌面 Dart 独立客户端同时查询 SH:600000 浦发银行（银行Ⅱ）与 SZ:000001 平安银行（银行Ⅱ），2026-09-30 收盘价分别 9.48、11.57。获取时点为 2026-10-01；未混入当日日线。
- Windows 旧 workspace.json 实际启动迁移到 schemaVersion 2，原 3 项持仓、5 张研究卡保留，workspace.json.v1.bak 存在；新名称进程启动并响应。
- Android 从原 v0.1 Release 包录入 Upgrade_v01_to_v02_preserve_this_review 复查，再覆盖安装 v0.2；最终发行包又以 Final_release_upgrade_preserves_v01_review 重测通过；未名溪谷界面仍显示原记录，applicationId 与测试签名保持兼容。模拟器测试目录也确认 schemaVersion 2。
- 1280×900 桌面和 390×844 手机 UI 渲染通过，已检查中文、图标、真实日线展示与小屏换行。

## 构建与构建脚本

- Windows x64 Release 与 Android 通用 Release APK 均完成构建；最终包使用 main.dart 入口，无预置密钥。Android 是测试签名，不是应用商店签名。
- 项目 SDK 为 Flutter 官方 stable 源码快照，当前本机报告 Flutter 3.47.4-0.0.pre-1 / Dart 3.13.4；跨机器建议使用官方完整 stable SDK。
- Windows 无符号链接权限时使用项目内 junction。修正了脚本：补建链接后再运行 pub get，完成 Android 与 Windows 新插件注册；旧 v0.1 CMake 目标缓存由脚本移除单个生成文件。
- Android 模拟器初次升级后 VM 套接字被系统拒绝；重启测试模拟器后恢复。缺失插件注册已定位并修复，修复后的两端原生测试均通过。未改变电脑系统的开发者模式或权限设置。
- 模拟器软件 GPU 的 Impeller shader 有兼容问题，原生集成测试使用 --no-enable-impeller；发行包实际启动另行检查。

## AI 与数据来源的验证边界

- DeepSeek 官方 Chat Completions / JSON 接口格式已核对；本地模拟响应验证五节草稿、来源 ID、逐字摘录、截断或空响应拒绝、人工核验门槛以及保存前后版本。
- 没有取得或使用用户真实 DeepSeek 密钥，因此未声称真实账户鉴权、余额检查或真实模型生成已通过。安装后在「DeepSeek 本地设置」录入密钥，检查连接并使用有出处资料生成。
- 引用检查只证明引用 ID 与摘录存在于输入，不证明判断在逻辑上成立；原文真实性、数字口径及推测仍需人工核验。
- 财务数字先人工录入，缺失保留 null；营收/扣非利润/现金流为期间数，现金与有息负债为期末余额。仅相同起止日期与单位的记录放在一个比较组。金融行业保留独立口径说明，不自动打分。
- 行情实测覆盖沪深两只股票。公共接口并无稳定性保证，科创、创业、北交所及各类停牌情形未逐一实测。网络失败保留旧价格与错误状态；账户价格仅在全部匹配、同日且不回退日期时统一应用。
- [DeepSeek 官方请求说明](https://api-docs.deepseek.com/api/create-chat-completion/)；[AKShare 股票数据接口文档](https://akshare.akfamily.xyz/data/stock/stock.html)。

## 仍未验证与后续范围

Android 实机、另一台 Windows 部署、大字体及厂商系统差异尚未实测。密钥换设备需要重设；研究备份明文 JSON 手动传输。未实现自动抓财报、PDF/OCR、全市场排名、现金流调整的历史净值/高点回撤、后台提醒、云同步和自动交易。

## 体验文件

- artifacts/windows-v0.2/weiming_xigu.exe：完整目录内直接运行。
- artifacts/weiming-xigu-windows-v0.2.zip：完整解压使用。
- artifacts/weiming-xigu-android-v0.2.apk：测试签名 APK，可覆盖同签名 v0.1。
- artifacts/SHA256SUMS-v0.2.txt：发行包 SHA-256。
- docs/preview/desktop.png / android.png：演示账户布局。
- docs/preview/desktop-research.png / android-research.png：真实查询的自选与日线布局。
- docs/preview/android-emulator.png：最终发行包实际安装的模拟器截图。
- docs/preview/android-upgrade.png：最终 APK 覆盖安装后保留 v0.1 复查记录的截图。

v0.1 的原验收记录与源码可通过 Git 初始提交 cd2adc6 查看，本轮未删除原体验包。
