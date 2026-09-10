import SwiftUI

struct PrivacyDataFlowView: View {
    private let routes = PrivacyDataFlowCatalog.routes

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introductionCard
                    legend

                    Text("数据怎样流动")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(routes) { route in
                        routeCard(route)
                            .id(route.id)
                    }

                    userControlsCard
                        .id("user-controls")
                    commitmentsCard
                        .id("commitments")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .task {
#if DEBUG
                let prefix = "--privacy-flow-preview="
                if let argument = ProcessInfo.processInfo.arguments.first(where: {
                    $0.hasPrefix(prefix)
                }) {
                    let anchor = String(argument.dropFirst(prefix.count))
                    await Task.yield()
                    proxy.scrollTo(anchor, anchor: .top)
                }
#endif
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("隐私与数据流")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            Text(PrivacyDataFlowCatalog.headline)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(PrivacyDataFlowCatalog.introduction)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("边界图例")
                .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(PrivacyDataBoundary.allCases, id: \.self) { boundary in
                        boundaryBadge(boundary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(PrivacyDataBoundary.allCases, id: \.self) { boundary in
                        boundaryBadge(boundary)
                    }
                }
            }
        }
    }

    private func routeCard(_ route: PrivacyDataFlowRoute) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: route.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.title)
                        .font(.headline)
                    Text(route.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            statusBadge(route.exitKind)

            ForEach(Array(route.steps.enumerated()), id: \.element.id) { index, step in
                flowStep(step)
                if index < route.steps.count - 1 {
                    Image(systemName: "arrow.down")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            if !route.sharedData.isEmpty {
                detailGroup(
                    title: "会传递什么",
                    image: "arrow.up.right.circle",
                    color: .blue,
                    items: route.sharedData
                )
            }

            if !route.excludedData.isEmpty {
                detailGroup(
                    title: "明确不包含",
                    image: "nosign",
                    color: .secondary,
                    items: route.excludedData
                )
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func flowStep(_ step: PrivacyDataFlowStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(boundaryColor(step.boundary).opacity(0.13))
                Image(systemName: step.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(boundaryColor(step.boundary))
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                    Text(step.boundary.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(boundaryColor(step.boundary))
                }
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusBadge(_ exitKind: PrivacyDataExitKind) -> some View {
        Label(
            exitKind.title,
            systemImage: exitKind == .none ? "iphone" : "hand.tap.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(exitKind == .none ? .green : .blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (exitKind == .none ? Color.green : Color.blue).opacity(0.10),
            in: Capsule()
        )
    }

    private func boundaryBadge(_ boundary: PrivacyDataBoundary) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(boundaryColor(boundary))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(boundary.title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(boundaryColor(boundary).opacity(0.10), in: Capsule())
    }

    private func detailGroup(
        title: String,
        image: String,
        color: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: image)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var userControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你可以控制什么")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(PrivacyDataFlowCatalog.userControls) { control in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: control.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(control.title)
                            .font(.subheadline.weight(.semibold))
                        Text(control.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var commitmentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("知衡的当前承诺与边界", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.teal)
            ForEach(PrivacyDataFlowCatalog.commitments, id: \.self) { commitment in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.teal)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text(commitment)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func boundaryColor(_ boundary: PrivacyDataBoundary) -> Color {
        switch boundary {
        case .appleSystem: .pink
        case .onDevice: .green
        case .secureNetwork: .blue
        case .externalDestination: .orange
        }
    }
}
