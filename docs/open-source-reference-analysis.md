# 开源参考项目分析与采用决策

更新日期：2026-08-27

## 1. 目的与结论

本文件记录知衡第一版对 HealthGPT、CareKit 和 SpeziHealthKit 的源码级研究结果，回答“参考什么、直接依赖什么、必须重写什么”。

最终决定：

- 健康数据唯一访问层使用苹果原生 HealthKit。
- CareKitStore 是微计划、任务、日程和执行结果的唯一事实来源；第一版不使用 CareKitFHIR。
- HealthGPT 只作为健康数据连接 AI、对话状态和模型抽象的重点参考，不作为产品底座。
- SpeziHealthKit 只参考权限、样本更新、睡眠和测试设计，第一版不引入 Spezi/SpeziHealthKit 依赖。
- 趋势、个人基线、数据质量、主客观对照、计划效果和“我的有效方法”均由知衡独立实现。

## 2. 固定版本与许可证

| 项目 | 仓库 | 固定版本或提交 | 许可证 | 知衡中的角色 |
| --- | --- | --- | --- | --- |
| HealthGPT | `StanfordBDHG/HealthGPT` | tag `0.5.1`，commit `0673a1c79e7af3a71b10fbb2ce217102c3b4522a` | MIT | 源码参考 |
| CareKit | `carekit-apple/CareKit` | tag `4.1.0`，commit `348a5efbd10cb79d92c760c8023156015558b06b` | BSD-3-Clause | 计划直接依赖 CareKitStore |
| SpeziHealthKit | `StanfordSpezi/SpeziHealthKit` | commit `5341a7a521fb4d14c88304e0f0622a94a095eef8` | MIT | 源码参考，不作为第一版依赖 |

源码研究副本位于系统临时目录，仅用于只读分析，不属于项目源代码，也不应提交到项目仓库。真正添加 Swift Package 依赖时必须再次固定版本并检查其传递依赖许可证。

## 3. HealthGPT 分析

### 3.1 已确认的数据与 AI 流程

HealthGPT 当前版本通过 HealthKit 权限配置获得授权，但具体健康数据读取由直接创建的 `HKHealthStore` 完成。其主要流程为：

```text
HealthKit 查询
  → 最近 14 天按日聚合
  → 生成自然语言健康数据文本
  → 拼接模型提示词
  → 本地、Fog 或云端模型
  → 流式对话界面
```

当前源码覆盖步数、睡眠、活动能量、锻炼分钟、体重和静息心率等数据；没有形成知衡需要的 HRV 统一分析模型。

### 3.2 可以参考

- HealthKit 授权引导和健康数据获取职责的拆分。
- 数据获取、提示构建、模型服务和聊天界面的模块边界。
- 本地、Fog、云端模型之间的可替换抽象。
- 流式输出、取消、重试和清空会话的交互状态。
- 使用 Keychain 保护用户密钥的方向。
- 使用模拟数据支持无真机演示和测试的思路。

### 3.3 必须重写或避免

- 不把缺失日填成 0；知衡必须保留“缺失”和“真实为零”的区别。
- 不直接把逐日原始值拼成长段提示词；先生成结构化、最小化、可追溯的健康事实包。
- 不用 `try?` 静默吞掉健康数据错误；界面必须区分未授权、无数据、查询失败和真实零值。
- 不直接累加可能重叠的睡眠样本；先按来源和时间区间去重、合并。
- 不让大模型自由计算趋势或作医学判断；趋势和数据质量由本地确定性算法产生。
- 不默认上传最近 14 天健康数据；远程 AI 必须明确同意、最小化发送，并提供不开启 AI 仍可用的核心功能。
- 不复用品牌、完整界面、原提示词或产品叙事。

### 3.4 本地构建与运行尝试

2026-08-21 使用固定 tag `0.5.1` 进行只读验证，参考仓库始终保持零修改。Swift Package Manager 成功按 `Package.resolved` 解析 33 个依赖。首次构建需要确认 SwiftLint 与 OpenAPI Generator 插件；跳过临时参考构建的交互式插件校验后，编译进入 MLX，并按 Xcode 提示补装 Metal Toolchain 17F109。

最终阻塞并非 HealthGPT 业务源码诊断，而是 Xcode 26.6 所带 Swift 6.3.3 编译器内部崩溃：编译 SpeziStorage 2.1.2 的 `KeychainStorage+Credentials.swift` 时在 `MandatoryAllocBoxToStack` 阶段退出，`arm64` 和 `x86_64` 模拟器切片均可复现。因此当前机器上未能启动 HealthGPT App，也未输入 API Key 或申请健康数据权限。

这次验证形成三项工程结论：

- HealthGPT 的本地模型路线会把 MLX、Metal 源码和大量传递依赖带入主应用，首次构建成本和工具链耦合较高。
- 知衡第一版只参考其数据到对话的职责划分，不直接采用整套 Spezi/MLX 底座。
- 知衡的 AI 接口必须保持可替换，核心健康事实、趋势和无网络降级不能依赖大模型框架能否编译或运行。

## 4. SpeziHealthKit 分析

