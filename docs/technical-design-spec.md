# 知衡第一版技术设计规范

| 项目 | 内容 |
| --- | --- |
| 文档版本 | V1.0 |
| 更新日期 | 2026-09-09 |
| 适用范围 | iPhone 第一版 MVP 与比赛版本 |
| 技术状态 | 架构基线；框架版本需在 S02/S03 实测固定 |
| 对应需求 | `docs/development-requirements.md` |

## 1. 设计目标

技术架构需要同时满足：

- HealthKit 数据接入稳定、权限边界清晰。
- CareKit 真正承担行动计划与结果记录。
- 健康趋势由本地确定性算法计算。
- AI 只解释经过验证的事实包。
- 真实、模拟和测试数据可以替换。
- 无网络时核心数据和趋势仍可使用。
- 未来可以扩展，但第一版不为多端和医院系统提前增加复杂度。

## 2. 技术栈

| 职责 | 默认技术 | 当前决策 |
| --- | --- | --- |
| iPhone UI | SwiftUI | 确定 |
| 健康数据 | 苹果原生 HealthKit | 已确定；SpeziHealthKit 仅作设计参考 |
| 行动计划 | CareKit、CareKitStore | 确定重点使用 |
| 主观与分析数据 | SwiftData | 确定 |
| 图表 | Swift Charts | 确定 |
| 通知 | UserNotifications | 确定 |
| 安全凭据 | Keychain、未提交配置 | 确定 |
| 网络 | URLSession 封装 | 默认 |
| AI | 可替换 `AIService`；开发阶段 DeepSeek Responses API 经本机代理 | 已实现并通过真实响应验收 |
| 测试 | XCTest 或 Swift Testing | 创建工程时确定统一方案 |

S02-16 已决定第一版使用自定义 SwiftUI 展示层，正式 App 只链接 CareKitStore，不链接 CareKit/CareKitUI 展示产品。计划、Schedule、Outcome、版本和持久化仍由 CareKitStore 负责；页面通过 `CarePlanService` 使用领域模型。证据与重新评估条件见 `docs/carekit-ui-decision.md`。

## 3. 分层架构

```text
Presentation
├── SwiftUI Views
├── Feature State
└── ViewModels
        ↓
Application
├── Use Cases
├── HealthDataService
├── CareKitPlanService
├── InsightService
├── PlanEvaluationService
├── AIService
└── NotificationService
        ↓
Domain / Analytics
├── Domain Models
├── DataQualityEngine
├── BaselineEngine
├── TrendEngine
├── StateComparisonEngine
├── FactPackBuilder
└── MethodEvaluationEngine
        ↓
Infrastructure
├── HealthKit Provider
├── CareKitStore Adapter
├── SwiftData Repositories
├── Demo Provider
├── AI Gateway
└── System Services
```

依赖方向只允许从上向下。Domain 与 Analytics 不导入 SwiftUI、HealthKit、CareKit UI 或具体 AI SDK。

## 4. 目录规范

创建工程后采用以下职责目录，实际工程名可以调整：

```text
Zhiheng/
├── App/
├── Features/
│   ├── Onboarding/
│   ├── Today/
│   ├── Insights/
│   ├── CheckIn/
│   ├── Plans/
│   ├── Assistant/
│   └── Profile/
├── Domain/
│   ├── Models/
│   ├── Protocols/
│   └── UseCases/
├── Data/
│   ├── HealthKit/
│   ├── CareKit/
│   ├── Persistence/
│   ├── Repositories/
│   └── Demo/
├── Analytics/
├── AI/
├── DesignSystem/
├── Support/
└── Resources/

ZhihengTests/
├── AnalyticsTests/
├── CareKitTests/
├── FactPackTests/
├── SafetyTests/
└── Fixtures/
```

## 5. 数据职责与唯一事实来源

### HealthKit

负责提供用户授权的客观健康数据。页面不得直接使用 `HKSample`；数据层先转换为知衡领域模型。

```text
HealthMetricSample
- id
- metricType
- startDate
- endDate
- value
- unit
- sourceName
- deviceName（可选）
```

需要统一处理单位、时区、来源和重复样本。缺失不转换为 0。

#### 当前步数来源规则

- `HealthMetricSource` 保留 HealthKit `sourceRevision.productType`，用于区分 Apple Watch、iPhone 和其他来源；不记录设备唯一标识。
- 同一天同时存在 Apple Watch 与 iPhone 步数时，当前原始样本汇总层选择 Apple Watch；没有 Watch 时选择 iPhone。
- 同一选定来源内的步数片段可以累计；不同来源不得直接相加。
- 两个或以上无法识别的第三方来源仍返回“无法安全合并”，不为了显示数值而制造重复计数。
- Apple 官方 `HKStatistics` 默认可以自动合并多来源。后续独立技术任务应比较系统合并结果与当前 Watch 优先规则，再决定是否把累计指标切换为统计查询；在真机对比完成前不静默改变口径。

#### 统一健康数据 Provider 边界

第一版统一 Provider 协议固定为 `HealthDataService`，不再创建同义的
`HealthDataProviding`：

- `HealthKitDataService` 是真实 Apple Health 实现。
- 演示数据实现同一个 `HealthDataService`，页面不判断底层数据来自 HealthKit 还是演示数据。
- `loadSnapshot(for:interval:)` 统一输出逐指标的可见样本、无可见数据、不可用和失败状态。
- 页面与算法只消费 `HealthMetricSample` 和 `HealthDataSnapshot`，不接触 `HKSample`。

如果以后需要拆分权限与样本读取，只能在出现第二个独立调用方或测试隔离问题后再拆协议，不能仅为名称一致增加重复抽象。

### CareKitStore

是计划执行事实的唯一来源：

```text
OCKCarePlan
└── OCKTask
    └── OCKSchedule
        └── OCKOutcome
            └── OCKOutcomeValue
```

通过 `CareKitPlanStore` 或等价适配层操作。SwiftUI 页面不能到处直接创建或查询 `OCKStore`。

当前正式微计划页通过共享的 `MicroPlanSession` 调用 `CarePlanService`，只展示领域模型。AI 建议先映射到十类白名单 `MicroPlanTemplate`，用户点击确认后才创建五天计划；同一时刻只允许一个进行中或暂停中的计划。今日完成、跳过、最多 160 字的可选反馈、暂停、恢复和提前结束均写入或更新 CareKitStore，界面不另存一份完成事实。可选反馈作为 `OCKOutcomeValue` 与同次完成或跳过保存在同一个 `OCKOutcome` 中，通过领域化的 `PlanOutcomeRecord` 回读，技术日志不记录反馈正文。

暂停使用版本化 `OCKCarePlan` 元数据记录暂停时刻和排除起点；恢复时以整日暂停区间重建 `OCKTask` 日程，并按暂停天数顺延结束日。当天已有 Outcome 时，暂停从次日开始排除，避免同日恢复造成多余顺延。已有 Outcome、稳定 occurrence 顺序和历史版本必须保留。

`CarePlanService.planHistory()` 提供全部计划的领域化历史，`CareKitPlanStore` 负责按稳定计划 ID 去重、把已过期活动计划归一为完成状态并按开始时间倒序返回。微计划页右上角以圆形 Liquid Glass 历史图标进入独立历史页；历史卡的计划、任务、日期、时间和完成率仍只来自 CareKitStore。

历史页删除单个已结束计划时，`MicroPlanSession` 通过领域协议协调 CareKitStore 与 SwiftData。CareKit 的删除是版本墓碑，删除 `OCKCarePlan` 不会自动让独立版本化的 `OCKTask` 和 `OCKOutcome` 不可见，因此适配层必须按 Outcomes、Task、CarePlan 的顺序删除完整对象链；随后按 `carePlanID` 清理 `PlanAnalysisMetadata`。删除失败不得显示成功，且不能影响其他计划 ID 的历史。

必须保留稳定 ID 和版本化历史。暂停、修改和提前结束优先通过 CareKit 支持的时间化版本更新表达，不直接篡改过去结果。

### SwiftData

#### 洞察领域契约（S09-01）

`Domain/Models/Insight.swift` 定义不依赖 SwiftUI、HealthKit、CareKit 或 SwiftData 框架的不可变 `Insight` 值，显式传入稳定 UUID，通过 `insightID` 字符串供后续跨存储关联。它保存生成时刻、覆盖基线与近期的半开分析范围、时区、数据模式、`s09-insight-v1` 模型版本，以及相互独立的事实、可能解释、不确定性、单个可选追问和单个建议。

- `InsightFact` 只承载指标与 `InsightMetricEvidence`：复用 `HealthMetricTrendEvidence` 的双窗口、有效日、聚合中位数、变化幅度、实际阈值、同向日、质量保护和算法版本，附所选来源；或承载明确不可用原因（未申请、系统不可用、无可见数据、读取失败、未加载、读取范围不足、来源冲突、未配置指标）。不存在自由文本事实字段，不以 AI 输出替代确定计算；无数据不补零。
- `InsightPossibleExplanation` 独立保存文字及支持事实 ID。`InsightContextReference` 仅保留记录种类、UUID、更新时间与模式，不复制备注或完成状态；S09-03 的匹配快照引用该结构并负责验证同一时期以及记录未编辑/删除，不推断关联或因果。
- `InsightRecommendation` 为继续观察或一个既有 `MicroPlanTemplateID` 候选，并引用支持事实；不得存储执行状态或创建 CareKit 计划。后续映射仍需用户确认。
- 唯一构造入口校验非空事实/不确定性、去重、半开范围与当地完整公历日（兼容 DST）、指标/单位、有限值、集中有效日门槛和质量状态一致性、同向日统计、引用完整性及主观引用模式/版本。数据不足、来源变化、孤立日保护保留为事实，但不允许据此构造解释或行动候选；不重新计算趋势、不宣称验证自由文本医学安全。

本步仅建立可测试的内存领域契约，不实现序列化、洞察表、迁移或已读/忽略写入。下述 `InsightRecord` 仍是后续 SwiftData 持久化职责规划，不是已存在的实体；落库/恢复时必须通过领域构造校验，不能绕过边界。它与图表展示模型 `InsightsDashboardPresentation`、AI 输出 `HealthAIResponse` 职责不同，后者不能直接充当本地事实。

#### 客观事实生成（S09-02）

`InsightFactGenerator` 是纯 Swift、无状态的领域工厂，只接收共享 `HealthDataSnapshot`、其 `loadedInterval`、`HealthAccessState`、数据模式、参考时刻、时区和指标白名单。默认指标来自 `HealthMetricTrendThresholdCatalog.todayCandidateMetrics`；生成器将输入按 `HealthMetricType.allCases` 固定排序，并为每项产生一个 `InsightFact`，不直接访问 HealthKit、SwiftData、CareKit、网络或页面。

