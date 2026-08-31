# 知衡第一版技术设计规范

| 项目 | 内容 |
| --- | --- |
| 文档版本 | V1.0 |
| 更新日期 | 2026-08-30 |
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

当前正式微计划页通过共享的 `MicroPlanSession` 调用 `CarePlanService`，只展示领域模型。AI 建议先映射到十类白名单 `MicroPlanTemplate`，用户点击确认后才创建五天计划；同一时刻只允许一个活动计划。今日完成、跳过和提前结束均写入或更新 CareKitStore，界面不另存一份完成事实。

`CarePlanService.planHistory()` 提供全部计划的领域化历史，`CareKitPlanStore` 负责按稳定计划 ID 去重、把已过期活动计划归一为完成状态并按开始时间倒序返回。微计划页右上角以圆形 Liquid Glass 历史图标进入独立历史页；历史卡的计划、任务、日期、时间和完成率仍只来自 CareKitStore。

必须保留稳定 ID 和版本化历史。暂停、修改和提前结束优先通过 CareKit 支持的时间化版本更新表达，不直接篡改过去结果。

### SwiftData

保存 CareKit 不承担的用户与分析数据：

- `DailyCheckIn`。
- `ContextEvent`。
- `InsightRecord`。
- `PlanAnalysisMetadata`。
- `EffectiveMethod`。
- 可选的 AI 对话元数据。

`PlanAnalysisMetadata` 只通过 `carePlanID` 关联计划，不重复保存每日完成状态。

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
- 今日页展示连续 7 日选择、五项目标完成度、当日身体/日常数据和昨晚生命体征，不显示跨日趋势结论。
- 7 日窗口分页时按手势方向为整组日期使用 0.34 秒滑入、滑出与淡化组合动画；选择日期和整组分页仍由同一展示模型驱动。
- 日期活动圆环和日常活动卡使用活动能量、运动分钟、站立小时三个独立比例；步数和活动能量的 24 小时柱状图使用与全天汇总一致的来源选择规则，并以显式 `yStart = 0` 保持柱底对齐。
- 活动圆环由 `Infrastructure/HealthKit/SystemActivityRingView` 隔离封装苹果 `HKActivityRingView`；Feature 页面只传入领域层归一化进度，不直接依赖 HealthKitUI 类型。日常卡使用固定外框和略小的原生视图，避免 HealthKitUI 内部留白或外圈被裁切。
- 睡眠阶段时间轴由 SwiftUI 自定义绘制，保留 HealthKit awake/core/deep/REM 区间；不显示左侧阶段标签，连续区间的竖向转换采用低透明度双颜色渐变。生命体征状态只表达查询是否获得有效记录，不执行医学正常范围判定。
- 标准字号的日常模块使用两列等宽网格并通过 1:1 比例固定为正方形，辅助功能字号切为单列；身体两张卡的顶部图标统一使用 46×46 点布局区域，使标题与说明从同一纵向基线开始。生命体征卡统一固定为 136×136 点且不使用投影；不同 SF Symbol 统一放入 24×24 点布局区域，名称使用固定 20 点高度的常规 `subheadline`。数值行把 32 点圆角粗体数字与小号单位拆分，避免长单位触发整行缩小；状态行只保留 2 点顶部间距并移除数值前的弹性占位，使数值和状态整体上移。横向生命体征视口抵消页面左右内边距，内容首尾再补同值间距，使初始卡片与标题对齐且滚动时可到达屏幕边界。
- 日常模块除卡片自身的 1:1 约束外，在 `LazyVGrid` 单元外层再次强制 1:1，避免 `NavigationLink` 或内容固有高度使睡眠和活动卡尺寸偏离。目标仪表外环保持既定方向，刻度遮罩独立顺时针旋转 90°；刻度先绘制完整灰色轨道，再按完成比例以相同渐变遮罩覆盖，百分比下方固定显示 `Perfect Day`。
- 睡眠样本在领域层保留 `HealthSleepStage`。深睡、核心、REM 和清醒按 HealthKit 原始分类展示；清醒样本值为 0，仅保留真实起止时间，避免计入睡眠总时长。
- 睡眠汇总、日序列和昨夜区间统一使用 Apple Watch、iPhone、其他来源的稳定优先级；未知类别存在多个来源时继续拒绝猜测。血氧从 HealthKit 的 0～1 `percent` 单位乘以 100 转换成页面百分比。
- HRV 状态只比较此前 28 天个人基线且至少需要 14 个有效日，页面用“状态偏低/状态正常/状态较好”表达相对位置；训练准备至少需要 4 个可用组件，并保留实际使用组件数和建议说明供辅助功能读取。
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
- HealthKit 连接状态和权限入口集中在“我的”页，今日页不重复展示；设置页继续消费 Root 的同一共享会话，不建立第二份状态。

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

## 8. CareKit 计划设计

### 模板到 CareKit 的转换

`MicroPlanTemplate` 是知衡定义的低风险计划模板，包含标题、目标、默认天数、日程和观察指标。开始计划时转换为 CareKit 实体。

```text
MicroPlanTemplate
  → OCKCarePlan
  → 一个或多个 OCKTask
  → OCKSchedule
```

每日执行写入 `OCKOutcome`。`OCKOutcomeValue` 可以保存完成量、困难度等量化数据；自由文本应控制长度并避免敏感信息进入技术日志。

### 计划评估

```text
CareKit Outcomes / CareTaskProgressStrategy / OCKAdherenceQuery
            +
HealthKit 计划前后指标
            +
SwiftData 主观感受和生活事件
            ↓
MethodEvaluationEngine
            ↓
PlanEvaluation + EffectiveMethod
```

评估结果存储计算输入摘要、结果和版本，不能覆盖 CareKit 原始执行历史。

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

微计划正式页按“计划进度—当前或最近计划—计划期间的变化”组织。顶部进度使用与今日页一致的弧形仪表盘，完成数与计划数只来自 CareKitStore 的 Schedule 和 Outcomes，鼓励内容紧跟进度标题；中部计划卡显示任务、圆角日期/时间信息和当日记录入口；下部趋势卡根据计划模板选择相关指标，例如睡眠类计划显示入睡时间与睡眠时长，步行类计划显示步数与活动能量。趋势使用计划开始前五天与计划期间至多五天的有效日中位数，并可包含最多两天后续观察；缺失日不补零，少于两个有效日时不计算变化。面积和折线必须使用相同插值，“计划开始”标记位于时间轴；演示数据必须显式标记，文案只描述同期变化，不表达因果结论。

今日页只承担当日数据、目标与行动展示，不再放置健康连接状态卡。“我的”接收 Root 选择出的同一 `HealthDataSession`，集中展示真实或演示数据状态、Apple Health 权限用途与刷新、数据来源、隐私与安全、Debug Keychain 密钥管理和产品说明；切换数据来源后仍由 Root 的共享会话刷新，不在设置页直接访问 HealthKit 服务。

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