SpeziHealthKit 提供长期和后台样本收集、增删样本回调、SwiftUI 查询包装、健康图表和批量导出等能力。它适合以 Spezi 为整体架构的研究型应用，但会引入 Spezi、SpeziFoundation、SpeziStorage、异步算法等依赖。

知衡第一版的关键工作是按需读取最近 28～90 天数据、进行确定性聚合并建立清晰的数据质量语义。HealthGPT 本身的核心读取同样直接使用 `HKHealthStore`。因此当前收益不足以抵消额外依赖、升级和调试成本。

采用决策：第一版使用原生 HealthKit；参考 SpeziHealthKit 的权限、样本删除、睡眠和测试设计。若未来出现可靠后台增量同步或多模块共享查询的强需求，再建立单独技术验证，不在现阶段预装依赖。

## 5. CareKit 4.1 分析

### 5.1 已确认的核心模型

- `OCKCarePlan`：一轮 3～7 天微计划。
- `OCKTask` 与 `OCKSchedule`：每日行动、日期、频率和目标。
- `OCKOutcome`：某次任务执行结果。
- `OCKOutcomeValue`：完成量、困难度或用户反馈，可保存整数、浮点、布尔、字符串、数据和日期等值。
- `OCKStore`：本地异步、版本化的计划数据存储。

CareKit 4.1 的最低平台为 iOS 18，使用 Swift tools 6.1。正式工程创建时必须据此统一知衡的最低 iOS 版本。

### 5.2 当前进度 API 注意事项

旧的 `OCKAdherenceAggregator` 已标记弃用并迁移到 `CareTaskProgressStrategy`。当前版本可使用 `OCKAdherenceQuery` 配合 `computeProgress`，或直接从 Outcomes 计算产品定义所需的完成率。

知衡不能只显示框架生成的抽象值。完成率计算必须：

- 明确分母是计划应执行次数还是有效可执行次数。
- 区分未完成、跳过、提前结束和没有数据。
- 保留对应的 task、occurrence、Outcome 和时间范围，便于解释与测试。
- 与客观数据、主观感受和数据质量一起参与计划效果评估。

### 5.3 依赖边界

- 计划直接依赖 CareKitStore。
- CareKitUI 只在技术样例中比较；正式 SwiftUI 页面可通过适配层自定义。
- 不引入 CareKitFHIR。
- SwiftData 不复制 CareKitStore 的计划完成状态。

## 6. 知衡采用清单

### 直接采用

- Apple HealthKit。
- CareKitStore。
- SwiftUI、Swift Charts、SwiftData、UserNotifications 和 Keychain。

### 只参考设计

- HealthGPT 的权限引导、服务分层、模型抽象和聊天状态。
- SpeziHealthKit 的样本更新、删除处理、睡眠和测试思路。
- CareKit 示例中的模型创建、Schedule、Outcome 和版本化查询方式。

### 独立实现

- 健康样本归一化、去重和按日聚合。
- 数据覆盖率、缺失语义和数据质量等级。
- 28 天个人基线、短期趋势和变化检测。
- 主观感受与客观状态对照。
- 结构化健康事实包和 AI 安全层。
- 微计划效果评估和“我的有效方法”。

## 7. 运行验证状态

- HealthGPT iOS App：依赖解析和编译尝试已完成；受当前 Swift 编译器与锁定 SpeziStorage 版本兼容问题阻塞，未启动 App，详见 3.4。
- CareKit OCKCatalog/OCKSample：默认分支没有 `.xcodeproj`，分别使用官方 `project-file`（commit `c99090c`）和 `missing-project-file`（commit `c6e764c`）分支；两者按自带的 2021 CareKit 锁定提交在 iPhone 17 Pro（iOS 26.5）模拟器构建、安装和启动通过，参考仓库保持零修改。Catalog 未授权时只显示 HealthKit 设置提示；Sample 能显示日历、任务与进度卡，但存在旧本地化占位符和较旧 UIKit 视觉，不能直接代表 CareKit 4.1.0 的正式产品 UI。
- CareKitStore 隔离样例：已完成三天 Schedule、Outcome、2/3 进度和任务版本历史验证。
- 正式 CareKitPlanStore：已完成计划、执行结果、进度、提前结束和版本选择适配；同名磁盘 Store 重建后能读回计划、Outcome 和最新结束版本，测试数据库显式清理，累计 22 个项目测试通过。

## 8. 2026-08-27 两项 AI 助手能力的补充候选筛查

本轮针对“读取 Apple Watch/Apple Health 数据回答健康问题”和“生成计划并写入微计划”再次筛查 GitHub。结论是：没有一个项目适合同时作为两项能力的整套产品底座；现有“原生 HealthKit + 健康事实包 + CareKitStore”的组合仍是最合适的直接复用方案。