- 参考日当天尚未结束，不进入分析；`analysisInterval` 为当前本地日零点之前的 35 个完整公历日，按 Calendar 加减 7/28 日而非固定秒数，覆盖夏令时。只有共享读取范围同时覆盖两个窗口才分析。
- 可见样本先按指标和半开窗口过滤，再交给现有 `HealthMetricTrendEvidenceBuilder`；结果原样保留双窗口、有效日、中位数、相对变化、配置/实际门槛、同向日、孤立值保护、来源稳定性和阈值版本。洞察层不复制中位数、MAD 或三档趋势算法。
- 步数、睡眠、活动能量和运动分钟沿用 `PreferredHealthMetricSourceSelector`；其他指标要求同日只有一个来源。同日无法选择为 `sourceConflict`；跨日精确来源变化即使供应方 bundle 未变也降级为 `sourceChanged`；最近完整日没有选中来源为 `recentDataGap`，避免把旧数据当作当前事实。
- 权限/读取状态与其他降级使用 `InsightDataUnavailableReason` 明确表达。`requestCompleted` 不等同于逐项授权，查询无可见数据仍是 `noVisibleData`，不会声称用户拒绝；缺失不补零。
- `s09-fact-generator-v1` 使用指标、分析截止日、时区、真实/演示模式和生成器版本构造 SHA-256 后截取为 RFC 9562 version 8 UUID。该 ID 只用于稳定关联：不包含原始样本 ID 或自由文本；同日刷新保持身份，跨日/模式/时区或生成规则升级形成新身份。输出仍是内存事实集合，不落库、不生成解释或行动。

S09-02 的合成测试覆盖稳定、持续上升/下降、当前/基线不足、间歇断档、最近日缺失、孤立异常、权限/失败/无数据、窗口不足、同日来源冲突、跨日来源变化、样本顺序/ID 无关性和 DST。客观事实本身不能据此声称相关性或因果关系。

#### 同期主观背景匹配（S09-03）

- `InsightContextMatcher` 是纯 Swift 规则层，从规范的 35 日 `InsightFactSet` 末端派生最近 7 个完整本地日，兼容 DST；`InsightContextWindow` 同时保留绝对半开范围和七个带原时区的 `SubjectiveLocalDay`。
- `InsightContextLoader` 在主线程通过既有 `SubjectiveRecordStore` 执行一次全有或全无读取：逐日读取签到，再读取与当前窗口相交的事件。真实模式才访问 Store；演示模式直接返回隔离状态。任一读取失败、签到日期/时区不同或记录损坏都不发布部分快照。
- `InsightMatchedCheckIn` 只复制三项枚举评分；`InsightMatchedContextEvent` 只复制事件枚举、强度和时间；二者都引用 `InsightContextReference`。备注和自定义名称不进入匹配对象，源 Store 仍是唯一事实来源。
- 同一记录精确重复会去重，冲突 ID 或同日多签到拒绝；输出按日期、时间和 UUID 确定排序。签到与事件可复用相同 UUID，因为引用类型参与区分。
- `validate(_:for:)` 用同一事实集重新读取完整快照并比较，因而新增、编辑、删除或移出范围都会返回 `stale`，读取错误不会被误报为空记录。
- 匹配容器只表达共享时间窗口，不保存支持事实 ID，不把背景绑定到某项指标，不生成解释、追问或行动。没有新 SwiftData Schema、缓存、页面、HealthKit/AI 访问或网络上传。

#### 最多一个关键追问（S09-04）

- `InsightFollowUpQuestionRule` 是纯 Swift、无状态且确定的规则，只接收同一规范 `InsightFactSet`、`InsightContextMatch` 和调用方可选的已处理问题 ID；输入模式、时区窗口、匹配器版本、事实/引用唯一性不一致时拒绝决策，而不是拼接部分背景。
- 输出为 `InsightFollowUpDecision`：要么给出一个 `InsightFollowUpQuestion`，要么给出明确的不提问原因。问题种类只分缺少主观背景、缺少生活背景和严格主客观不一致，保留支持事实 ID 与既有结构化引用，不复制备注或自定义名称。
- 质量合格的持续变化，或相对变化达到实际门槛的“值得继续观察”，才可进入变化分支；有效日不足、来源不稳定/非单一、孤立异常保护或弱变化不触发问题。缺签到优先补主观感受；已有签到而缺事件才补生活背景；两者都有时不询问，不把事件绑定为原因。
- 主客观不一致分支要求四类核心指标全部为质量合格的“未见明确变化”，且至少一次结构化签到为精力/身体感受 1～2 或压力 4～5；只在缺生活背景时询问，始终尊重主观感受。
- 演示模式不向真实用户提问。`s09-follow-up-question-v1` 使用问题种类、模式、时区和分析窗口截止时间生成 SHA-256 截取的 RFC 9562 version 8 UUID；同窗口同问题身份稳定，调用方传入已回答/忽略 ID 后返回 `alreadyHandled`，但本步不持久化处理状态。
- 本步不构造完整 `Insight`、解释、建议或 UI，不访问 Store、HealthKit、CareKit、网络或 AI。固定问句仍需后续 S09-08 医学与低焦虑文案审阅。

#### 四层洞察卡展示映射（S09-05）

- `InsightFourLayerCardFactory` 是纯 Swift、确定性的展示映射，只消费同一 `InsightFactSet`、明确的上下文状态和可选已处理问题 ID；页面不重复计算趋势，也不直接读取 HealthKit、CareKit 或 AI。
- `InsightFourLayerCardPresentation` 固定且只包含四个有序层：事实、可能解释、不确定性、建议。工厂优先选择一个质量合格的持续变化，其次选择达到实际门槛的观察项；完全稳定集、数据不足、来源变化、孤立异常和读取失败分别进入保守文案，不拼出强结论。
- 可能解释只使用 S09-03 已剥离自由文本的结构化事件种类或主客观不一致；事件只表达同期出现和可能相关，并明确不代表因果。上下文读取失败是独立状态，不能伪装成空背景并触发追问。
- 追问仍委托 S09-04 规则，展示层最多接收一个问题；演示模式不读取真实 Store，也不询问真实用户。问句明确可选，未回答内容不进入事实层。
- `InsightsView` 从 Root 注入的共享 `InsightContextLoader` 读取同一主观 Store；数据模式、共享健康快照或访问状态改变时重建卡片。大辅助字号使用纵向头部和整宽正文，卡片保持可滚动且不截断。
- 本步不新增 SwiftData Schema、洞察持久化、通知、计划自动创建或网络请求；详细数据依据/来源、已读/忽略和正式医学文案审阅分别留给 S09-06、S09-07 和 S09-08。

#### 洞察数据依据与来源（S09-06）

- `InsightEvidencePresentation` 是 S09-05 展示模型的只读组成，由 `InsightFourLayerCardFactory` 直接从同一个 `InsightFactSet` 生成。它不访问 HealthKit、不保存原始样本、不重复运行趋势引擎，也不改变四层结论。
- 有主要变化时只带该事实；严格主客观不一致时带四项核心事实；稳定集或质量不足时按 `HealthMetricType.allCases` 的规范顺序带当前结论使用的全部事实，保证结论与展开依据一一对应。
- 每个依据项显示当前/基线半开窗口对应的本地日期、有效日/期望日、中位数、相对变化、实际门槛、同向日/分析日/最低要求、来源名称、质量说明、趋势规则版本和事实生成版本。日期通过事实时区按完整本地日格式化，兼容 DST。
- 来源从既有 `HealthMetricSource.displayName` 去重排序，只输出 `Apple Watch`、`iPhone` 或既有可读来源名；bundle identifier、设备序列、样本 UUID、主观记录引用和自由文本不进入展示模型。
- `DisclosureGroup` 默认收起，普通字号下可展开并随洞悉页滚动。不可用事实只显示分析范围、精确降级原因和事实生成版本，不伪造中位数、变化、来源或 0。
- 本步不新增 Schema、网络、AI 或 CareKit 调用；已读/忽略/不再提醒及医学文案审阅仍分别属于 S09-07、S09-08。

#### 洞察状态与用户控制（S09-07）

- `InsightInteractionIdentity` 由四层卡工厂基于展示版本、事实生成版本、模式、时区、分析窗口、实际依据事实、可选问题及结构化背景更新时间生成 SHA-256 截取的 RFC 9562 version 8 UUID。相同聚合卡身份稳定；窗口、模式、主题、依据或背景发生变化时形成新身份。
- `InsightInteractionsSchemaV1` 独立于 `SubjectiveRecordsSchemaV1`，由 `InsightInteractionsMigrationPlan` 显式管理。`InsightInteractionEntity` 仅保存模式、散列洞察 ID、主题键、已读/忽略时间；`InsightReminderPreferenceEntity` 仅保存模式、主题键和关闭时间，不复制洞察正文、原始健康数据、自由文本或底层记录 ID。
- 当前洞察的已读与忽略互相独立且都可撤销；清除最后一个当前状态后删除空实体。忽略只替换为可恢复的紧凑卡，不改变健康事实或四层结论。同类提醒偏好按主题跨未来洞察窗口生效、真实/演示隔离，恢复时删除偏好实体。
- `InsightInteractionSession` 在卡片身份变化时同步读取状态。读取失败继续展示卡片、禁用控制并提供重试；写入失败回滚 Store、重建上下文并保留 UI 原状态，不做乐观成功。损坏或跨模式记录被拒绝，不能被当作有效偏好。
- `RootTabView` 向真实与演示洞悉页注入同一 Store，隔离由持久化键保证。本步只保存用户偏好，不访问 HealthKit、CareKit、AI 或通知 API；S13 低频提醒调度后续消费主题偏好，洞悉页始终仍可查看内容。

#### 洞察低焦虑文案回归（S09-08）

- `docs/insight-low-anxiety-copy-checklist.md` 是 S09 固定文案的版本化审阅基线，按事实、可能解释、不确定性、建议、追问、依据/质量和用户控制七类职责检查，并列出 COPY-01～COPY-18 固定场景。
- `InsightTests` 从 `InsightFourLayerCardFactory` 的真实输出组合用户可见文本，覆盖变化、同期事件、稳定、严格主客观不一致、读取失败、全部不可用原因、来源/孤立日期和演示模式；测试禁止诊断、恐吓、确定因果、效果保证与强制服从断言。
- 数值层只表达相对个人基线的上升/下降和三档趋势，不映射健康好坏。追问只用“是否”补充背景并使用“身体感受”；离群证据只写“孤立日期保护”，避免把统计保护误读为身体异常。
- 自动字符串检查只拦截完整危险断言；“不能用于诊断”等明确否定句由语境审阅保留，避免简单禁词表误伤安全边界。任何固定文案、洞察主题或通知语义变化都必须重跑清单和完整测试。
- 本步不改变趋势、数据质量、存储、AI、CareKit 或通知调度。工程与产品审阅不冒充医学专业意见，正式发布前医学专业人士审阅仍是独立门禁。

#### 洞察到计划候选的确定规则（S10-05）

