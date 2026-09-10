import SwiftUI

/// Read-only context: shared HealthKit snapshot + the existing local history store.
struct HealthContextTimelineView: View {
    @ObservedObject var session: SubjectiveHistorySession
    @ObservedObject var healthSession: HealthDataSession
    @State private var endingDate = Date()

    private var canDisplay: Bool { session.isEnabled && healthSession.dataMode == .live }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if canDisplay {
                    DatePicker("截至日期", selection: $endingDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    Text("按日期并列记录，不代表生活事件导致健康变化。未记录不等于没有发生，缺失值不补零。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DisclosureGroup("日期与数据说明") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("浏览时区：\(session.timeZone.identifier)。健康指标按本地日期汇总，睡眠归入结束日；感受保留记录时的本地日期和原时区，旅行换时区时请留意差异。")
                            Text("步数、睡眠使用既有单来源日合计；静息心率和 HRV 使用当日最后一条可用值，不是日平均。来源冲突时不强行合并。事件按起止时间与当天重叠显示，跨日事件可在多天出现。")
                            if let interval = healthSession.snapshotInterval {
                                Text("本次健康数据范围：\(dateText(interval.start)) 至 \(dateText(interval.end))。超出范围不推断为无数据。")
                            }
                            Text("这里只展示已有记录，不判断趋势或方法效果。内容仅在本机对照，不上传 AI。")
                        }
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    .font(.subheadline)
                    Button {
                        session.loadTimeline(endingAt: endingDate)
                        Task { await healthSession.refresh() }
                    } label: {
                        Label(healthSession.isLoading ? "正在刷新健康数据…" : "刷新时间线", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(FeelingActionButtonStyle(isPrimary: false))
                    .disabled(healthSession.isLoading)
                    if let interval = healthSession.snapshotInterval {
                        Text("健康数据截至 \(dateText(interval.end))；今日数据尚不完整。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = session.timelineError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                    } else {
                        ForEach(session.timelineDays) { day in dayCard(day) }
                    }
                } else {
                    Text("演示模式不读取真实感受和生活事件，请返回真实数据模式查看。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("同日时间线")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.timeZone, session.timeZone)
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .onAppear {
            endingDate = session.selectedDate
            reload()
        }
        .onChange(of: endingDate) { _, _ in reload() }
    }

    private func reload() {
        guard canDisplay else { return }
        session.loadTimeline(endingAt: endingDate)
    }

    private func dayCard(_ day: HealthContextTimelineDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(.teal)
                Text(day.localDay.storageKey).font(.headline)
                Spacer()
                if day.localDay.storageKey == SubjectiveLocalDay(date: Date(), timeZone: session.timeZone).storageKey {
                    Text("今日 · 尚未结束").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 10) {
                ForEach(HealthContextTimeline.metrics, id: \.self) { metric in
                    metricRow(metric, day: day)
                }
            }
            Divider()
            Text("当日感受").font(.subheadline.weight(.semibold))
            if let checkIn = day.checkIn {
                ForEach([DailyFeelingField.energy, .stress, .bodyFeeling], id: \.self) { field in
                    HStack {
                        Text(field.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(field.label(for: field.rating(in: checkIn)))
                    }.font(.subheadline)
                }
                if let note = checkIn.note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                if checkIn.localDay.timeZoneIdentifier != session.timeZone.identifier {
                    Text("记录时区：\(checkIn.localDay.timeZoneIdentifier)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("这一天未记录感受").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            Text("生活事件").font(.subheadline.weight(.semibold))
            if day.events.isEmpty {
                Text("这一天没有已记录事件").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(day.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.customLabel ?? event.kind.title).font(.subheadline.weight(.medium))
                        Text(eventTime(event)).font(.caption).foregroundStyle(.secondary)
                        if let note = event.note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func metricRow(_ metric: HealthMetricType, day: HealthContextTimelineDay) -> some View {
        let state = HealthContextTimeline.metricState(
            metric, day: day.interval, snapshot: healthSession.snapshot,
            loadedInterval: healthSession.snapshotInterval, access: healthSession.accessState,
            timeZone: session.timeZone
        )
        return HStack(alignment: .top) {
            Text(HealthContextTimeline.title(for: metric)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if case let .value(value, source) = state {
                    Text(HealthContextTimeline.valueText(value, metric: metric)).fontWeight(.medium)
                    Text(source).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(state.message).foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }

    private func eventTime(_ event: ContextEvent) -> String {
        let start = dateText(event.startedAt)
        return event.endedAt.map { "\(start) — \(dateText($0))" } ?? "\(start) · 未记录持续时长"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = session.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
