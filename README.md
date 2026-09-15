# macTilt Duo 中文整合版

让 MacBook 在合盖时显示类似 iPhone Duo 的空间投影与磨砂玻璃动画。

本项目以 macTilt 的 macOS 桌面捕获、铰链角度读取和覆盖窗口为基础，移植
DuoLikeAnimation 的固定画面平面、视线投影、渐进散射与衰减算法，并提供
完整简体中文界面。已在 M5 MacBook Air 与 Apple M5 GPU 上验证。

## 功能

- 直接读取支持机型的内置铰链角度传感器
- 合盖时捕获当前桌面，以屏幕底边为转轴进行透视重投影
- 随屏幕与原画面间距增加的渐进虚化、暗化和两侧黑场
- DuoLikeAnimation 磨砂玻璃与 macTilt 原版效果切换
- 观看距离、虚化、反光、暗边、触发角度和跟随速度调节
- 交互滑块预览，无需实际移动屏幕
- 简体中文菜单、设置、引导和权限提示
- 修复开发构建后屏幕录制权限反复失效的问题

## 构建

要求 macOS 14 或更高版本、Apple Silicon Mac、Command Line Tools 和
OpenSSL 3。应用需要屏幕录制权限才能捕获桌面。

```sh
bash setup-local-signing.sh
bash build-local.sh
```

解压 `build-local/macTilt Duo.zip`，把应用移到 `/Applications` 后运行。
请勿直接从 iCloud 或其他文件同步目录运行 `.app`。

首次创建的固定本机签名身份保存在被 Git 忽略的 `.local-signing/`。
以后更新必须复用它，否则 macOS 会把新构建识别为另一个应用，要求重新授权。
如需将签名目录放在其他位置：

```sh
MAC_TILT_SIGNING_DIR=/绝对路径/签名目录 bash setup-local-signing.sh
MAC_TILT_SIGNING_DIR=/绝对路径/签名目录 bash build-local.sh
```

## 验证渲染器

```sh
"/Applications/macTilt Duo.app/Contents/MacOS/macTilt" \
  --render-check "$PWD/verification"
```

测试会在本机 GPU 离屏渲染并检查原图一致性、投影参考点、虚化、模式切换、
黑屏收尾与反向拖动，同时输出检查图片。

## 来源和许可证

- [macTilt](https://github.com/lqSky7/iphone-duo-macos-animation)，固定于
  `a1745b9159d64fae38038b24d5d0e5fcb09f2ce3`。该版本未附许可证。
- [DuoLikeAnimation](https://github.com/elijah-semyonov/DuoLikeAnimation)，固定于
  `0aa525639a494be8abdf4c4e1e25dcb52d372d94`，使用 MIT 许可证。

DuoLikeAnimation 的 MIT 许可证与原始参考文件保留在
`ThirdParty/DuoLikeAnimation/`。macTilt 的原始 README 保留在
`docs/UPSTREAM_README.md`。更详细的整合、适配和权限修复说明见
[`INTEGRATION.md`](INTEGRATION.md)。

macTilt 上游版本未提供许可证。本仓库保留来源与提交历史；这并不表示取得了
重新发布、再许可或商用授权。
