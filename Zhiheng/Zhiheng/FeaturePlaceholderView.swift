import SwiftUI

struct FeaturePlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                Text("正在按开发计划逐步建立")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.teal)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    FeaturePlaceholderView(
        title: "洞察",
        systemImage: "chart.xyaxis.line",
        message: "数据质量通过后才会显示趋势。"
    )
}

