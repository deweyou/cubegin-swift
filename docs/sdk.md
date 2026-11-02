# SDK 安装与版本

正式工程依赖仓库内 Vendor/CubeginSDK 的 Cubegin Swift Package 产品。
无需相邻 core 仓库，也无需在 App 构建时运行 Cargo 或 Node。

## 升级

在 core 根目录运行 cargo xtask build-sdk ios，得到 CubeginSDK-<version>.zip 与
.sha256。对比可信构建提供的 ZIP 校验值后解压，在 App 根目录运行：

```sh
python3 scripts/install-sdk.py /path/to/CubeginSDK-0.1.0
```

安装器验证 SDK.json 中所有文件的 SHA-256，先准备完整副本，再整体替换 Vendor。
不要只换 XCFramework 或只换 Swift 绑定。当前安装目录需随产品仓库保存。

SDK.json 是版本与来源依据：schemaVersion、version、sourceCommit、sourceDirty、
sourceObservation、打包时间和 files。后续通用清单使用 packagedAt；早期候选使用
builtAt。源信息是打包时观察值，不是干净源码构建证明。当前候选有未提交修改，不能
仅凭 sourceCommit 重建；SDK 版本与 App 版本独立，核心版本源是 core Cargo.toml。

## 调用契约

Engine.swift 在 Task.detached 上调用同步 Rust 接口，结果再回到产品状态：

- generateEvent：项目 ID 与随机 UInt32 seed → 打乱公式。
- evaluateEvent：项目 ID 与公式 → 状态与 SVG 展开图。
- solveAssist：333、方法 JSON、公式、深度选项 → 辅助解法 JSON。

UI 不创建模拟公式。独立 CubeginPreview 工程缺少 SDK 时会明确报错。
SDK 的 seed 是可重现接口，不构成比赛随机性认证；后台任务取消也不保证终止引擎。

保留完整 LICENSE、NOTICE、docs/provenance.md。公开分发前还需处理来源可用性与
完整依赖归属；本地安装不代表公开发布。