| 项目 | 能力匹配 | 许可证与维护信息 | 采用判断 |
| --- | --- | --- | --- |
| `StanfordBDHG/HealthGPT` | 最贴近 Apple Health 自然语言问答，包含聊天、HealthKit、远程/本地模型抽象 | MIT；最新发布仍为 `0.5.1` | 继续只参考聊天状态、服务分层和模型抽象；不整体接入 Spezi/MLX，不复用其原始数据提示方式 |
| `carekit-apple/CareKit` | 直接覆盖 Care Plan、Task、Schedule、Outcome 和 Outcome Value | BSD-3-Clause；`4.1.0` 为最新发布 | 继续直接采用 `CareKitStore`，作为微计划唯一事实来源；计划推荐和安全筛选由知衡实现 |
| `StanfordHCI/GPTCoach-CHI2025` | 覆盖 HealthKit、LLM 工具调用和健康行为辅导研究流程 | 应用代码 MIT，但 Active Choices 对话提示为专有许可；仓库明确说明不再积极维护 | 仅参考工具调用和辅导流程研究，不复制受限提示，也不采用其上传三个月 HealthKit 数据到 Firestore 的架构 |
| `Kartha-AI/agentcare-ios` | 包含 SwiftUI 聊天、HealthKit/FHIR、MLX 端侧模型和数据筛选 | MIT；仓库规模小，当前主要面向临床记录 | 可参考端侧模型管理和按问题筛选上下文；不直接复用数据层，因为它不读取知衡需要的 Apple Watch 活动、睡眠与 HRV 数据 |
| `thinkwee/HiMe` | 功能表面上最接近，包含穿戴数据聊天与个性化健康计划 | PolyForm Noncommercial 1.0.0；研究级、自托管，并包含 iOS、watchOS 与服务端 | 不直接复用：非商业限制、系统范围和持续数据同步方式均不符合知衡第一版边界；只作产品能力对照 |
| `roian6/apple-health-ai-bridge` | 提供 HealthKit 到自托管 AI/MCP 的数据桥 | Apache-2.0；项目较新、体量较小 | 第一版不采用：需要额外接收端和数据同步，会扩大基础设施与隐私攻击面；可在未来确有自托管数据出口需求时重新评估 |
| `StanfordBDHG/LLMonFHIR` | iOS 上用 LLM 解释 Apple Health 中的 FHIR 临床记录，带任务式对话、研究配置和会话模拟 | MIT；基于 Spezi，支持 OpenAI、Firebase 与局域网 Fog 模型 | 不作为 Watch 健康问答底座：它读取的是医院 FHIR 病历，不是步数、睡眠、HRV 等 Watch 指标；可参考结构化资源解释、任务式对话和可重复会话评测 |
| `neiltron/apple-health-mcp` | 通过 MCP 提供只读 schema、SQL 查询和周期报告 | MIT；TypeScript/Node.js 22、DuckDB，依赖第三方 App 导出的 CSV | 不嵌入 iPhone App：它是电脑端 MCP 服务，不直接访问 HealthKit，也不能写 CareKit；可参考按问题取数、只读工具边界和最小结果返回 |
| `krumjahn/applehealth` | 解析原生 `export.xml`，生成指标、图表并连接多种本地/云端模型 | `pyproject.toml` 声明 MIT；Python CLI，仓库根目录未见完整 LICENSE 文件 | 不直接复制或依赖：不是 iOS/实时 HealthKit 组件；可参考来源优先级、重叠累计数据处理、单位归一化、诊断输出和模型提供者抽象，若复用代码需先补齐许可证文本与版权核对 |

### 8.1 对两项功能的直接复用结论

1. 健康问答不能整套复制 HealthGPT。知衡应继续复用自己已经完成的原生 HealthKit 数据层，新增结构化健康事实包、安全规则和可替换 `AIService`；HealthGPT 只提供交互与架构参考。
2. 微计划可以直接复用 CareKitStore 的计划、日程、执行结果、进度和版本历史；但“AI 推荐哪个计划”、计划是否低风险、计划前后效果和“我的有效方法”必须由知衡自己的确定性规则实现。
3. 不新增 Spezi、MLX、Firebase、自托管接收端或 watchOS App。当前候选没有带来足以抵消依赖、隐私和范围成本的新能力。
4. 如果下一步要做代码级复用验证，优先只验证 HealthGPT 的聊天状态/服务接口映射，不直接引入依赖；微计划继续沿用已经通过持久化测试的 `CareKitPlanStore`。

### 8.2 用户补充三个仓库后的排序

针对知衡当前两项设想，这三个仓库的参考价值排序为：

1. `neiltron/apple-health-mcp`：最值得参考 AI 如何用受限只读工具按问题取数，但不复用其 CSV、Node.js 或 MCP 运行形态。
2. `krumjahn/applehealth`：最值得参考导出数据的来源冲突、单位归一化和计算审计，但其 Python/`export.xml` 管线不能进入 iPhone 主流程。
3. `StanfordBDHG/LLMonFHIR`：最值得参考结构化健康资源解释与对话评测；因知衡第一版明确不做完整 FHIR，功能匹配度最低。

三者均不负责把 AI 生成的行动写入 CareKit 微计划。该能力仍应由知衡把经过安全筛选的模板 ID 映射为 `OCKCarePlan`、`OCKTask` 和 `OCKSchedule`，而不是让模型直接写任意计划内容。