- `InsightPlanCandidateRule` 只消费 S09 的 `InsightFactSet` 与重新校验后的 `InsightContextMatchState`，不访问 HealthKit、SwiftData、CareKit、网络或 AI。决策显式区分候选与非候选原因，规则版本固定为 `s10-insight-plan-candidate-v1`。
- 规则先复用 S09-04 的背景完整性守门，再从有效日、稳定单一来源、未触发孤立日期保护且达到集中门槛的变化事实中选择；持续变化优先于值得继续观察，同档按变化相对门槛幅度和固定指标顺序排序，因此相同输入始终只产生同一个最高优先候选。
- 模板映射只引用既有 `MicroPlanTemplateID` 白名单。睡眠、活动与恢复方向结合结构化签到和事件生成咖啡截止、提前上床、午后步行、工作间歇活动、轻柔活动、降低运动负荷或睡前呼吸候选；不把事件写成因果，也不从备注或自定义名称推断。
- 生病、未佩戴设备、演示模式、背景读取失败、背景未补全、质量降级或没有白名单匹配时返回无候选。`InsightPlanCandidate` 只携带模板 ID、聚合事实 ID 与规则版本；四层卡只显示“可以考虑”的五天候选并说明需用户确认，不创建 CareKit 草稿、任务或 Outcome。

#### 本地持久化职责

保存 CareKit 不承担的用户与分析数据：

- `DailyCheckIn`。
- `ContextEvent`。
- `InsightRecord`。
- `PlanAnalysisMetadata`。
- `EffectiveMethod`。
- 可选的 AI 对话元数据。

S08-01 为每日签到和生活事件建立独立的 `ZhihengSubjectiveRecords` 本地配置。当前 `SubjectiveRecordsSchemaV1` 同时登记 `DailyCheckInEntity` 与 `ContextEventEntity`，并由 `SubjectiveRecordsMigrationPlan` 显式声明版本顺序；首版没有旧结构可迁移，因此阶段列表为空。以后修改字段时必须保留既有 Schema 类型，新增下一个版本，并在迁移计划中按相邻版本添加轻量或自定义阶段，不能直接改写 V1 后继续使用同一版本号。

`DailyCheckIn` 保存稳定 ID、本地公历年月日、记录时区、精力/压力/身体感受 1～5、可选短备注及创建/更新时间；本地日期键保证同一公历日最多一条签到，更新不会产生重复记录。`ContextEvent` 独立保存稳定 ID、事件类型、自定义标签、可选起止时间/强度/短备注及创建/更新时间。两者只在设备本地保存，不包含 HealthKit 原始样本，也不重复 CareKit 计划完成状态；自由文本禁止进入技术日志。

S08-02 建立 `SubjectiveCheckInSession` 连接 `SubjectiveRecordStore`；S08-03 收缩选择状态的观察范围。S08-09 进一步由 Root 持有 `DailyCheckInCoordinator`，协调器拥有唯一签到会话但不转发其每次选择通知；只有弹窗和独立摘要卡观察感受状态，避免每次选择让整个健康仪表重算。Root 在启动、切换数据模式和进入前台时调用同一每日门禁，不依赖 HealthKit 查询完成，也不依赖当前标签或今日页所选历史日期。

标题统一为“今日感受”，删除三项各选一个提示；S14-11 起，进入 App、切换模式和跨日只加载当天状态，不再自动打开 sheet。用户只从今日状态卡主动打开记录或修改窗口，同日未保存草稿继续保留。旧的 `dailyFeeling.lastPresentedDay` 偏好仅作兼容读取，不再触发界面。今日页当天的仪表盘下方使用独立“今日状态”板块展示感受摘要/手动入口及今日变化卡，身体区不再包含今日变化。

精力、压力和身体感受全部选择且当天记录成功读取后才允许保存；同日再次保存更新既有记录，成功后关闭弹窗并同步摘要。读取失败时不自动弹出、不允许覆盖未知旧记录，手动重开可重试；保存失败保留草稿、窗口不关闭。跨日进入或跨午夜保存会重载新的本地日期并清除旧日草稿，不自动把昨天的感受写入今天。演示模式关闭弹窗并清空会话可见状态，明确禁用真实感受读写；切回真实模式再按当日门禁处理。没有新的数据副本、远程上传或 CareKit 任务状态。

感受选项使用 10 点圆角矩形，最小触控高度 46 点、标准字号最小宽度 56 点、辅助字号最小宽度 80 点；可按内容扩展和横向滚动，选中时有边框及辅助功能 selected 特征。记录/修改、保存和暂不填写操作均使用 14 点圆角矩形。弹窗内容可滚动，操作固定在底部安全区，大辅助字号改为大尺寸 sheet。工程基准与真实用户耗时分别记录在 `docs/check-in-usability-validation.md`，旧内联版计时不作为新弹窗版验收，不在正式产品采集签到耗时或感受选值日志。

S08-05 在 `SubjectiveCheckInSession` 中持有可编辑备注，加载恢复保存值、写入失败保留草稿，成功后同步归一值；读取失败、跨日和演示模式清理可见文本。会话保存时也检查所加载的本地日期，防止绕过协调器将旧草稿写入新日。`OptionalRecordNoteField` 为今日感受和生活事件共用的默认收起输入组件，展开今日感受备注时选择大尺寸 sheet；显示已填写状态、字数、长度错误和键盘完成操作。领域与会话共用 `SubjectiveRecordText.normalized`，按 Swift `String.count` 统计去除两端空白后的扩展字素，空白转 nil；名称上限 30、备注上限 160，超限拒绝保存而不截断草稿。沿用 Schema V1 现有字段，不改变存储结构、不新增迁移步骤或 AI 上传。

`PlanAnalysisMetadata` 只通过 `carePlanID` 关联计划，不重复保存每日完成状态。当前 S10-08 已实现其中的版本化 `baselineSnapshot`：只包含计划开始日期、捕获时间、真实或演示数据模式、任务相关指标在计划前五天的中位数与有效天数，以及 Schema 版本；原始 HealthKit 样本不进入 SwiftData。

计划启动采用“先冻结分析基线，再创建 CareKit 计划”的顺序。SwiftData 保存失败时计划不启动；CareKit 创建失败时删除刚保存的孤立基线。页面恢复状态时按 `carePlanID` 读取快照，客观计划评估只接受计划 ID、开始日和数据模式一致的冻结基线。旧计划缺少快照时仍可展示动态趋势，但不能把后来重算出的计划前数据作为可靠历史评估事实，需明确降级为基线未保存、数据不足。

#### 生活事件（S08-04 / S08-05）

`ContextEventKind.defaultKinds` 固定 11 类默认标签，保留已有原始枚举值；S08-05 的展示目录为默认目录追加 `.custom`，不改变 defaultKinds 的职责。`ContextEventSession` 调用既有 `SubjectiveRecordStore`，由每日协调器共享持有但不转发每次选择通知；只有生活事件摘要/弹窗观察会话。进入前台和切换模式更新本地日界限，同日不重复读取或重置草稿；手动打开可重试读取。窗口由用户主动打开，不增加每日感受弹窗步骤。

每次选一类并明确保存，生成稳定事件 ID，以当前时间记录正在发生的事件；成功后清除选择和文本、更新当日列表，避免连点重复，用户重新选择可以记录另一次事件。S08-05 由会话持有自定义名称及备注草稿，自定义名称必须非空；选择默认类型时不保存隐藏的自定义名称，但同一未提交草稿切换类型不会丢失文字。失败重试沿用待保存事件的 ID、开始及创建时间，每次用最新草稿重建事件，避免保存编辑前的旧文字。起止时间调整仍待后续接入，不推断事件持续时长。当天列表使用当前时区公历日的半开窗口查询，包括重叠事件，夏令时日不假定为固定 24 小时；跨日/时区变化先清理旧草稿、重新读取，不把昨天选择或文字写入今天，也不从旧界面删除昨日记录。

只允许删除列表中的单个 ID，用户需二次确认，成功后才更新列表。事件写入/删除失败时 SwiftData 适配器先回滚，再用同一 ModelContainer 重建关闭自动保存的上下文，避免失败插入残留在注册实例缓存中并被后续读取或其他保存带出；只读磁盘失败插入/删除测试已验证恢复后的读取仅含成功保存的记录。演示模式关闭生活事件窗口、清除可见状态，不读写真实数据。沿用 Schema V1，无新持久化副本，不写 CareKit，也不进入 AI 事实包。S08-10 将可选入口移到今日状态双卡下方的紧凑独立行，保留记录数量、读取失败提示和原 sheet；标签为圆角矩形，标准字号两列、辅助字号一列，底部操作区固定可见。

#### 主观记录历史（S08-06）

`DailyCheckInCoordinator` 共享同一个 `SubjectiveRecordStore` 给 `SubjectiveHistorySession`，不新增 Store 实例或 Schema。历史入口仅在真实模式的“今日状态”标题旁展示。历史会话按选择日期一次性读取签到和该日半开窗口的重叠事件；任一读取失败不展示部分结果或上一次日期的数据，禁止修改并提供重试。签到按原公历日期键查询；事件按当次浏览固定时区计算日界限，夏令时不假定固定 24 小时。日期选择不允许未来日期；无记录日只读，不新增补填。

`SubjectiveHistoryDraft` 只暴露评分、类型、自定义名称和备注，重建领域记录时保留原 ID、本地日期/时区、创建时间和事件起止时间/强度；内容校验复用现有领域构造与文本规则。保存、确认删除前在主线程同一同步操作中重新读取并比较原始快照；不一致时要求重读，防止旧编辑覆盖新内容或复活已删除记录。写入失败不修改页面快照，编辑草稿留在编辑器中，成功后才更新列表并关闭编辑器。日期切换清理旧编辑与待确认删除；删除由会话锁定单条候选，确认弹窗的显示状态与候选分离，避免系统关闭弹窗先清空删除目标。

签到与事件的写入/删除统一使用 `resetContextAfterWriteFailure` 回滚并重建同库上下文，清理失败插入或更新的注册实例缓存；不回滚或重建独立的第二份健康/任务数据。磁盘只读测试覆盖签到插入、更新、删除和事件更新失败后仍读到原记录。

历史操作成功后通知每日协调器：只有涉及今天的签到才重新加载感受摘要；历史事件变化刷新当天事件列表但保留未提交的感受草稿。浏览历史跨午夜时只更新日期状态，不自动展示 sheet。切换演示模式关闭历史/编辑窗口、清空可见记录并阻止读写；不改动 HealthKit、CareKit 或 AI 事实包。S14-11 将历史入口改为 44 点无描边 Liquid Glass 纯图标圆形按钮，iOS 18～25 降级为无描边 `ultraThinMaterial`，仍保留完整辅助功能名称。

#### 同日时间线（S08-07）

`HealthContextTimeline` 为只读纯模型，生成固定浏览时区、公历日历的连续 7 个半开日窗口，使用 Calendar 加日以适配 23/25 小时的夏令时日。`SubjectiveHistorySession.loadTimeline` 使用同一 Store 读取 7 个本地日期键签到和整个窗口的一次事件查询，全部成功后发布瞬时展示结果；任何失败清空旧结果并提示，不把部分读取包装成无记录。跨日事件复用 Store 的重叠语义（开始小于日末、结束或点事件时间大于等于日初），按时间及 ID 稳定排序。签到保持原记录日期/时区，不按时间戳重新归日；旅行时提示原时区差异。

