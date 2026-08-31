import SwiftUI

enum HealthAccessPurpose: String, CaseIterable, Identifiable {
    case activity
    case sleep
    case heart
    case vitals

    var id: Self { self }

    var title: String {
        switch self {
        case .activity: "活动与运动"
        case .sleep: "睡眠"
        case .heart: "心脏相关趋势"
        case .vitals: "夜间生命体征"
        }
    }

    var detail: String {
        switch self {
        case .activity: "步数、活动能量、运动分钟、站立、步行跑步距离、爬楼和步态，用来理解日常活动变化。"
        case .sleep: "睡眠时长和时间段，用来建立你自己的作息基线。"
        case .heart: "静息心率、普通心率、HRV 和心肺适能，用来观察近期变化，不用于诊断疾病。"
        case .vitals: "呼吸频率、血氧和睡眠腕温，用来整理夜间记录；缺失时不会补零或给出确定结论。"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: "figure.walk"
        case .sleep: "bed.double.fill"
        case .heart: "heart.text.square.fill"
        case .vitals: "waveform.path.ecg.rectangle.fill"
        }
    }
}

struct HealthAccessExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    let onContinue: () -> Void
    let isRequesting: Bool
    let requestErrorMessage: String?

    init(
        isRequesting: Bool = false,
        requestErrorMessage: String? = nil,
        onContinue: @escaping () -> Void
    ) {
        self.isRequesting = isRequesting
        self.requestErrorMessage = requestErrorMessage
        self.onContinue = onContinue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    purposeList
                    privacyCard
                    permissionNote
                }
                .padding()
                .padding(.bottom, 88)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("连接 Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不连接") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)

            Text("先了解用途，再决定是否授权")
                .font(.title2.weight(.bold))

            Text("知衡只会读取你在系统授权页中选择的数据，用它们建立个人基线、解释趋势和评估低风险微计划。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var purposeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("希望读取的数据")
                .font(.headline)

            ForEach(HealthAccessPurpose.allCases) { purpose in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: purpose.systemImage)
                        .frame(width: 28, height: 28)
                        .font(.title3)
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(purpose.title)
                            .font(.subheadline.weight(.semibold))
                        Text(purpose.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("你的数据边界", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(.teal)

            commitment("只读访问：知衡不会修改或删除 Apple Health 中的数据。")
            commitment("本地优先：原始健康样本不会直接发送给 AI。")
            commitment("健康管理：这些数据不用于疾病诊断、用药决定或急救监护。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color.teal.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func commitment(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.primary)
    }

    private var permissionNote: some View {
        Text("你可以只授权部分数据，也可以暂不连接。拒绝授权后仍可进入 App，并可稍后在系统设置中更改。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var continueButton: some View {
        VStack(spacing: 8) {
            if let requestErrorMessage {
                Label(requestErrorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                onContinue()
            } label: {
                if isRequesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("继续")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isRequesting)

            Text("点击继续后，才会显示系统授权选项。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    HealthAccessExplanationView(onContinue: {})
}
