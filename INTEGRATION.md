# macTilt × DuoLikeAnimation — 本地整合版

这是基于两个现有项目的本地修改版。

| 来源 | 固定版本 | 使用内容 |
| --- | --- | --- |
| https://github.com/lqSky7/iphone-duo-macos-animation | `a1745b9159d64fae38038b24d5d0e5fcb09f2ce3` | macOS 应用、菜单与设置、ScreenCaptureKit、Metal 渲染器、内置铰链读取、平滑与休眠处理、原版效果 |
| https://github.com/elijah-semyonov/DuoLikeAnimation | `0aa525639a494be8abdf4c4e1e25dcb52d372d94` | 固定 UI 平面与观察点、视线投影、按玻璃间距计算的 Vogel 圆盘散射与衰减 |

## 使用

首次运行 `bash setup-local-signing.sh` 创建本机签名身份（需要 OpenSSL 3），
然后运行 `bash build-local.sh`。解压 `build-local/macTilt Duo.zip`，放入
`/Applications` 后运行。不要从 iCloud / 文件同步目录直接运行应用。
已有签名身份时，通过 `MAC_TILT_SIGNING_DIR` 指定原目录，避免重新生成身份。
编译需要 macOS Command Line Tools；着色器通过 Metal 运行时编译。
此脚本不会安装到 Applications、终止现有应用或修改上游版本号。

在首次引导中按需授予屏幕录制权限，用于捕获桌面。无需录制音频。
菜单栏显示真实铰链角度。“设置 → 动画效果”可选择：

- DuoLikeAnimation · 磨砂玻璃：默认整合效果。
- macTilt · 原版：上游效果，供对照。

“观看距离”以屏幕高度为单位调整观察距离；“虚化强度”调虚化。
“交互预览”的滑块可模拟合盖；释放滑块后沿用上游行为恢复桌面。
选用“内置图片 / 自选图片”可在未授予录屏权限时预览。
正常使用时沿用上游静止自动恢复机制，避免停在半开位置时桌面长期模糊。

## 适配范围

Duo 原项目是 iOS SwiftUI layerEffect，不能直接作用于整个 macOS 桌面。
移植保留其投影及散射数学，将侧边转轴改为屏幕底边，将 SwiftUI Layer
采样改为 macTilt 的 Metal 纹理采样。屏幕高度采用 900 虚拟点，使虚化
强度不随 Retina 分辨率变化；观察距离默认 2.5 个屏幕高度。角度跨度
来自 macTilt 设置的起止角。越界采样为黑色。

保留 macTilt 的可选反光和末段合盖渐黑，并提供完整原版效果切换。
新模式默认 side blackout = 1，此值保留物理投影；其他值是上游的艺术调节。
新模式的虚化来自距离，原版的速度额外虚化不应用到新模式。

独立 bundle ID：`local.david.mactilt-duo`，与原版设置及录屏授权分开。
上游更新检查在此构建中被禁用，避免误认为官方发行版包含本地整合。
上游私有 SkyLight 锁屏功能默认关闭；正常桌面效果不依赖它。
本地应用采用固定的本机开发证书签名，未做 Developer ID 公证。
签名身份默认保存在被 Git 忽略的 `.local-signing/` 隔离钥匙串中，
也可由 `MAC_TILT_SIGNING_DIR` 指定，不随应用分发。
签名要求同时绑定 bundle ID 与证书指纹，不再随每次编译的代码哈希变化。
构建时临时加入该钥匙串，签名后恢复原搜索列表并锁定钥匙串。
没有更改系统证书信任。若签名身份不可用，构建会停止，不退回临时签名。

2026-09-15 权限修复：去掉在后台用 ScreenCaptureKit 枚举/截图探测权限的
逻辑（这些调用可能弹出授权请求）；UI、捕获流和覆盖窗口统一使用有锁的
状态缓存，最多每两秒预检一次，手动刷新可立即检查。
旧 ad-hoc 版本的失效录屏记录需要移除一次，再由用户授权这个固定签名版本。

## 验证

```sh
bash build-local.sh
"/Applications/macTilt Duo.app/Contents/MacOS/macTilt" --render-check "$PWD/verification"
```

测试编译真实着色器并在本机 GPU 离屏渲染，检查原图一致、投影与独立 CPU
参考一致、虚化与模式切换有效、合盖黑屏、反向拖动确定性，并输出 PNG。
该测试不读取桌面，不模拟硬件测试通过；实际合盖的观感仍需移动屏幕验证。

## 来源与许可

DuoLikeAnimation 使用 MIT 许可证，全文与原始着色器、参数文件位于
`ThirdParty/DuoLikeAnimation/`，随本地应用一起保留。

macTilt 在上述版本未提供 LICENSE 文件。保留其完整 Git 历史及原作者信息，
本目录仅作为用户请求的本机整合实验；不能据此声称取得重新发布或再许可授权。
上游说明位于 `docs/UPSTREAM_README.md`，原 build.sh 保留供参考，
实际构建请使用 build-local.sh。