`HealthDataSession.snapshotInterval` 记录实际共享快照的查询窗口，健康不可用时与快照一起清空；页面不直接访问 HealthKit。`HealthContextTimeline.metricState` 按样本结束日筛选本次范围内四类核心指标，复用 `HealthMetricDailySeriesCalculator` 及 `PreferredHealthMetricSourceSelector` 的来源优先、合计/最后值规则；范围之外及读取起点不覆盖完整日初时不显示每日总量。无记录、来源冲突、查询失败、未申请、不可用和尚未读取分别返回明确状态；真实零值保留，来源逐日显示，缺失不按零处理，不计算趋势或因果。

`HealthContextTimelineView` 位于历史导航内，观察同一个健康会话与历史会话；首次进入/截至日期改变重新读取本地主观记录，显式刷新同时刷新共享健康快照，原始历史编辑页保留不变。界面双重检查真实模式与历史启用状态，演示时不显示真实记录；会话切换演示清空时间线状态并阻止 Store 读取。不新增 Schema、原始样本持久化、CareKit 状态副本、AI 事实包字段或网络上传。

#### 感受与数据对照（S08-08）

`StateComparisonEngine` 为纯 Swift 确定性只读计算，输入共享快照/查询窗口、访问状态、数据模式、已保存签到/读取状态、当前时间和时区；无记录、读取失败、日期/时区不匹配或演示模式直接降级。`SubjectiveFeelingState` 按 `StateComparisonRules` 的版本化 2/4 边界分类，任一低精力/低身体或高压力保留需照顾状态，三个评分不求平均，一般/混合独立展示。此为产品展示分组，不是医学阈值。

客观计算以当地昨日为参考，7 个完整日和此前 28 天互不重叠，排除今日尚未结束的合计。查询窗口需覆盖完整 35 天；复用 `HealthMetricTrendEvidenceBuilder` 的集中阈值、有效日、稳健统计、孤立日期保护和同向日。为本次跨指标合并额外检查四类核心指标昨日有数据、逐日所选 `HealthMetricSource` 完整身份一致且无同日来源冲突；不修改原趋势引擎，不让同 bundle 换设备或被聚合跳过的冲突日形成整体结论。任何不足、失败、源变、孤立保护或 worthObserving 均不进入四类结果，可用部分仍列入依据。

`StateComparisonResult` 保存临时展示结果与逐项证据，没有 SwiftData/CareKit 副本或 AI 上传。四类组合只把相对基线变化与今日感受并列，任何方向变化都不认定好坏。`StateComparisonCard` 独立观察健康会话与感受会话，只有共享健康输入、已保存签到/读取状态和日期变化时重算，未提交评分/备注不触发健康计算。60 秒 TimelineView 只更新跨日保护、不发查询；切换演示关闭详情。详情展示双时间范围、有效日、来源和规则版本，提示今日感受与近期趋势不是同一时间尺度。

S14-11 保留 `StateComparisonEngine`、模型和测试作为既有确定性能力，但 Today 不再构造或展示 `StateComparisonCard`；该能力不会形成新的隐式入口或后台查询。

### AI 服务

AI 服务不作为健康数据事实来源。请求内容是本地生成的聚合 `HealthFactPack`；响应是需要校验的结构化建议。

## 6. HealthKit 数据流

```text
用户授权
  → HealthKit 查询
  → 单位/来源/时区标准化
  → 累计指标来源选择与防重复
  → 去重和聚合
  → 数据质量判断
  → 个人基线与趋势
  → 页面、洞察与事实包
```

要求：

- 查询范围和数据类型最小化。
- 授权状态变化可以刷新。
- 数据查询异步、可取消，错误转换为领域错误。
- 页面只消费加载、成功、空、部分授权和失败等明确状态。
- 后台更新属于 P1，P0 先保证启动和手动刷新正确。

### 今日与洞察页面职责

- `RootTabView` 持有当前真实/演示模式各自唯一的 `HealthDataSession`。会话保存授权状态、数据模式、加载状态和最近一次 90 天共享快照；前台进入门禁保证同一 App 进入周期只自动加载一次，进入后台后才重置门禁。
- 今日页和洞察页通过 `@ObservedObject` 消费同一个会话，不再在各自 `.task` 中查询 HealthKit。页面下拉、今日页刷新按钮和授权完成调用会话的显式 `refresh()`；标签切换只重绘展示模型。
- 今日页通过 `TodayDashboardPresentationFactory` 把健康快照、所选日期和本机目标转换成一次性展示模型；SwiftUI 卡片不得直接读取 HealthKit。
- 今日页展示连续 7 日选择、五项目标完成度、当日身体/日常数据和昨晚生命体征；S08-09 将“今日变化”与“今日感受”合并到当天仪表盘下的独立“今日状态”板块，身体区仅保留 HRV 和训练准备两卡。S08-10 / S08-11 按参考图采用标准字号并排、超过 `.large` 纵排的自适应双卡：黄橙粉渐变太阳、蓝青渐变双星、感受三条摘要、大号数值与百分比、淡黄色建议框及详情入口；用语义背景和动态颜色支持深色模式。`TodayStateCardsLayout` 按可用宽度计算等宽双卡，目标比例为 484:568；高度取目标值与真实内容测量值的较大者，移除 236 点固定下限，长文案不截断。字号通过 `ScaledMetric` 缩放，修改入口视觉紧凑但触控区保留 44 点。`DailyFeelingField.tone(for:)` 将用户评分映射到五档视觉程度，压力方向反转，非中间档有同色浅底和边框，两端透明度更高；未记录不生成程度色，颜色不替代文字标签。太阳/双星由 SwiftUI Canvas、闪电由 Shape 绘制，渐变圆底比例约占卡宽 19%，不依赖位图或新增包。`TodayImportantChange.currentMedian` 直接取 `trend.magnitude.currentValue`，与 `relativeDifference` 同源，不用最新单日值替代 7 天中位数，不解析文案反取数据，也不改变趋势门槛。`metricTitle` 和既有单位映射负责数值说明；无候选只展示中性观察，不伪造数据或详情链接。完整比较事实保留在卡片辅助功能标签及指标详情中。Debug 专用 `--today-state-preview` 只定位到该板块以便检查，不注入数据，Release 不包含自动定位行为。
- 7 日窗口分页时按手势方向为整组日期使用 0.34 秒滑入、滑出与淡化组合动画；选择日期和整组分页仍由同一展示模型驱动。
- 日期活动圆环和日常活动卡使用活动能量、运动分钟、站立小时三个独立比例；步数和活动能量的 24 小时柱状图使用与全天汇总一致的来源选择规则，并以显式 `yStart = 0` 保持柱底对齐。
- 活动圆环由 `Infrastructure/HealthKit/SystemActivityRingView` 隔离封装苹果 `HKActivityRingView`；Feature 页面只传入领域层归一化进度，不直接依赖 HealthKitUI 类型。日常卡使用固定外框和略小的原生视图，避免 HealthKitUI 内部留白或外圈被裁切。
- 睡眠阶段时间轴由 SwiftUI 自定义绘制，保留 HealthKit awake/core/deep/REM 区间；不显示左侧阶段标签，连续区间的竖向转换采用低透明度双颜色渐变。生命体征状态只表达查询是否获得有效记录，不执行医学正常范围判定。
- 标准字号的日常模块使用两列等宽网格并通过 1:1 比例固定为正方形，辅助功能字号切为单列；身体两张卡的顶部图标统一使用 46×46 点布局区域，使标题与说明从同一纵向基线开始。生命体征卡统一固定为 136×136 点且不使用投影；不同 SF Symbol 统一放入 24×24 点布局区域，名称使用固定 20 点高度的常规 `subheadline`。数值行把 32 点圆角粗体数字与小号单位拆分，避免长单位触发整行缩小；状态行只保留 2 点顶部间距并移除数值前的弹性占位，使数值和状态整体上移。横向生命体征视口抵消页面左右内边距，内容首尾再补同值间距，使初始卡片与标题对齐且滚动时可到达屏幕边界。
- 日常模块除卡片自身的 1:1 约束外，在 `LazyVGrid` 单元外层再次强制 1:1，避免 `NavigationLink` 或内容固有高度使睡眠和活动卡尺寸偏离。目标仪表外环保持既定方向，刻度遮罩独立顺时针旋转 90°；刻度先绘制完整灰色轨道，再按完成比例以相同渐变遮罩覆盖，百分比下方固定显示 `Perfect Day`。
- 睡眠样本在领域层保留 `HealthSleepStage`。深睡、核心、REM 和清醒按 HealthKit 原始分类展示；清醒样本值为 0，仅保留真实起止时间，避免计入睡眠总时长。
- 睡眠汇总、日序列和昨夜区间统一使用 Apple Watch、iPhone、其他来源的稳定优先级；未知类别存在多个来源时继续拒绝猜测。血氧从 HealthKit 的 0～1 `percent` 单位乘以 100 转换成页面百分比。
- HRV 状态只比较此前 28 天个人基线且至少需要 14 个有效日，页面用“状态偏低/状态正常/状态较好”表达相对位置；训练准备至少需要 4 个可用组件，并保留实际使用组件数和建议说明供辅助功能读取。
- `TodayImportantChangeSelector` 仅比较睡眠时长、HRV、静息心率、步数、活动能量和锻炼时长。候选必须同时具备最近 7 天至少 4 个有效日、与近期窗口不重叠的此前 28 天至少 14 个有效日、稳定数据来源、超过按指标配置与 2.5×MAD 取较大值的相对变化，以及至少半数且不少于 3 个有效日同向；再按“变化幅度÷有效门槛”排序，固定优先级打破平局并最多返回一项。SwiftUI 只显示“发生了什么”和低风险建议；内部门槛不因界面简化而取消，未达标时显示继续观察状态。
- 五项目标和模块显示/顺序通过 `AppStorage` 持久化；缺失或损坏配置回退到领域层默认值。
- 单项详情页展示当前汇总、来源、更新时间、7/90 天覆盖、最近 7 天每日记录，以及由同一聚合规则生成的 7/28 天 Swift Charts 趋势卡。折线与面积使用同一插值，缺失日不补零；今日页与洞悉页复用同一个详情实现。
- 洞察页通过 `InsightsDashboardPresentationFactory` 从健康快照生成一次性展示模型，SwiftUI 不直接读取 HealthKit。展示模型包含 HRV 最新值、此前 28 天基线状态、参考区间、7 日图点、参考日 00～24 时的 `InsightsHRVIntradayChartPresentation`，以及十类身体指标的当前值、前一有效日差值和迷你趋势。日内图只保留参考日内且不晚于参考时刻的真实样本，按时间排序；缺失不插值、不补点。
- HRV 仪表归一化位置只用于绘制相对个人参考区间，不作为健康评分；少于 14 个此前有效日时返回学习状态。睡眠时心率在领域层先用睡眠区间裁剪心率样本，再按日聚合。
- `HRVVisualState` 把无数据、学习中、低于、接近和高于个人参考统一映射为两个页面共用的 `HRVStatusFace`；表情以 SwiftUI `Canvas` 本地绘制，不依赖图片资源。颜色、眉眼和嘴形同时变化，并提供状态辅助功能标签。
- `InsightsHRVPresentation.explanation` 为无数据、学习中、偏低、接近和较好五种确定状态生成互不重复的自然评价；它只解释此刻 HRV 相对个人节奏的展示状态并提醒结合本人感受，不承担诊断、压力测量或整体健康判断。
- 洞察仪表用同一个几何容器放置仪表和左右操作按钮，不使用负间距悬浮；最新数值留在仪表底部，状态、记录时间和解释在仪表外按顺序布局。
- 洞悉顶部云朵由 `InsightsCloudLowerArcGeometry` 在 U 形基础轮廓上绘制七段大小递变的二次曲线：外侧形成大云团，中部形成连续小云瓣；填充区域跟随整个 HRV Hero。刻度使用 31 条共享圆心、内外半径和等角步长的径向 `Path`，不再用逐个 Capsule 的位置与旋转组合。
- 主 HRV 图使用 Swift Charts：横轴固定为参考日 00～24 时，显示 00/06/12/18 时刻；参考带覆盖完整日区间，点和折线来自 `InsightsHRVIntradayChartPresentation`，点色只表达其相对个人参考区间的位置。7/28 天跨日趋势继续由详情页承担。
- 仅 Debug 构建支持 `--insights-section=top|chart|body|expanded` 定位洞悉页视觉验收区域；普通启动和正式构建固定从今日页开始，不受调试参数影响。
- `InsightsMetricReferenceState` 保留相对方向，超过个人参考阈值时分别输出偏低或偏高；“状态正常”只表示接近个人参考范围。
- 洞察页继续集中承载 7/28 天趋势、个人基线、变化解释和后续 AI 辅助分析；身体指标显示与顺序使用本机 `AppStorage` 保存，详情仍复用单指标详情展示模型。
- HealthKit 连接状态和权限入口集中在今日页右上角齿轮打开的设置中，今日内容区不重复展示；设置继续消费 Root 的同一共享会话，不建立第二份状态。

