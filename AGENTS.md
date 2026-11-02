# Cubegin Swift App workspace

本仓库拥有原生 iPhone/iPad 魔方计时器产品。核心打乱、状态、SVG 和求解语义由
cubegin-core 的 Rust SDK 实现；这里拥有 SwiftUI、手势、计时、成绩存储及后台调度。

- 开发前读 README.md 和与任务相关的 docs/ 文档。以工程和源码为准，及时修正文档。
- 使用 Swift 6 / SwiftUI；部署下限 iOS/iPadOS 26。采用系统 Liquid Glass，保持系统外观和可访问性。
- 正式工程是 Cubegin.xcodeproj，运行 scheme 为 CubeginApp。不要误选 SDK 的 Cubegin scheme。
- SDK 是 Vendor/CubeginSDK 中已安装的完整产物；App 不引用相邻 core 仓库。
- 不手改 Vendor 下的绑定或二进制，不在 Swift 重写魔方语义。引擎变更在 core 完成，再整体安装新 SDK。
- 升级通过 scripts/install-sdk.py；保留 SDK.json、Package.swift、绑定、二进制、测试、LICENSE、NOTICE 和来源说明。
- CPU 密集 SDK 调用必须由 App 在后台执行；调用是同步的，取消 Swift Task 不保证停止 Rust 计算。
- 计时使用单调时钟，持久化错误必须可见。保留每次成绩对应的项目、打乱和日期。
- 修改 SDK 或接入方式后验证打包消费者及正式 App；编译通过不等同于真机或视觉验收。
- 不提交构建缓存、个人 Xcode 状态或签名凭据；安装的 SDK 产物是产品依赖，应随仓库保存。
- 保留 GPL-3.0-only 和上游归属。不把本地候选产物描述成远程发布。
- 未经明确要求，不 commit、push、发布或上传。

## 知识库

| 文档 | 何时阅读 |
| --- | --- |
| README.md | 运行入口、前提、SDK 升级与知识库索引 |
| docs/architecture.md | 产品/core 边界、状态、计时与存储 |
| docs/sdk.md | 安装产物、版本清单、接口和后台调用 |
| docs/testing.md | 构建、消费者、模拟器、真机与视觉验证 |
| docs/status.md | 当前验证证据和未完成功能 |

用户提到 agent.md 时，本仓库以标准 AGENTS.md 为唯一代理规则入口，避免多份规则漂移。
