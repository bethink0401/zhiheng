import SwiftUI

struct StateComparisonCard: View {
    @ObservedObject var healthSession: HealthDataSession
    @ObservedObject var feelingSession: SubjectiveCheckInSession
    @State private var showsDetails = false
    @State private var result = StateComparisonResult(kind: .missingFeelings, feeling: nil,
        currentInterval: nil, baselineInterval: nil, evidence: [])

    var body: some View {
        // Refresh the date guard while the app remains open across midnight; no new queries.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Button { showsDetails = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.split.2x2")
                        .font(.title3).foregroundStyle(.teal).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("感受与数据对照").font(.subheadline.weight(.semibold))
                        Text(result.kind.title).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("感受与数据对照，\(result.kind.title)，查看依据")
            .sheet(isPresented: $showsDetails) {
                StateComparisonDetail(result: result,
                    checkIn: healthSession.dataMode == .live && feelingSession.didLoadRecord
                        ? feelingSession.savedCheckIn : nil)
            }
            .onChange(of: context.date, initial: true) { _, date in update(at: date) }
        }
        // Draft rating taps must not recalculate health trends or change the saved comparison.
        .onChange(of: feelingSession.savedCheckIn) { _, _ in update() }
        .onChange(of: feelingSession.didLoadRecord) { _, _ in update() }
        .onChange(of: healthSession.snapshot) { _, _ in update() }
        .onChange(of: healthSession.snapshotInterval) { _, _ in update() }
        .onChange(of: healthSession.accessState) { _, _ in update() }
        .onChange(of: healthSession.dataMode) { _, mode in
            if mode != .live { showsDetails = false }
            update()
        }
    }

    private func update(at date: Date = Date()) {
        result = StateComparisonEngine.make(
            snapshot: healthSession.snapshot, loadedInterval: healthSession.snapshotInterval,
            access: healthSession.accessState, mode: healthSession.dataMode,
            checkIn: feelingSession.savedCheckIn, didLoadCheckIn: feelingSession.didLoadRecord,
            now: date, timeZone: .autoupdatingCurrent)
    }
}

private struct StateComparisonDetail: View {
    let result: StateComparisonResult
    let checkIn: DailyCheckIn?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.kind.title).font(.title3.weight(.semibold))
                        Text(result.kind.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

                    if let record = checkIn, result.feeling != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今日已保存的感受").font(.headline)
                            ForEach([DailyFeelingField.energy, .stress, .bodyFeeling], id: \.self) { field in
                                HStack {
                                    Text(field.title).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(field.label(for: field.rating(in: record)))
                                }.font(.subheadline)
                            }
                            Text("\(record.localDay.storageKey) · \(record.localDay.timeZoneIdentifier)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if let current = result.currentInterval, let baseline = result.baselineInterval {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("近期数据依据").font(.headline)
                            Text("最近 7 个完整日：\(range(current))")
                            Text("此前 28 天基线：\(range(baseline))")
                            Text("今日感受与截至昨日的近期趋势并列，不是同一时间尺度，也不代表彼此存在因果关系。")
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(result.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(HealthContextTimeline.title(for: evidence.metric)).font(.headline)
                            Text(evidence.status.text).font(.subheadline.weight(.medium))
                            if let trend = evidence.trend {
                                Text("有效日：近期 \(trend.currentValidDayCount)/7 · 基线 \(trend.baselineValidDayCount)/28")
                                if let baseline = trend.baselineMedianValue, let current = trend.currentMedianValue {
                                    Text("中位数：\(HealthContextTimeline.valueText(baseline, metric: evidence.metric)) → \(HealthContextTimeline.valueText(current, metric: evidence.metric))")
                                }
                                if let change = trend.relativeChange {
                                    Text(String(format: "相对变化 %+.1f%%", change * 100))
                                }
                                if let threshold = trend.effectiveRelativeThreshold {
                                    Text(String(format: "实际变化门槛 %.1f%%", threshold * 100))
                                }
                                if let aligned = trend.alignedDayCount, let required = trend.requiredAlignedDayCount {
                                    Text("同向日 \(aligned) 天 · 持续判断至少 \(required) 天")
                                }
                                if trend.isolatedOutlierExcluded {
                                    Text("当前中位数来自孤立日期保护后的分析副本，原记录未删除。")
                                }
                            }
                            if !evidence.sources.isEmpty { Text("来源：\(evidence.sources.joined(separator: "、"))") }
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                    DisclosureGroup("对照规则与边界") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("精力或身体感受 1～2，或压力 4～5，任一项都会提示照顾感受；精力和身体 4～5、压力 1～2 才归为舒适，其余不强行分类。没有综合健康分。")
                            Text("四项数据均需最近 7 天至少 4 个有效日、此前 28 天至少 14 个有效日，且昨日有记录。来源变化、冲突、孤立日期保护和未形成明确趋势时，不合并判断；任何方向的持续变化都不直接称作变好或变差。")
                            Text("未见明确变化 + 感受舒适：保持适合自己的节奏。\n未见明确变化 + 感受需照顾：尊重感受，补充生活背景。\n持续变化 + 感受舒适：不制造焦虑，继续观察。\n持续变化 + 感受需照顾：先照顾感受，不推断原因。")
                            Text("对照规则：\(StateComparisonRules.version)\n趋势阈值：\(HealthMetricTrendThresholdCatalog.version)")
                            Text("仅在本机处理，不上传 AI，不自动创建微计划；这不是诊断或医疗监护。")
                        }.font(.footnote).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    .font(.subheadline)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("感受与数据对照")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func range(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: interval.start)) — \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
    }
}
