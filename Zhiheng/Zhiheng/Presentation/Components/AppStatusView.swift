import SwiftUI

struct AppStatusView: View {
    let state: AppContentState
    let action: (() -> Void)?

    init(state: AppContentState, action: (() -> Void)? = nil) {
        self.state = state
        self.action = action
    }

    var body: some View {
        Group {
            if state == .loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(state.title)
                        .font(.headline)
                    Text(state.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            } else {
                ContentUnavailableView {
                    Label(state.title, systemImage: state.systemImage)
                } description: {
                    Text(state.message)
                } actions: {
                    if let actionTitle = state.actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview("无数据") {
    AppStatusView(state: .noData) {}
}

#Preview("读取失败") {
    AppStatusView(state: .failed) {}
}
