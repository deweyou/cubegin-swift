# 验证

所有命令在本仓库根目录执行。正式运行 scheme 是 CubeginApp。

```sh
xcodebuild -project Cubegin.xcodeproj -scheme CubeginApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
swift test --package-path Vendor/CubeginSDK
```

定向运行时用 xcrun simctl list devices available 获取设备 UUID，以
platform=iOS Simulator,id=<UUID> 作为 destination。在 Xcode 27 使用 Device Hub
显示设备窗口；老版本的 Simulator.app 路径不适用于当前安装。

SDK 更新后至少执行：安装文件校验、独立包消费者测试、正式 App 新构建、模拟器
运行。不要用没有 SDK 的 Preview 工程通过构建来证明核心接入成功。

手动检查真实打乱和 SVG 显示、项目切换、开始/停止、成绩重启后保留、后台中断取消、
错误提示以及 Cross 输出。检查 iPhone/iPad 尺寸、横竖屏、浅色/深色、字体放大、
VoiceOver 和降低透明度。计时器核心状态改变时应补充独立时钟/存储验证，避免只测视图。

host SwiftPM 测试验证 SDK 调用与消费；模拟器截图验证特定运行画面；签名真机运行、
设备渲染、完整交互验收和发布均为独立结果，不可相互替代。