## 7. 数据质量与趋势引擎

推荐接口：

```text
DataQualityEngine.evaluate(samples, interval) -> DataQualityReport
BaselineEngine.calculate(samples, config) -> MetricBaseline
TrendEngine.detect(baseline, current, quality, config) -> MetricTrend
```

配置集中保存：

- 基线窗口。
- 当前窗口。
- 最小有效日。
- 最小变化阈值。
- 异常值处理参数。
- 趋势一致性门槛。

算法模块必须是纯 Swift、无网络、无 UI、无系统权限依赖。测试使用脱敏固定数据或合成 Fixture。

### 28 天个人基线

- 基线窗口是截至参考时刻的最近 28 个日历日，不用更早数据补齐缺失日。
- 先按指标现有日聚合规则生成每日值；缺失日保持缺失，不能按 0 处理。
- 至少 14 个有效日才返回可用基线，否则返回有效日、最低要求和窗口天数构成的明确数据不足结果。
- 可用结果保留指标、时间范围、28 个预期日、有效日、覆盖率、单位、中位数和中位绝对偏差（MAD）。
- 中位数作为个人典型水平，MAD 作为稳健离散度；AI 与 UI 不得改写这些程序计算结果。

### 最近 7 天当前窗口

- `HealthMetricRecentWindowEngine` 以参考日所在日历日为末日，只取当日及向前 6 个日历日；时间范围保存为“首日 00:00 ～末日次日 00:00”的半开区间，跨时区或夏令时时仍按日历日计算，不固定为 168 小时。
- 先复用指标日聚合与来源优先规则生成真实每日点位；缺失日不补点、不补 0，同日多来源完全平局时使用稳定来源标识打破平局，保证输入顺序不改变结果。
- 至少 4 个有效日时输出指标、时间范围、7 个预期日、4 个最低有效日、实际有效日、单位、每日点位和当前中位数；不足时仍保留时间范围与真实点位，但明确返回数据不足，不生成当前中位结论。
- “今日变化”已复用该窗口的时间边界、有效日和中位数，并把可用窗口交给统一的变化幅度计算器。

### 变化幅度与双窗口覆盖率

- `HealthMetricChangeMagnitudeCalculator` 只比较指标、单位一致，且基线窗口结束不晚于当前窗口开始的两个可用结果；指标或单位不一致、窗口重叠或倒序时明确拒绝比较。
- 结果同时保存基线与当前时间范围、中位值、绝对变化、相对变化，以及两个窗口各自的有效日、预期日和覆盖率，保证 UI、AI 事实包和后续趋势规则能够追溯同一组程序事实。
- 相对变化按“当前中位值减基线中位值，再除以基线中位值”计算；基线恰为 0 时仍保留绝对变化，但明确标记相对变化不可用，不生成无穷大或伪造百分比。
- “今日变化”已复用该计算结果，不再自行重复计算相对变化。S07-03 不负责异常值保护或三档趋势判断；这两项分别留给 S07-04 与 S07-05。

### 单日异常值保护

- `HealthMetricSingleDayOutlierGuard` 对当前窗口每日值使用 Hampel/MAD 思路：以当前中位数为中心，以当前窗口 MAD 与个人基线 MAD 中较大者乘以 `3.5` 作为偏离门槛；参数和版本 `s07-outlier-v1` 集中保存在 `HealthDataQualityThresholds`。
- 只有恰好一个日期超过门槛时才视为孤立单日异常；没有越界日期或多日离散时均不擅自归因为单日异常。输入点先按日期稳定排序，固定输入和重排输入得到相同结果。
- 原始窗口和点位不删除、不改写，仍用于覆盖率与图表追溯；守门器只在分析副本中排除孤立日期，重新计算受保护的当前中位值、绝对变化和相对变化。
- “今日变化”使用受保护结果和分析点位；排除后少于 4 个有效分析日时不输出。若其余日期仍呈持续变化，则允许继续进入既有幅度与一致性门槛，避免一个异常日期反向遮蔽真实的多日变化。
- S07-04 只提供异常值守门与受保护变化，不输出“未见明确变化／值得继续观察／存在持续变化”；三档结果留给 S07-05。

### 三档趋势结果

- `HealthMetricTrendDetector` 接收可用基线、可用当前窗口、来源是否稳定和领域阈值目录提供的最小相对变化配置；测试仍可显式注入合成配置，正式调用方不得在页面中散落阈值。
- 判定顺序严格遵守数据质量优先：来源不稳定、孤立异常排除后少于 4 个分析日，或零基线无法安全计算相对变化时，结果为“值得继续观察”，不得形成持续变化。
- 有效相对门槛取调用方最小相对变化与 `2.5 × 基线 MAD ÷ |基线中位值|` 中较大者。受保护相对变化未达到门槛时输出“未见明确变化”；达到门槛但同向日不足时输出“值得继续观察”；达到门槛且同向日不少于 3 天、同时不少于分析日的一半时输出“存在持续变化”。
- 结果保留受保护的变化幅度、原始双窗口范围/覆盖率、分析点、被排除的孤立点、来源稳定状态、固定与稳健门槛、同向日与所需同向日，以及趋势和异常值两套阈值版本。`higher/lower` 只记录算术方向，不等同于健康变好或变差。
- `TodayImportantChangeSelector` 只消费“存在持续变化”的结果，使用统一的受保护幅度和有效门槛排序，不再重复实现幅度与一致性判断。

### 指标阈值目录

- `HealthMetricTrendThresholdCatalog` 是最小相对变化阈值的唯一领域事实来源，版本为 `s07-metric-thresholds-v1`。四类核心指标固定为睡眠时长、HRV、静息心率和步数，当前默认门槛分别为 8%、15%、8% 和 15%。
- 为保持 S06-30 已验收的今日变化候选不退化，同一目录还保存活动能量 18% 和锻炼时长 25% 两个扩展门槛；`coreMetrics` 与 `todayCandidateMetrics` 分开声明，不能把扩展项误写成 S07 核心四类。
- 目录返回指标、最小相对变化和版本，并可直接转换为 `HealthMetricTrendConfiguration`；趋势结果因而保留实际使用的指标阈值版本。未配置指标返回 `nil`，调用方不得猜测或采用静默通用值。
- `TodayImportantChangeSelector` 只保留指标优先级，不再保存任何阈值数值。当前数值沿用此前已验收的产品默认值，本轮未做医学或真实用户数据校准；后续调整必须新增 Fixture、对比前后结果并记录版本和原因。

### 趋势场景 Fixture

- `HealthBaselineTests` 使用完全合成且固定的每日样本，让睡眠时长、HRV、静息心率和步数四类核心指标逐一经过 28 天基线、7 天当前窗口、变化幅度、单日异常保护和三档趋势判定，不依赖 HealthKit、网络或 UI。
- 四类指标共同覆盖稳定、持续上升、持续下降、当前窗口仅 3/7 有效日、基线仅 13/28 有效日，以及当前窗口 4/7 非连续有效日；缺失日期始终保持缺失，不补成 0。
- 合成变化只验证算术方向、数据门槛和确定性分类，不代表医学界限、真实用户健康结论或因果关系。阈值调整时必须同步更新对应 Fixture、版本和影响记录。

### 趋势依据 UI

- `HealthMetricTrendEvidenceBuilder` 是指标详情的可追溯证据适配层，只组合现有 7 天窗口、此前不重叠的 28 天基线、来源稳定判断和三档趋势结果，不另建第二套算法或阈值。
- 证据模型保留双窗口时间范围与有效日、受保护后的当前中位数、基线中位数、相对变化、配置/实际门槛、同向日、分析日、孤立日期保护、来源状态和阈值版本。当前窗口不足、基线不足、来源变化和三档结果使用互斥状态，UI 不从缺失字段猜结论。
- 支持趋势阈值的指标详情在趋势图下方显示“趋势依据”卡；未配置指标不显示该卡，也不采用静默通用阈值。“今日变化”卡仍只显示事实与建议，完整证据通过其指标详情入口查看。

## 8. CareKit 计划设计

### 模板到 CareKit 的转换

`MicroPlanTemplate` 是知衡定义的低风险计划模板，包含标题、目标、默认天数、日程和观察指标。开始计划时转换为 CareKit 实体。

```text
MicroPlanTemplate
  → OCKCarePlan
  → 一个或多个 OCKTask
  → OCKSchedule
```

每日执行写入 `OCKOutcome`。当前界面记录完成或跳过，并允许在同一个 Outcome 中附带最多 160 字的可选感受；不提供困难度选择。保存后的反馈只读展示并标记为隐私内容，自由文本不得进入技术日志。

### 计划评估

```text
CareKit Outcomes（完成、跳过、可选反馈）/ 当前进度
            +
HealthKit 计划前后指标
            +
SwiftData 每日主观记录和生活事件（接入后）
            ↓
MethodEvaluationEngine
            ↓
PlanEvaluation + EffectiveMethod
```

评估结果存储计算输入摘要、结果和版本，不能覆盖 CareKit 原始执行历史。

