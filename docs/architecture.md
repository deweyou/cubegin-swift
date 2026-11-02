# App 架构

CubeginApp 是 SwiftUI 入口；ContentView 负责响应式布局、系统玻璃控件和交互。
TimerModel 是 MainActor 上的 Observable 产品状态，Engine 是后台 SDK 适配层。

Engine 仅封装生成打乱、获取 SVG、Cross 辅助求解。Rust 拥有魔方语义，App 不复制
移动规则、打乱算法或求解器。安装的 Vendor/CubeginSDK 是唯一引擎依赖。

计时以 ContinuousClock 计算时长，TimelineView 刷新显示；进入非 active 状态会取消
当前计时且不保存。当前交互是轻触开始/停止，不是按住准备或比赛观察流程。

Solve 保存 UUID、秒数、项目、打乱、日期。成绩以 JSON 原子写入 App Documents 的
solves.json，读取与写入失败通过界面提示。统计为当前项目的历史次数、最佳和算术平均，
不是 ao5/ao12。当前没有数据库迁移、云同步和训练分组。

SVG 由 Rust 生成，App 使用禁止 JavaScript 的 WKWebView 显示。原生渲染和控件归
产品负责；SDK 不提供视图。Cross 当前显示 SDK JSON，尚未产品化为解法列表。

iPhone/iPad 使用同一布局，内容宽度上限 880；支持窗口宽度变化。当前尚无专门的
横屏双栏设计。维护时需检查字体放大、VoiceOver、系统深浅色及降低透明度效果。
