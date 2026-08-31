# CareKitStore 技术样例

这是知衡 S02 的隔离验证包，不是正式 App 工程。它只依赖 CareKit 4.1.0 的 `CareKitStore` 产品，用于验证：

- 三天微计划、每日任务和 Schedule。
- Outcome 与 Outcome Value 写入和读取。
- `OCKAdherenceQuery` 与 `CareTaskProgressStrategy` 的当前 API。
- 任务更新产生可追溯历史版本。
- CareKitStore 与知衡领域摘要之间的适配边界。

运行：

```shell
swift test
```

正式工程不得直接复制本样例中的简化完成率语义；需要按技术设计规范补充跳过、提前结束、数据质量和计划效果评估。