S11-01 的 `EffectiveMethodCandidateGenerator` 直接通过 `CarePlanService` 读取 `planHistory()` 与各 Task 的 `outcomeRecords(for:)`，生成不落库的只读 `EffectiveMethodCandidate`。生成器只接纳 `.completed` 与 `.endedEarly` 且能映射到当前低风险模板库的计划，按 `carePlanID` 去重、按模板 ID 归并多次执行，并保留每次 `MicroPlan` 与 `PlanOutcomeRecord` 作为后续完成率和可信度计算的可追溯来源。候选使用模板 ID 构造稳定身份，计划、Outcome 与候选顺序均确定；任一合格 Task 的 Outcome 读取失败时整体抛错，不返回部分历史。该投影不实现 `Codable`、不写 SwiftData，也不改变 CareKit 数据；已结束但 Outcome 为空的执行仍保留，交由后续阶段表达证据不足。

S11-02 在每个 `EffectiveMethodCandidateRun` 上附加只读 `EffectiveMethodCompletionFact`。生成器对每个合格计划同时读取 `outcomeRecords(for:)` 与 `progress(for:)`：进度查询提供实际可执行总数及完成、跳过、未记录计数，Outcomes 负责核对 occurrence 唯一、范围有效且状态计数一致。零日程的完成率为 `nil`；重复、越界、计数冲突或任一读取失败均整体抛错，不返回部分候选。候选级事实将各次计数求和，以总完成数除以总应执行数形成加权汇总，避免短计划与长计划被简单平均为相同权重。该事实随 CareKit 历史即时生成，不新增 SwiftData Schema，也不改变原始 Outcomes。

S11-03 的 `EffectiveMethodConfidenceRule` 是版本为 `s11-method-confidence-v1` 的纯 Swift 函数。调用方用稳定 `carePlanID` 把每次候选执行关联到既有本地 `MicroPlanEvaluationVerdict` 和结构化数据质量；规则先验证评估一一对应、无重复且不含候选外来源，再逐次检查完成率至少达到 `MicroPlanEvaluationFactory.minimumCompletionRate`（60%）且数据质量可判断。一条可判断结果固定为 `preliminaryObservation`；两条全部为 `mayHaveHelped` 时为 `possiblySuitable`；至少三条全部为 `mayHaveHelped` 时为 `fairlyStable`。零日程、低完成率、质量降级、`insufficientExecution`、`insufficientData`、`subjectiveObjectiveMismatch`、无一致支持或混合结果均为 `unclear`，并保留结构化原因、总执行数、可判断数、支持数和规则版本。该规则不解析反馈文字、不调用 AI、不持久化可信度，也不改写来源事实。

S11-04 由 `MicroPlanSession.refreshEffectiveMethods` 负责把运行时 CareKit 候选与每次本地计划评估组装为 `EffectiveMethodCardPresentation`。每次执行重新读取按 `carePlanID` 关联的冻结基线、当前聚合健康快照和计划半开区间内的结构化生活背景；`EffectiveMethodCardPresentationFactory` 汇总真实执行次数、S11-02 加权完成率、四级数据质量和 S11-03 可信度。全部执行可判断为 `sufficient`，部分可判断为 `partial`，无可判断对照为 `insufficient`，基线/背景/相关指标读取失败或评估来源错配为 `unavailable`。候选源读取失败进入整页失败状态，不返回部分卡；单次评估资料失败仍保留 CareKit 执行事实并降低数据质量。`ProfileSettingsView` 只消费该领域展示模型，并区分加载、空历史、失败、演示隔离和已加载状态；演示模式在调用 CareKit 前短路。该流程不新增 Schema、不复制 Outcome、不调用 AI，也不展示自由文本反馈。

S11-05 在每个 `EffectiveMethodRunEvaluationFact` 中分别保留客观聚合指标事实和 `EffectiveMethodSubjectiveRunChange`。客观项沿用冻结的计划前中位数、计划期中位数、有效日与确定方向；主观项通过同一个 `SubjectiveRecordStore` 按本地日逐日读取开始日前 5 天和计划半开区间，只将精力、压力、身体感受映射为 1～5 分中位数。两侧均至少 2 个签到日才形成主观对照；零记录为 `notRecorded`，单侧不足为 `insufficient`，存储读取或日期结构异常为 `unavailable`。`EffectiveMethodCardPresentationFactory` 先验证每次评估与候选 `carePlanID` 一一对应，再分别计算两类可用性；多次执行时选择最近一次完整对照展示具体变化，同时显示可对照次数，不跨不同计划基线平均数值。客观读取失败不抹掉主观事实，主观读取失败也不抹掉客观事实；卡片固定声明两类同期变化不代表因果。该投影不新增持久化、不读取备注或 Outcome 反馈、不发送 AI，也不改变 S11-03 可信度规则。

S11-06 将方法卡中的 `sourcePlanTemplateID` 作为再次验证的唯一模板引用。`ProfileSettingsView` 先根据 `EffectiveMethodRestartAvailability` 展示可开始、检查中、已有活动计划、不可读取或演示隔离状态；只有可开始时才允许打开二次确认，并明确旧历史不变。确认后调用 `MicroPlanSession.restartEffectiveMethod`，再次读取 `CarePlanService.activePlan()` 防止页面状态过期，再复用与 AI 候选开始相同的私有 `createPlan` 链：模板生成新 UUID 草稿、捕获并保存计划前聚合基线、写入 CareKit，写入失败时回滚本次基线，最后刷新会话。每次重启形成独立 `carePlanID` 与 `taskID`，原 Care Plan、Outcomes、评估和基线保持只读；演示模式在 CareKit 读取前短路。成功后根标签切换到“微计划”，此流程不请求 AI、不改变方法可信度或模板定义。

S11-07 新增独立的 `EffectiveMethodVisibilitySchemaV1` 与 `SwiftDataEffectiveMethodVisibilityStore`，每个隐藏偏好只保存一个唯一的 `MicroPlanTemplateID.rawValue` 和隐藏时间，并由显式迁移计划管理版本。`MicroPlanSession` 先完整生成 CareKit 方法卡，再一次性读取隐藏模板集合，将同一只读卡片投影拆为默认列表和“已隐藏的方法”；未知模板或无效时间视为整组偏好损坏，不返回部分集合。隐藏或恢复时先持久化，成功后才更新内存投影，失败保持原列表。演示模式在读取 CareKit 和偏好 Store 前短路。`ProfileSettingsView` 用二次确认触发隐藏，并在折叠管理区恢复；两处均说明历史保留。该链路从不调用 `CarePlanService.deletePlan`，因此 Care Plan、Task、Outcomes、评估和基线的事实关系不变。

S11-08 的 `EffectiveMethodEvidenceFilter` 是纯 Swift、无状态的运行时投影规则，固定提供全部、睡眠、精力、压力和可坚持性五类。睡眠从方法卡最近一次可展示的客观指标中查找方向为 `favorable` 的入睡时间或睡眠时长；精力和压力分别只读取完整主观对照的 `changeFromBefore`，以大于 `0.05` 和小于 `-0.05` 排除浮点噪声；可坚持性复用 `MicroPlanEvaluationFactory.minimumCompletionRate`（60%）检查 S11-02 的 CareKit 加权完成率。缺失、不可读、零日程或中性变化均不匹配，输入顺序保持不变。`ProfileSettingsView` 只对 `effectiveMethodsState.loaded` 中当前未隐藏卡片应用筛选；已隐藏管理区不受影响，空结果可恢复“全部”。筛选选择不落库，不新增 Schema，不修改 CareKit、可信度或隐藏偏好，也不调用 AI。

S11-09 只重组 `ProfileSettingsView` 的方法页面视觉，不改变 `EffectiveMethodCardPresentation`、筛选规则、隐藏偏好或再次验证链路。方法页使用自定义滚动内容而非 Form 默认分组外观：顶栏从运行时已加载及已隐藏投影计算收录数；筛选胶囊只改变本地 `effectiveMethodFilter`。方法卡把现有执行次数、加权完成率和质量级别映射为三列摘要；完成率条只在分母有效时显示真实进度，未知保持文字状态。客观与主观变化仍调用现有格式化和事实模型，在同一浅色内容容器中分区展示；依用户补充要求移除顶部说明卡、质量详情摘要及分区后的重复灰字说明，再次验证与隐藏按钮使用一致的宽度、高度和圆角。保留现有 SF Symbols 图标和 VoiceOver 语义；本次不新增大字体或深色模式专项布局。

当前 `MicroPlanEvaluationFactory` 先基于 CareKit 完成率、Outcome 反馈、任务相关 HealthKit 计划前后趋势、数据质量和同期结构化生活背景生成确定性本地结果。`MicroPlanSession` 复用根视图持有的唯一 `SubjectiveRecordStore`，按计划 `[startDate, endDateExclusive)` 半开区间查询重叠事件，再按 `ContextEventKind.allCases` 固定顺序聚合为类型、次数和最高强度。自由文本、自定义名称、事件 ID 与起止时间不进入评估事实包。完成率低于 60% 时优先输出“执行不足”；计划前或计划期有效日少于 2 天时不计算对应客观变化；背景读取失败时保持计划和 CareKit 事实可见，但评估降级为“数据不足”。读取成功为空、读取失败和演示模式分别为 `notRecorded`、`unavailable`、`demoMode`，不得互相冒充。所有结果只使用批准的非因果措辞，事件仅作为同期背景，不改变完成率或指标方向。结束卡片展示完成率、反馈天数、客观趋势、数据质量和“同期背景”，删除重复的解释性说明。

S10-16 的 `MicroPlanView` 仅重组上述展示模型，不增加评估算法或数据副本。已完成或提前结束计划在执行卡之后显示独立评估板块：第一层按 `MicroPlanEvaluationVerdict` 映射结论与状态徽标，第二层按固定顺序展示事实包中的完成率、反馈记录数、客观对照数、结构化同期背景和冻结基线质量，第三层提供渐变 AI 深度解读入口。完成率条对缺失值保持“无法计算”，同期背景数量由结构化事件次数求和；背景说明继续直接使用 `contextSummary`。页面不解析自由文本形成结论，不改变 AI 确认弹窗、字段白名单或本地评估降级逻辑。

“AI 深度解读与调整建议”是用户主动触发的可选层。确认后，`HealthAIRequest.planEvaluation` 只携带完成率、最多七条受限反馈、相关指标聚合、数据质量、本地结论、背景状态及事件类型/次数/最高强度；不包含生活事件备注、自定义名称、记录 ID、起止时间或原始 HealthKit 样本。客户端与代理同时校验字段白名单；AI 不得新增计划、不引用事实包外指标，也不得把同期事件写成原因。失败时继续显示本地评估。

## 9. AI 设计

### AIService

所有模型通过统一协议调用：

```text
AIService.respond(request: HealthAIRequest) async throws -> HealthAIResponse
AIService.streamResponse(request: HealthAIRequest) -> AsyncThrowingStream<HealthAIStreamEvent, Error>
```

不得让页面依赖某个模型厂商的 SDK 类型。开发阶段可以采用一个模型服务，正式分发前通过后端代理保护密钥。

