# v0.1 验证记录

完成日期：2026-10-01（Asia/Shanghai）。

## 构建与运行

- Windows x64 Release 构建成功。启动后进程保持运行，应用支持目录生成了有效的模拟账户 JSON。发行目录含 Flutter 引擎、应用资源、JNI 库与 Visual Studio 提供的 C++ 运行库。
- Android Release APK 构建成功；通用包包含多个目标架构，使用调试密钥签名供本地体验。
- 在 Pixel 4 XL / Android 10（API 29）x86_64 模拟器中安装并启动了 Android 包，界面正常。
- 使用模拟器界面录入一条复查记录，强制停止并重启后仍可读取该记录；升级安装 Release 包后，界面再次显示保留的记录。检查当前应用进程日志，未发现 Flutter 错误或致命异常。
- Android 实机尚未连接，因此尚未验证具体手机的文件交互、厂商系统行为或大字体设置。没有应用商店发布。

## 自动检查

- Flutter 静态检查：无问题。
- 13 项功能测试全部通过，覆盖：包含现金的仓位与压力测试、非正本金处理、资金流口径、备份往返、异常导入拒绝、文件保存与恢复、损坏文件保留、研究卡修改前内容保存、非法持仓输入拒绝、桌面与手机尺寸布局、复查记录保存及重开。
- 单独生成并检查桌面和手机布局预览，加载中文与 Material 图标字体；手机首屏能同时展示资产、仓位和盈亏。

## 构建环境处理

- Flutter 官方 Git 地址连接不稳定，改用官方 stable 源码压缩包，保留引擎版本 pin，并建立本地 Git 快照以启动工具。
- Windows 插件链接使用项目内 junction，未修改系统开发者模式。
- 补充了 Android 命令行工具、API 36 / 35 平台、Build Tools 36.0.0、NDK 28.2 和 CMake 3.22.1。命令行工具下载文件已校验官方 SHA-256。
- Gradle 通过电脑已有的 Windows 代理连接下载；一次 Android 依赖 TLS 握手失败，经自动重试后构建成功。Gradle wrapper 的发行包使用官方 SHA-256 校验。

## 当前产品限制

当前数据是虚构示例或人工录入。没有真实行情、自动财报更新、模型 API、后台通知、云端同步、量化回测或自动交易。研究卡是人工填写的依据记录，不是自动选股排名。

目前只计算现金与股票资产。20% 是相对本金的个人亏损偏好提醒，实际亏损可能超过它。账户高点回撤缺少经过现金流调整的历史序列，界面明确显示无法计算。

Android 使用模拟器验证；桌面保存与自动测试已验证，但尚未在另一台 Windows 电脑进行完整部署测试。

## 体验文件

- `artifacts/windows-v0.1/lianghua_assistant.exe`：在整个目录保留完整的情况下双击运行。
- `artifacts/lianghua-windows-v0.1.zip`：可复制到其他 Windows 电脑，完整解压后运行 exe。
- `artifacts/lianghua-android-v0.1.apk`：传到安卓手机进行本地安装，属于测试签名包。
- `docs/preview/desktop.png`：桌面 UI 渲染预览。
- `docs/preview/android.png`：手机 UI 渲染预览。
- `docs/preview/android-emulator.png`：实际安装包的安卓模拟器截图。
