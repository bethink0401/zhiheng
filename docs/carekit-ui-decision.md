# CareKitUI 与自定义 SwiftUI 适配决策

| 项目 | 内容 |
| --- | --- |
| 决策编号 | ADR-S02-16 |
| 状态 | 已接受 |
| 日期 | 2026-08-21 |
| 适用范围 | 知衡 iPhone 第一版 |
| 关联任务 | S02-11、S02-12、S02-16、S03-10、S03-11 |

## 1. 最终决定

知衡第一版使用**自定义 SwiftUI 页面与组件**，通过 `CarePlanService` 读取和写入计划事实；正式 App 继续只链接 `CareKitStore`，不链接 `CareKit` 同步控制器产品，也不链接 `CareKitUI` 产品。

这不是放弃 CareKit。计划、任务、Schedule、Outcome、版本历史和磁盘持久化仍由 CareKitStore 负责；被替换的只是展示层。页面和 ViewModel 不允许出现 `OCK` 类型。

## 2. 实测与源码证据

### CareKit 4.1.0 包结构

- `CareKitStore` 提供 Core Data Store 和计划事实，是知衡已经验证并接入的必要依赖。
- `CareKitUI` 同时包含原生 SwiftUI 卡片和大量 UIKit 视图。
- `CareKit` 产品依赖 `CareKitUI` 与 `CareKitStore`，其自动同步能力主要由 `UIViewController`、`SynchronizedViewController` 和 View Synchronizer 组成。
- CareKit 源码明确提到 SwiftUI 生命周期 App 包装部分控制器时需要 `UIViewControllerRepresentable`，且存在 tint color 不能自然传播的兼容处理。

### 官方示例运行结果

- OCKCatalog 与 OCKSample 的默认分支都没有工程文件，需要使用官方补工程分支。
- 两个示例锁定 2021 年 CareKit 提交，不是知衡采用的 4.1.0；在 iOS 26.5 模拟器均可构建和启动，只能作为交互参考。
- Catalog 在未授权时只显示“到设置启用 HealthKit”，没有知衡所需的未请求、拒绝、无数据和失败四态语义。
- Sample 能快速展示日历、任务、完成环和图表，但出现未本地化占位符，整体视觉与当前系统和知衡样式存在明显差异。

### 知衡现状

- 根导航、今日页和通用状态组件均为 SwiftUI，并已验证浅色、深色和最大无障碍字体。
- `CareKitPlanStore` 已把 CareKit 类型隔离在基础设施层。
- 磁盘重建后，计划、Outcome 和最新版本均可通过领域协议读回；UI 不需要直接依赖 OCKStore 才能获得完整事实。

## 3. 方案比较

| 维度 | CareKit 同步控制器 | 仅使用 CareKitUI SwiftUI 卡片 | 自定义 SwiftUI（采用） |
| --- | --- | --- | --- |
| 首次任务页速度 | 快，已有日历和多种任务控制器 | 中，需要自行连接状态与操作 | 中，需要实现计划卡和进度视图 |
| Store 自动同步 | 强，控制器直接观察 Store | 无完整同步层，仍需 ViewModel | 通过 `CarePlanService` 明确刷新 |
| 接入当前 SwiftUI 导航 | 需要 UIKit 容器与桥接 | 容易 | 最自然 |
| 视觉统一 | 需要重写 CareKit 样式和容器细节 | 可调整，但引入另一套 Style 环境 | 直接复用知衡语义颜色、间距和状态组件 |
| 健康状态语义 | 偏通用护理任务 | 偏通用任务卡 | 可严格区分未授权、缺失、失败、真实零值与数据质量 |
| 领域隔离 | 页面容易直接接触 Store/OCK 查询 | 视接法而定 | 页面只依赖知衡领域模型 |
| 动态字体与深色模式 | 框架有支持，桥接后仍需整页复验 | 源码预览覆盖相关场景 | 现有基线已实测，新增组件继续同一套标准 |
| 本地化与中文产品文案 | 需要覆盖框架字符串和旧示例问题 | 需要管理框架与产品两套文案 | 所有用户文案由知衡统一管理 |
| 依赖与升级面 | 新增 CareKit + CareKitUI 展示 API | 新增 CareKitUI 展示 API | 保持当前仅 CareKitStore |
| 长期原创能力 | 容易形成“示例换皮”观感 | 中等 | 最适合主客观对照、解释性洞察和有效方法闭环 |

## 4. 成本结论

自定义 SwiftUI 在第一张任务卡上比直接使用同步控制器多一层 ViewModel 与交互实现，但这些工作本来就需要承担：知衡必须显示数据质量、主观反馈、解释依据和计划效果，而这些不是通用 CareKit 卡片的职责。

采用 CareKit 全套 UI 的短期收益主要是日历、任务卡和 Store 自动同步；代价是 UIKit 桥接、两套样式系统、框架本地化、页面直接接触 CareKit 查询的诱惑，以及后续为知衡差异化功能大幅定制。综合第一版范围，自定义 SwiftUI 的总维护成本更低。

## 5. 实施约束

1. Presentation 和 ViewModel 只使用 `MicroPlan`、`MicroPlanProgress`、`PlanOutcomeInput` 等领域类型。
2. 所有计划写操作经过 `CarePlanService`；不得在按钮事件中直接创建 `OCKOutcome`。
3. 计划列表与详情使用 SwiftUI；趋势与计划结果图使用 Swift Charts。
4. 完成、跳过、暂停、恢复和提前结束必须有明确的加载、成功、冲突与失败状态，不能乐观显示后不处理持久化失败。
5. 用户文案由知衡资源统一管理，不依赖示例字符串。
6. 不复制 OCKSample 的品牌、完整布局或示例医疗叙事。

## 6. 允许的例外与重新评估条件

未来只有在以下情况之一出现时，才创建独立技术验证重新评估 CareKitUI：

- 自定义实现某个复杂任务交互的无障碍成本经测试明显高于单个 CareKitUI 原生 SwiftUI 组件。
- 需要 CareKit 已提供且稳定的专用图表或联系人交互，且产品需求与其语义完全一致。
- 可以只包装一个隔离组件，不把 `OCK` 类型传播到页面其余部分。

即使触发重新评估，也优先试用单个 CareKitUI SwiftUI 组件；不得直接把整个 `OCKDailyPageViewController` 设为知衡主页面。

## 7. 验收结果

- 官方双示例已构建并启动，比较不是仅依据 README。
- CareKit 4.1.0 包依赖和 UI 源码已核对。
- 正式工程仍只链接 CareKitStore，未增加 UI 依赖。
- 当前领域隔离与磁盘持久化测试保持通过。