当前开发适配使用 DeepSeek Responses API 的 `deepseek-v4-flash`，请求设置 `store=false`、关闭思考模式并要求 JSON Schema 结构化输出。个人 Debug 真机允许用户在 App 内主动输入密钥并保存到该设备的 Keychain，由 `PersonalAIService` 直接通过 HTTPS 调用 DeepSeek；没有 Keychain 密钥时可回退到开发代理。Release 版本编译时关闭个人直连，正式分发只允许经过鉴权、限流和密钥轮换的 HTTPS 后端代理。两条开发通路的兼容层都只保证 JSON 字段和类型可被客户端解码（例如把 DeepSeek 偶发返回的 `uncertainty` 字符串数组合并为字符串），不改写、纠正或过滤正常模型结论。诊断、用药、紧急场景和事实引用边界继续由独立客户端安全规则承担。

流式通路使用 Responses API 的 SSE 语义事件：直连和代理都消费 `response.output_text.delta`，以 `response.completed`、`response.incomplete` 或 `response.failed` 结束。因为模型输出本身是结构化 JSON，增量解析器只允许把 `summary` 与其后的 `supportiveClosing` 字符串内容送入白底回答气泡，不展示 JSON 语法或事实数组。局部文本不写入本地会话；仅在完成事件到达、完整响应完成字段兼容、结构解码、事实引用和医疗安全校验后，才持久化正式回答。用户停止、连接失败或最终校验失败时移除未验证的局部气泡，进入既有降级流程。

AI 对话使用最近十条用户/助手消息作为连续上下文，真实数据与演示数据分别保存，避免不同数据来源的会话混用。当前会话最多在本机保留最近八十条消息，文件采用 iOS 完整文件保护写入；“开始新对话”同时删除对应本地会话文件。无健康快照时仍构建明确为空的事实包，使一般健康教育可以继续，同时禁止模型误认为使用了个人记录。回答正文以自然段展示，提示词避免固定模板和机械标题；新响应通过 `supportiveClosing` 返回一至两句与当前问题或可完成行动相关的具体鼓励，不使用空泛口号。需要注意的短语使用受限的 Markdown 加粗；若模型没有输出 Markdown，客户端只把原回答首句加粗显示，不增删或改写结论。旧会话没有 `supportiveClosing` 时按可选字段解码。AI 页不显示顶部健康连接卡，助手回答使用自适应白底气泡；事实和指标依据默认折叠。微计划候选独立常显，展示白名单模板的行动、天数和时间；按最新产品决定不显示“为什么适合我”及推荐理由。确认入口使用圆角矩形按钮，按钮下不重复显示辅助说明。模型追问是等待用户回答的静态卡片，不再把问题自动回发给 AI。

微计划正式页按“计划进度—当前或最近计划—计划期间的变化”组织。顶部进度使用与今日页一致的弧形仪表盘，完成数与计划数只来自 CareKitStore 的 Schedule 和 Outcomes，鼓励内容紧跟进度标题；中部计划卡显示任务、圆角日期/时间信息和当日记录入口；下部趋势卡根据计划模板选择相关指标，例如睡眠类计划显示入睡时间与睡眠时长，步行类计划显示步数与活动能量。趋势使用计划开始前五天与计划期间至多五天的有效日中位数，并可包含最多两天后续观察；计划开始前的评估值优先读取已冻结的 `baselineSnapshot`，后续 HealthKit 回填不会改写它。缺失日不补零，少于两个有效日时不计算变化；真实与演示模式不交叉比较。面积和折线必须使用相同插值，“计划开始”标记位于时间轴；演示数据必须显式标记，文案只描述同期变化，不表达因果结论。

今日页内容区只承担当日数据、目标与行动展示，不放置健康连接状态卡；右上角齿轮以 sheet 打开统一设置。设置接收 Root 选择出的同一 `HealthDataSession`，集中展示真实或演示数据状态、Apple Health 权限用途与刷新、数据来源、提醒、健康摘要、隐私与安全、Debug Keychain 密钥管理和产品说明；切换数据来源后仍由 Root 的共享会话刷新，不在设置内直接访问 HealthKit 服务。“我的”根页只构造并展示“我的有效方法”，不重复设置入口。

### 健康事实包

事实包至少包含：

- 当前与基线时间范围。
- 数据质量与覆盖率。
- 本地计算的趋势事实。
- 最近主观记录。
- 用户主动记录的生活事件。
- 允许推荐的计划模板 ID。
- 数据缺失和不确定性。

当前指标白名单覆盖应用已经支持的十六类 HealthKit 聚合数据：步数、睡眠时长、静息心率、HRV、活动能量、运动分钟、站立小时、心率、呼吸频率、血氧、睡眠腕温、步行与跑步距离、爬楼层数、步行速度、步长和心肺适能。模型应综合与问题相关且数据质量可用的指标；不得为了增加事实数量上传原始样本、重复事实或编造数值。

默认不包含原始样本数组、真实姓名、联系方式、精确地址和不必要的具体日期。

### 结构化响应

响应至少包含：

- `summary`。
- `supportiveClosing`，一至两句与当前问题相关的具体鼓励；客户端为兼容旧会话按可选字段解码。
- `observedFacts`。
- `possibleFactors`。
- `uncertainty`。
- `followUpQuestion`，最多一个。
- `suggestedAction`，只能引用允许模板。
- `safetyLevel`。
- `escalationMessage`。

非流式回答在展示前验证结构、事实引用和安全级别。流式回答的增量阶段只展示白名单正文，并先经过独立输入安全预检查；完成后必须验证完整结构、事实引用和安全级别，验证通过才保存正式回答，失败时移除局部内容并使用本地规则摘要。

## 10. 安全规则层

紧急症状、诊断和用药规则独立于大模型：

```text
用户输入
  → 本地/服务端安全预检查
  → 正常问题才调用模型
  → 结构与事实校验
  → 输出安全后检查
  → 展示或安全降级
```

急症规则优先级高于普通健康洞察。产品只引导寻求专业帮助，不自行诊断。

## 11. 错误与降级

统一领域错误至少区分：

- 权限未请求。
- 权限拒绝或部分授权。
- 无健康数据。
- 健康数据查询失败。
- CareKitStore 读写失败。
- SwiftData 保存失败。
- 网络不可用。
- AI 超时或输出无效。
- 演示数据加载失败。

降级原则：

- AI 失败不影响本地趋势和计划查看。
- HealthKit 无数据时可以使用明确标注的演示模式。
- CareKit 写入失败时不得显示“已完成”。
- SwiftData 保存失败时向用户说明，并避免页面假成功。
- 所有错误对用户使用普通语言，技术详情只进入不含敏感数据的开发诊断。

## 12. 隐私设计

- 原始健康数据默认不上传。
- AI 上传前完成聚合和字段白名单过滤。
- 正式密钥由服务端代理保护。
- 可提交的公共构建设置集中在 `Zhiheng/Config/Base.xcconfig`；可选本地覆盖只允许写入被忽略的 `Zhiheng/Config/Secrets.xcconfig`。
- `Secrets.xcconfig.example` 必须保持无值，且 iPhone 客户端配置中不得出现 AI 厂商正式密钥。
- Keychain 只保存必要凭据，不保存大批健康样本。
- 日志和崩溃报告禁止记录事实包全文、HealthKit 样本和用户自由文本。
- 数据删除需要同时处理 SwiftData、CareKitStore 和本地 AI 对话记录。
- 演示 Fixture 使用合成数据，文件名和界面明确标记。

### 通知授权与用途说明（S13-01）

`NotificationAuthorizationClient` 是 `UserNotifications` 的最小边界，只暴露当前授权状态和用户确认后的授权请求；正式 `SystemNotificationAuthorizationClient` 在 actor 内将系统 `UNAuthorizationStatus` 映射为不依赖框架的领域状态。未知系统状态不得按已授权处理。`NotificationAuthorizationSession` 由 Root 单例持有，在主线程发布加载、未请求、拒绝、已授权、安静授权、临时授权和不可确认状态；刷新只读取状态，不调用授权。只有 `beginRequest` 打开的用途说明仍在显示、状态仍为未请求且没有进行中请求时，`confirmExplanation` 才能调用一次系统授权；取消、拒绝、重复确认和失败均不得造成隐式重试。

`NotificationPermissionExplanationView` 固定展示每日感受、微计划和低频趋势三类未来用途，以及锁屏隐私、每天最多一条常规提醒、可关闭方式和非急救监护边界。页面明确授权本身不会读取新健康数据或安排通知。S13-01 本身不创建 `UNNotificationRequest`、不保存通知偏好、不读取 HealthKit、CareKit 或 AI 数据；S13-02 及后续调度必须继续通过该边界检查权限和用户设置，不能绕过说明门禁。

### 每日感受提醒（S13-02）

`DailyCheckInReminderPolicy` 是纯本地确定规则，只接收版本化本地偏好、通知授权状态、真实/演示模式、今天是否已有签到、参考时刻和时区。偏好默认关闭，时间默认 20:00；无授权、演示模式或签到读取失败均返回空计划。未签到且时间未到时从今天开始，已签到或时间已过时从次日开始；每个本地公历日只生成一个 `zhiheng.daily-check-in.YYYY-MM-DD` 标识。

`SystemDailyCheckInReminderScheduler` 只管理上述前缀的 `UNNotificationRequest`，不删除其他类型通知。为在签到后可靠移除当天待发送项，不使用无法按签到状态抑制的永久重复触发器，而维护未来 30 个公历日的一次性滚动窗口；每次先清理同前缀旧请求，再写入新计划，部分添加失败时回收本次已添加标识。S13-06 已将原本可区分类别的中性文案进一步收敛为三类共用的公开预览，具体边界见下文集中隐私策略。

`DailyCheckInReminderSession` 在主线程读取同一个 `SubjectiveRecordStore`，只持久化开关与时分，不复制签到或通知请求事实。Root 在启动、进入前台和模式变化时先刷新系统授权再同步；`DailyCheckInCoordinator` 只在今日签到成功保存或历史变更后发出重算信号，不转发评分选择。关闭开关、授权撤销、演示模式及读取失败都会以空计划清理待发送项；调度失败不发布虚假的下一次提醒。S13-02 不访问 HealthKit、CareKit、AI、备注或其他自由文本，后续提醒类型必须继续协调每天最多一条的总预算。

### 微计划提醒与每日预算（S13-03）

`MicroPlanReminderPolicy` 是纯本地确定规则，只接收版本化开关、系统授权、真实/演示模式、当前 `MicroPlan`、由 CareKit Schedule 映射的执行日期、Outcome 是否存在、参考时刻和时区。开关默认关闭；只有活动计划、尚未写入 Outcome 且计划内时间仍在未来的日期才生成 `zhiheng.micro-plan.YYYY-MM-DD` 一次性请求。暂停、结束、无活动计划或时间已过均返回空计划。

