# 知衡开发环境清单

| 项目 | 当前值 |
| --- | --- |
| 检查日期 | 2026-08-21 |
| Mac | MacBook Air（Mac17,3） |
| 芯片 | Apple M5，arm64 |
| 内存 | 16 GB |
| macOS | 26.6.2（25G83） |
| 可用磁盘 | 约 211 GiB |
| Swift | Apple Swift 6.3.3 |
| Command Line Tools | 26.6.0 |
| 当前 Developer Directory | `/Applications/Xcode.app/Contents/Developer` |
| 完整 Xcode | Xcode 26.6（17F113） |
| iOS SDK | iOS 26.5、iOS Simulator 26.5 |
| 可用模拟器 | iPhone 17 Pro 等 iOS 26.5 模拟器 |

## 结论

硬件、内存、磁盘、Xcode、iOS SDK 和模拟器已经满足创建与编译知衡第一版的条件。iPhone 已由 Xcode 识别为可用运行目标；Personal Team、真机签名构建、安装、开发者 App 信任、前台启动、HealthKit 用户授权和当前六类数据可见性均已通过。

## 安全说明

Xcode 和 iOS 平台组件由用户自行安装。项目只执行版本与 SDK 只读检查，没有记录设备序列号、Apple ID、开发团队 ID 或其他账户信息。

## 后续处理

后续处理：

1. 创建最小 SwiftUI iPhone 工程并在 iPhone 17 Pro 模拟器构建。
2. iPhone 已完成信任并成为 Xcode 可用目标。
3. Personal Team、自动签名、首次真机安装、开发者 App 信任和首次启动已完成。
4. 用户已主动完成 HealthKit 数据选择；下一步只在本机汇总四类核心指标最近 90 天有效日。
