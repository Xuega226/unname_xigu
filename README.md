# 研股手记 v0.1

Windows / Android 共用的 Flutter 原型。默认使用虚构公司、虚构代码和模拟持仓；没有获取真实市场数据或调用 AI 服务。

下一轮将正式更名为“未名溪谷”，建议开发范围见 [v0.2 计划](docs/v0.2-plan.md)。当前 v0.1 应用和体验包仍保留原名。

已实现：

- 公司研究卡新增、编辑、来源记录；缺来源时提示资料不足。
- 账户资金设置、持仓增删改、个股及行业占比、相对本金盈亏。
- 指定股票下跌情景的压力测试，亏损偏好默认 20%。
- 复查记录追加；编辑公司研究卡时保留修改前内容。
- 本机 JSON 保存及上一版文件备份；JSON 文本导入、导出，可在两端手动交换。
- 桌面侧边导航、手机底部导航与小屏布局。

## 使用

从默认模拟工作区体验。准备录入自己的资料时，通过右上菜单先导出需要保留的记录，再选择“新建空白工作区”。手动录入的数据会一直标记为未核验。

价格不会自动更新：请在“账户设置”记录估值日期，并录入该日期的所有持仓价格。入金和出金是账户资金流，不是股票买卖金额。当前资产范围为现金与股票，不支持融资负债。

相对本金亏损与账户高点回撤不同。当前版本没有现金流调整后的历史净值序列，因此不计算高点回撤。20% 是个人偏好提醒，不能保证亏损不超过它。

“复制 AI 分析模板”只复制研究提示词，尚未调用任何模型。应用不发出买卖指令，也没有后台提醒、云端同步或登录功能。

## 开发与运行

在项目根目录 `F:/lianghua` 的 PowerShell 中执行：

```powershell
./tools/flutter.ps1 -Task run-win
./tools/flutter.ps1 -Task check
./tools/flutter.ps1 -Task build-win
./tools/flutter.ps1 -Task build-android
```

脚本优先使用项目 `.tools/flutter`，也支持系统 PATH 中已有的 Flutter。构建要求 Windows 的 Visual Studio C++ 桌面工具链，以及 Android SDK 和兼容的 JDK。脚本只设置当前进程的环境变量；Windows 未启用符号链接权限时，使用项目目录内的 junction 链接。

本机 Flutter 安装来自 Flutter 官方 stable 源码压缩包，保留原始 engine.version；为了启动工具建立了本地 SDK Git 快照，因此版本输出带本地修订信息，不能据此进行上游升级。迁移开发环境时建议安装官方完整 stable SDK，保留项目 pubspec.lock。

Windows 发行包需保留 exe、DLL 和 data 目录一起使用，不应只复制 exe。Android 初版使用调试签名供本地体验，不用于应用商店发布。

## 数据位置与恢复

通过 path_provider 获取各平台的应用支持目录，保存 `workspace.json` 与 `workspace.json.bak`，不使用固定 Windows 路径。没有主文件但有备份时可恢复备份；主文件格式损坏时保留原文件并报告错误，不覆盖为模拟数据。

导入需格式检查和替换确认。备份以明文 JSON 保存，包含持仓与研究记录；卸载或清除应用数据前请手动导出。两端导入会替换工作区，不进行自动合并。

核心计算位于 `app/lib/domain.dart`，存储位于 `app/lib/storage.dart`，界面位于 `app/lib/main.dart`。Python 数据采集与 AI 接口将在后续独立接入。

验证结果与已知限制见 [验证记录](docs/validation.md)。桌面与手机布局预览位于 `docs/preview/`。