`MicroPlanReminderSession` 与正式 `MicroPlanSession` 共享同一个 `CarePlanService`，但仅通过 `activePlan`、`outcomeRecords` 和 `occurrenceIndex` 读取 CareKitStore 事实；不读取 Outcome 反馈，不复制 Schedule 或完成状态到 SwiftData。CareKit 任一读取失败即丢弃整批候选并清理该类型请求。Root 在启动、进入前台、数据模式变化，以及活动计划、今日 Outcome 变化后同步；计划创建、打卡、暂停、恢复和结束通过现有会话状态变化触发重算。

`SystemNotificationReminderScheduler` 同时管理每日感受和微计划两个独立前缀。微计划请求全部写入成功后，按同一本地日移除较低优先级的每日感受请求；每日感受重排时也会读取现有微计划标识并跳过已占用日期，因此调用顺序变化仍不会让两种提醒同日并存。微计划关闭或计划状态变化时先清理旧前缀，再由每日感受会话恢复空出的日期。S13-06 后两类锁屏内容不再由各业务模块持有，均通过下文集中隐私策略生成，不使用计划标题、具体行动、反馈、完成率、健康数据或 AI 文本。

### 低频趋势提醒（S13-04）

`LocalLowFrequencyTrendCandidateProvider` 只把共享 `HealthDataSession` 的聚合快照、已加载区间与访问状态交给既有 `InsightFactGenerator`，不重新查询 HealthKit，也不调用 AI。`LowFrequencyTrendCandidateRule` 只接受 7/28 天有效日门槛通过、来源单一且稳定、未被单日异常值保护拦截并达到 `sustainedChange` 的事实；按相对变化与实际门槛之比确定最多一个候选，固定输入产生固定结果。“值得继续观察”和质量降级都不升级成后台通知。

`LowFrequencyTrendReminderSession` 持久化默认关闭的总开关、已处理趋势散列和尚未触发的一次性日期。去重散列只由规则版本、`metric-change` 主题与高/低方向构成，不保存指标数值、来源、样本、主观记录或自由文本。候选形成后必须经同一个 `InsightInteractionStore` 读取 S09-07 主题偏好；读失败按不可用处理，用户在洞悉页关闭或恢复同类提醒后 Root 立即重算。相同主题与方向一经成功进入系统调度便不重复创建；尚未到时的同一请求保持原日期，不会因前台刷新向后漂移。

系统调度器新增独立 `zhiheng.low-frequency-trend.YYYY-MM-DD` 前缀，并把三类优先级固定为微计划、低频趋势、每日感受。微计划写入后移除同日趋势和签到请求；趋势跳过已有微计划日期并在成功后移除同日签到；签到重排同时避开前两类，因此调用顺序变化仍保持每天最多一条。趋势默认选择下一个本地 10:00 一次性时点。S13-06 后趋势锁屏同样使用下文集中隐私策略，不再暴露“趋势”或“观察”类别，也不包含指标、方向、数值、症状、异常或模型文字。

### 统一通知投递设置（S13-05）

`NotificationDeliverySettingsStore` 仅以版本化 `UserDefaults` 保存总开关、频率枚举和安静时间时分；读写由同一锁保护，可由主线程设置会话与通知调度 actor 共享。默认值为总开关开启、每天最多一条及本地 22:00～08:00 安静时间；无效枚举或时分回退默认值。各类型的开关、每日感受时间和趋势去重散列继续由原会话独立持有，关闭总开关不改写这些事实。

`NotificationDeliveryPolicy` 是纯本地确定规则。它先按候选实际触发时刻判断安静时间，命中时直接丢弃；再把稳定通知标识中的本地日期解析为公历日起点，按 1、2 或 7 天最小间隔筛选。调度器继续按微计划、低频趋势、每日感受顺序同步：较低优先级先避开较高优先级已占用日期，高优先级写入后按同一间隔回收较低请求。总开关关闭时每个前缀仍先清理旧请求但不写入新请求。策略不移动原触发时刻，不读取 HealthKit、主观记录、CareKit 反馈、趋势数值或 AI 内容。

`NotificationDeliverySettingsSession` 只负责把今日右上角设置中的总开关、三档频率与安静时间选择写回共享 Store；每次更改后 Root 依次重算三类提醒。每日感受、微计划和趋势会话均使用调度器返回的实际结果更新下一次时间，因此被安静时间、频率或优先级过滤时不显示虚假成功。总开关关闭提示明确偏好和趋势去重历史仍保留。

### 锁屏公开内容隐私（S13-06）

`ReminderNotificationKind` 是调度器接收的唯一业务提示，只表达每日感受、微计划或低频趋势的内部类型；业务层不再提供标题和正文。`ReminderLockScreenPrivacyPolicy` 将三种类型全部映射为同一公开内容“知衡提醒 / 打开知衡查看”，集中创建 `UNMutableNotificationContent`，避免新增提醒时绕过隐私门禁。

系统内容只设置中性标题、正文和默认提示音。`userInfo`、附件、类别、线程、目标内容、角标与启动图片显式保持为空，不复制 HealthKit 聚合、主观记录、CareKit 计划或反馈、趋势方向、来源、去重散列和 AI 输出。请求标识继续只在本地调度内部承担日期、优先级与去重职责。授权前说明展示同一固定预览；系统级“显示预览”方式属于用户控制，应用不能替用户修改。

### 7 天健康摘要预览（S13-07）

`SevenDayHealthSummaryFactory` 是纯 Swift、确定性的内存映射。它接收同一共享快照经 `InsightFactGenerator` 生成的四项核心 `InsightFactSet`，以及同一 `InsightContextLoader` 的全有或全无结构化背景状态；不直接读取 HealthKit、SwiftData、CareKit 或网络。摘要窗口复用 `InsightContextMatcher.window`，固定为截至今天零点的最近 7 个完整本地日，客观趋势仍由此前不重叠的 28 天基线、集中有效日门槛、来源规则和孤立日期保护产生。

摘要模型保留四项客观事实的指标、单位、当前中位数、7/28 天有效日、趋势级别、方向、相对变化、来源和降级原因。主观聚合只计算三项结构化 1～5 分中位数与有记录天数；生活情境只按 `ContextEventKind` 和次数汇总，自定义名称、备注、记录 ID、原始 HealthKit 样本及 CareKit 反馈均不进入摘要。建议文本直接复用 `InsightFourLayerCardFactory` 的本地建议层，并增加可见来源说明；不调用 AI、不自动创建计划。

`SevenDayHealthSummaryView` 从今日右上角设置主动进入，消费 Root 已持有的 `HealthDataSession` 与 `InsightContextLoader`。页面进入只根据当前共享快照生成预览；用户主动刷新时才调用既有健康会话刷新后重建。演示模式与真实模式沿用现有隔离，主观读取失败不发布部分记录但客观事实仍可查看。本任务不落库、不生成 PDF、不调用系统分享，导出留给 S13-08。

### 健康摘要 PDF 与系统分享（S13-08）

`SevenDayHealthReportPDFRenderer` 只接收已验证的 `SevenDayHealthSummary` 和一次性 `SevenDayHealthReportExportOptions`，用系统 `UIGraphicsPDFRenderer` 在本机生成 A4 PDF 数据。它不持有 `HealthDataSession`、Store、网络或 AI 依赖；所有展示文本都从同一个摘要投影映射，确保 App 预览与导出事实边界一致。报告元数据和文件名固定为中性名称，不写用户身份或健康事实；可选姓名默认关闭、只存在于本次导出内存状态，并经过空白和长度校验。

`SevenDayHealthReportTemporaryFileStore` 在应用临时目录内为每次导出创建独立 UUID 子目录，原子写入启用完整文件保护的 PDF 并标记排除备份。返回值同时保存精确文件 URL 与本次清理根目录；清理只删除该独立目录，幂等调用不影响其他导出或普通临时文件。系统分享由 `UIActivityViewController` 包装层接收唯一文件 URL；完成、取消、Sheet 消失或摘要页离开都会触发同一清理路径。

`SevenDayHealthReportPrivacySheet` 是生成动作之前的强制门禁，列出将包含和明确排除的字段、外部副本责任及可选姓名开关。只有用户点击确认才生成 PDF；关闭或取消只清空一次性选项，不创建文件。页面不判断分享目标是否成功接收，也不建立导出历史。演示摘要可以导出用于展示，但 PDF 顶部和元数据必须明确标注为模拟数据。

### 隐私说明与数据流展示（S14-01）

`PrivacyDataFlowCatalog` 是版本为 `s14-privacy-data-flow-v1` 的只读领域目录，集中描述五条实际数据路径：Apple Health 到本机洞察、主观记录与 CareKit 计划、本地通知、AI 对话和 PDF 分享。每个步骤保留稳定 ID、普通用户可读说明、所属边界和是否离开本机；外发只分为用户点击发送问题后的 HTTPS 请求与用户确认后的系统分享。目录不读取任何 Store、HealthKit、网络或当前用户值，也不保存新的隐私偏好。

`PrivacyDataFlowView` 从“今日右上角设置 → 隐私与安全”主动进入，用带文字标签的纵向流程卡展示 Apple 系统、知衡本机、加密网络和外部接收方四种边界；颜色只作辅助。页面同时列出每条外发路径会传递与明确排除的字段、通知固定预览、临时 PDF 生命周期、外部副本责任、权限和现有删除入口。页面不得承诺绝对安全，也不得把 S14-02～S14-10 尚未完成的专项审计写成已通过。

普通 AI 对话的当前请求边界以实现为准：用户本次问题、最近最多 10 条对话和 `HealthFactPackBuilder` 生成的聚合 HealthKit 事实；普通对话尚不加入主观记录或生活事件。用户主动请求计划 AI 解读时，现有独立事实包可以加入完成率、最多七条受限反馈、相关指标聚合、数据质量、本地结论和结构化生活背景；两条路径都排除原始 HealthKit 样本数组、身份/联系方式、生活事件备注、自定义名称和底层记录 ID。完整可审计说明见 `docs/privacy-data-flow.md`。

## 13. 测试设计

### 单元测试

- 数据质量门槛和断档。
- 基线与趋势。
- 主客观状态矩阵。
- 计划效果和可信度。
- 事实包字段白名单。
- AI 结构校验与安全规则。

### 集成测试

- HealthKit 授权与查询。
- CareKit 计划、Schedule、Outcome 和版本历史。
- SwiftData 持久化与删除。
- Provider 切换。
- AI Gateway 成功、错误、超时和取消。

### UI 与人工测试

- 首次授权、部分授权、无数据。
- 计划创建、完成、暂停和提前结束。
- 动态字体、VoiceOver、深色模式。
- 断网和模型失败。
- 真实/模拟数据标签。

## 14. 技术决策记录

以下决定必须写入当天开发日志，必要时同步更新本文件：

- HealthKit 数据层最终选择。
- CareKit 和 CareKitUI 使用范围。
- 最低 iOS 版本。
- Swift/测试框架版本。
- AI 模型和后端方式。
- 任何新依赖。
- 数据模型迁移。
- 算法阈值变化。
- 隐私和医疗安全边界变化。

没有实测证据时，文档中的框架 API 视为设计意图；实现前必须根据当时官方文档和固定版本确认。
