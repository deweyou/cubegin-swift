# 当前状态

## 2026-11-03 本地证据

- Xcode 27.2，Rust 1.96.0，Node 24.21.0，pnpm 10.33.0。
- core iOS SDK 构建成功；XCFramework 覆盖 iOS arm64、模拟器 arm64/x86_64、macOS arm64。
- SDK 完整 ZIP 解压后的 SwiftPM 消费者 2 项测试通过。
- SDK 0.1.0 已安装在 Vendor/CubeginSDK；当前为 dirty 本地候选，来源详见 SDK.json。
- 正式 App 以全新 DerivedData 编译通过，包解析位置为 Vendor/CubeginSDK。
- iPhone 18 Pro / iOS 27.2 模拟器成功启动，观察到真实 3×3 打乱与展开图。

这些结果不代表完整交互测试、iPad 视觉验收或真机验收。未进行远程 SDK 发布、签名
分发、App Store 发布；未因本次工作提交或推送。

## 已实现和待完善

已实现轻触计时、本地 JSON 成绩存储、按项目历史次数/最佳/平均、项目切换、真实打乱、
SVG、Cross 原始 JSON 展示、非 active 中断取消，以及基础系统玻璃界面。

待完善：按住准备、观察时间、+2/DNF、分组、ao5/ao12、成绩编辑、导出/同步、友好解法
呈现、应用图标、iPad 专门布局、完整辅助功能和持久化迁移验证。SDK 长耗时调用调度、
应用中断策略与完整产品体验还需继续验收。

## 通用清单更新

已重新安装 core 通用 metadata 机制生成的 SDK 0.1.0，清单含 artifact 和 packagedAt，
安装校验通过；安装后的 SwiftPM 消费测试 2 项通过。此次未新增真机或 iPad 验收证据。
