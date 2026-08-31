import Charts
import SwiftUI

struct HealthMetricDetailView: View {
    let metric: HealthMetricType
    let state: HealthMetricReadState
    var referenceDate = Date()
    @State private var selectedTrendWindow = HealthTrendWindow.sevenDays

    private var presentation: HealthMetricStatusPresentation {
        HealthMetricStatusPresentation(metric: metric, state: state)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                currentValueCard
                if case let .available(samples) = state {
                    trendCard(samples)
                    dataCoverageCard(samples)
                    recentRecordsCard(samples)
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trendCard(_ samples: [HealthMetricSample]) -> some View {
        let points = HealthMetricDailySeriesCalculator.points(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            window: selectedTrendWindow
        )
        let chartPresentation = HealthTrendChartPresentation(
            points: points,
            expectedDayCount: selectedTrendWindow.rawValue
        )
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("趋势", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                if let latest = points.last {
                    Text(valueText(latest.value, unit: latest.unit))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            }

            Picker("趋势范围", selection: $selectedTrendWindow) {
                ForEach(HealthTrendWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                ContentUnavailableView(
                    "暂无可绘制趋势",
                    systemImage: "chart.xyaxis.line",
                    description: Text("当前时间范围没有可安全汇总的每日记录。")
                )
                .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        yStart: .value("图表起点", chartPresentation.yDomain.lowerBound),
                        yEnd: .value("数值", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor.opacity(0.22), accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("数值", point.value)
                    )
                    .foregroundStyle(accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("数值", point.value)
                    )
                    .foregroundStyle(accentColor)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .chartYScale(domain: chartPresentation.yDomain)
                .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
                .frame(height: 220)
                .accessibilityLabel("\(presentation.title)\(selectedTrendWindow.title)趋势")
                .accessibilityValue("共 \(points.count) 个有效日，最新记录 \(valueText(points.last?.value ?? 0, unit: metric.expectedUnit))")
            }

            Text(chartPresentation.contextText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var currentValueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(accentColor, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.headline)
                    Text("当前记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch state {
            case let .available(samples):
                summaryContent(
                    HealthMetricSummaryCalculator.summarize(
                        metric: metric,
                        samples: samples,
                        referenceDate: referenceDate
                    )
                )
            default:
                Text(presentation.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let detail = presentation.fallbackDetail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func dataCoverageCard(
        _ samples: [HealthMetricSample]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据连续性")
                .font(.headline)
            if let shortTerm = qualityReport(
                samples: samples,
                expectedDays: HealthDataQualityThresholds.shortTermExpectedDays
            ) {
                coverageRow(shortTerm)
            }
            if let inventory = qualityReport(
                samples: samples,
                expectedDays: HealthDataQualityThresholds.inventoryExpectedDays
            ) {
                coverageRow(inventory)
            }
            Text("有效日只表示当天存在记录，不代表当天健康状况良好或异常。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func coverageRow(_ report: HealthDataQualityReport) -> some View {
        let percentage = Int((report.coverageRatio * 100).rounded())
        return HStack(alignment: .firstTextBaseline) {
            Text("近 \(report.expectedDayCount) 天")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("有效 \(report.validDayCount) 天 · \(percentage)%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func recentRecordsCard(
        _ samples: [HealthMetricSample]
    ) -> some View {
        let points = HealthMetricDailySeriesCalculator.points(
            metric: metric,
            samples: samples,
            endingAt: referenceDate,
            window: .sevenDays
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("近期记录")
                .font(.headline)
            if points.isEmpty {
                Text("最近 7 天没有可安全汇总的每日记录；缺失值不会补成 0。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(points.reversed()) { point in
                    HStack(alignment: .firstTextBaseline) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                        Spacer()
                        Text(valueText(point.value, unit: point.unit))
                            .font(.subheadline.weight(.semibold))
                    }
                    if point.id != points.first?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    @ViewBuilder
    private func summaryContent(_ result: HealthMetricSummaryResult) -> some View {
        switch result {
        case let .value(summary):
            Text(valueText(summary.value, unit: summary.unit))
                .font(.largeTitle.weight(.bold))
            Text("更新于 \(summary.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("来源：\(summary.sourceName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .noData:
            Text("今天暂无可汇总数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .multipleSources:
            Text("存在无法安全合并的来源")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func qualityReport(
        samples: [HealthMetricSample],
        expectedDays: Int,
        calendar: Calendar = .current
    ) -> HealthDataQualityReport? {
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(expectedDays - 1),
            to: referenceDate
        ) else {
            return nil
        }
        return try? HealthDataQualityCalculator.evaluate(
            metric: metric,
            samples: samples,
            interval: DateInterval(
                start: calendar.startOfDay(for: firstDay),
                end: referenceDate
            ),
            calendar: calendar
        )
    }

    private var systemImage: String {
        switch metric {
        case .stepCount: "shoeprints.fill"
        case .sleepDuration: "bed.double.fill"
        case .restingHeartRate: "heart.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .activeEnergy: "flame.fill"
        case .exerciseDuration: "clock.fill"
        case .standHours: "figure.stand"
        case .heartRate: "heart.circle.fill"
        case .respiratoryRate: "lungs.fill"
        case .oxygenSaturation: "drop.fill"
        case .wristTemperature: "thermometer.medium"
        case .walkingRunningDistance: "figure.walk"
        case .flightsClimbed: "stairs"
        case .walkingSpeed: "speedometer"
        case .walkingStepLength: "ruler.fill"
        case .vo2Max: "lungs.fill"
        }
    }

    private var accentColor: Color {
        switch metric {
        case .stepCount: .teal
        case .sleepDuration: .purple
        case .restingHeartRate: .pink
        case .heartRateVariability: .mint
        case .activeEnergy: .orange
        case .exerciseDuration: .cyan
        case .standHours: .blue
        case .heartRate: .red
        case .respiratoryRate: .indigo
        case .oxygenSaturation: .cyan
        case .wristTemperature: .orange
        case .walkingRunningDistance: .teal
        case .flightsClimbed: .orange
        case .walkingSpeed: .blue
        case .walkingStepLength: .cyan
        case .vo2Max: .mint
        }
    }

    private func valueText(_ value: Double, unit: HealthMetricUnit) -> String {
        switch unit {
        case .count:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 步"
        case .hours:
            "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
        case .beatsPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 次/分"
        case .milliseconds:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 毫秒"
        case .kilocalories:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 千卡"
        case .minutes:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 分钟"
        case .breathsPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(1)))) 次/分"
        case .percentage:
            "\(value.formatted(.number.precision(.fractionLength(1))))%"
        case .degreesCelsius:
            "\(value.formatted(.number.precision(.fractionLength(1))))℃"
        case .kilometers:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 公里"
        case .floors:
            "\(value.formatted(.number.precision(.fractionLength(0)))) 层"
        case .metersPerSecond:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 米/秒"
        case .meters:
            "\(value.formatted(.number.precision(.fractionLength(2)))) 米"
        case .millilitersPerKilogramPerMinute:
            "\(value.formatted(.number.precision(.fractionLength(1)))) ml/kg·min"
        }
    }
}
