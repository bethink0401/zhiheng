# 知衡 Zhiheng

知衡是一款面向成年用户的 iPhone AI 健康洞察与行动助手。它读取用户授权的 Apple Health / Apple Watch 数据，先建立“和过去的自己相比”的个人基线，再结合用户主动记录的感受与生活情境，给出可解释、低焦虑、可执行的下一步。

知衡不是疾病诊断、治疗、处方或持续急救监护软件。

## 产品闭环

```text
Apple Health / Apple Watch
        ↓
数据质量与来源检查
        ↓
个人基线与稳健趋势
        ↓
今日感受与生活事件
        ↓
可解释洞察
        ↓
3～7 天低风险微计划
        ↓
执行记录与计划评估
        ↓
我的有效方法
        ↓
基于结构化事实包的 AI 对话
```

## 核心能力

- 个人基线优先：主要比较用户与过去的自己，不用单一综合分数替代解释。
- 数据质量守门：处理缺失、断档、未佩戴、权限不足、来源变化和单日异常，不把未知补成零。
- 主客观并列：同时呈现健康指标、精力、压力、身体感受和生活背景，不用设备数据否定用户感受。
- 可解释洞察：分开事实、可能因素、不确定性和建议，避免把相关性写成因果性。
- 微计划闭环：一次只建议一个可停止的短计划，使用 CareKitStore 记录日程、任务和执行结果。
- 方法沉淀：根据多次计划的客观变化、主观变化、完成率和数据质量，形成“我的有效方法”。
- 安全 AI：AI 只解释客户端构建的聚合健康事实包，不读取原始 HealthKit 样本，也不能自行诊断或调整药物。
- 演示模式：使用同一虚构人物的连贯合成数据覆盖五个主要模块；演示感受和生活事件可在本次运行内编辑，但不会接触真实数据。

## 技术架构

| 层次 | 主要技术与职责 |
| --- | --- |
| UI | SwiftUI、Swift Charts、自定义低焦虑信息卡片 |
| 健康数据 | Apple HealthKit，只读取用户授权的数据 |
| 行动计划 | CareKitStore，负责 CarePlan、Task、Schedule 与 Outcome |
| 本地数据 | SwiftData，保存感受、生活事件、洞察、分析快照与方法展示偏好 |
| 分析 | Swift 实现的数据质量、基线、趋势、主客观对照与计划评估 |
| AI | 可替换 `AIService`；开发阶段支持 DeepSeek Responses API / 本地代理 |
| 测试 | XCTest，覆盖算法、数据隔离、CareKit、AI 安全和失败降级 |

真实数据、演示数据和测试 Fixture 通过同一协议边界替换。页面不直接访问 HealthKit、CareKitStore 或模型供应商 SDK。

## 隐私与安全边界

- 原始 HealthKit 样本默认只在本机处理，不上传。
- 用户主动提问时，AI 只接收完成回答所需的最小化聚合事实包。
- 事实包排除原始样本、设备标识、精确事件时间、底层记录 ID 和未授权字段。
- 通知锁屏内容不显示健康数值、症状、备注或计划反馈。
- 演示数据与真实 HealthKit、SwiftData、CareKitStore 隔离。
- 项目不提供疾病诊断、处方、停药、剂量调整或急救监护。

## 开发与运行

项目当前只支持 iPhone，使用 Xcode 打开：

```text
Zhiheng/Zhiheng.xcodeproj
```

依赖由 Swift Package Manager 管理，主要包括 CareKit、CareKitStore、swift-collections、swift-async-algorithms 和 FHIRModels。首次构建需要 Xcode 解析 Swift Package 依赖。

无签名 Debug 构建示例：

```bash
xcodebuild build \
  -project Zhiheng/Zhiheng.xcodeproj \
  -scheme Zhiheng \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

测试建议使用已安装的 iOS Simulator：

```bash
xcodebuild test \
  -project Zhiheng/Zhiheng.xcodeproj \
  -scheme Zhiheng \
  -destination 'platform=iOS Simulator,name=<available-simulator>' \
  CODE_SIGNING_ALLOWED=NO
```

正式运行真实 HealthKit 功能需要开发签名、iPhone、Apple Health 授权以及项目要求的配置。AI 网络代理和密钥不应写入源代码或提交到 Git。

## 项目文档

- [开发需求规范](docs/development-requirements.md)
- [技术设计规范](docs/technical-design-spec.md)
- [实施总方案](docs/implementation-plan-v1.md)
- [隐私说明与数据流](docs/privacy-data-flow.md)
- [开发执行步骤](docs/execution-steps.md)
- [每日开发日志](开发日志/README.md)
- [第三方开源声明](THIRD_PARTY_NOTICES.md)

## 当前状态

知衡已完成主要健康数据、趋势、洞察、微计划、计划评估、有效方法、AI 事实包和演示模式闭环。当前仍保留真实 HealthKit 场景下的性能与标签切换复测，以及发布前的敏感日志审计。

## 许可证

本仓库的项目代码和文档许可范围以仓库后续发布说明为准。第三方依赖及参考项目遵循各自许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
