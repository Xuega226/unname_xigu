# 应用图标

`unnameko-stock-icon-v2.png` 是项目已生成的原始图标（1254 × 1254），生成提示词保存在同名 `.prompt.md` 文件中。应用资源只缩放整个画面，不裁切或重绘。

在项目根目录运行：

```powershell
./tools/create-brand-icon.ps1
```

该脚本使用项目 Flutter SDK 中的 Dart 和已安装的 `image` 包，生成以下资源：

- 应用内图片：`app/assets/branding/unnameko-stock-icon-v2.png`，512 × 512。
- Windows：`app/windows/runner/resources/app_icon.ico`，包含 16、24、32、48、64、128、256 像素七个尺寸。
- Android：各 `mipmap-*` 目录的 `ic_launcher.png`，对应 48、72、96、144、192 像素。清单中的普通及圆形启动图标均引用此资源。

首次运行需要配置 `.tools/flutter`，并在 `app` 目录运行 `../.tools/flutter/bin/flutter.bat pub get` 获取项目依赖。
