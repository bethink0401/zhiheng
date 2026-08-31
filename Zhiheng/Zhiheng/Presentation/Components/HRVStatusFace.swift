import SwiftUI

struct HRVStatusFace: View {
    let state: HRVVisualState
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            context.fill(
                Path(ellipseIn: bounds),
                with: .linearGradient(
                    Gradient(colors: state.faceGradient),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )

            drawEyes(in: &context, size: canvasSize)
            drawMouth(in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private func drawEyes(in context: inout GraphicsContext, size: CGSize) {
        let stroke = GraphicsContext.Shading.color(.black)
        let lineWidth = max(size.width * 0.065, 2)
        let leftX = size.width * 0.36
        let rightX = size.width * 0.64

        switch state {
        case .abovePersonalRange:
            for centerX in [leftX, rightX] {
                var eye = Path()
                eye.move(to: CGPoint(x: centerX - size.width * 0.07, y: size.height * 0.43))
                eye.addQuadCurve(
                    to: CGPoint(x: centerX + size.width * 0.07, y: size.height * 0.43),
                    control: CGPoint(x: centerX, y: size.height * 0.51)
                )
                context.stroke(eye, with: stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        default:
            let eyeSize = size.width * 0.105
            context.fill(
                Path(ellipseIn: CGRect(
                    x: leftX - eyeSize / 2,
                    y: size.height * 0.43 - eyeSize / 2,
                    width: eyeSize,
                    height: eyeSize
                )),
                with: stroke
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: rightX - eyeSize / 2,
                    y: size.height * 0.43 - eyeSize / 2,
                    width: eyeSize,
                    height: eyeSize
                )),
                with: stroke
            )
        }

        guard state == .belowPersonalRange else { return }
        for (start, end) in [
            (CGPoint(x: size.width * 0.27, y: size.height * 0.28), CGPoint(x: size.width * 0.43, y: size.height * 0.33)),
            (CGPoint(x: size.width * 0.57, y: size.height * 0.33), CGPoint(x: size.width * 0.73, y: size.height * 0.28))
        ] {
            var eyebrow = Path()
            eyebrow.move(to: start)
            eyebrow.addLine(to: end)
            context.stroke(
                eyebrow,
                with: stroke,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square)
            )
        }
    }

    private func drawMouth(in context: inout GraphicsContext, size: CGSize) {
        var mouth = Path()
        let start = CGPoint(x: size.width * 0.31, y: size.height * 0.67)
        let end = CGPoint(x: size.width * 0.69, y: size.height * 0.67)
        mouth.move(to: start)

        switch state {
        case .belowPersonalRange:
            mouth.addQuadCurve(
                to: end,
                control: CGPoint(x: size.width * 0.5, y: size.height * 0.56)
            )
        case .nearPersonalRange, .abovePersonalRange:
            mouth.addQuadCurve(
                to: end,
                control: CGPoint(x: size.width * 0.5, y: size.height * 0.82)
            )
        case .learning, .unavailable:
            mouth.addLine(to: end)
        }

        context.stroke(
            mouth,
            with: .color(.black),
            style: StrokeStyle(lineWidth: max(size.width * 0.075, 2), lineCap: .round)
        )
    }
}

extension HRVVisualState {
    var accentColor: Color {
        switch self {
        case .belowPersonalRange: .orange
        case .nearPersonalRange: .blue
        case .abovePersonalRange: .teal
        case .learning, .unavailable: .secondary
        }
    }

    fileprivate var faceGradient: [Color] {
        switch self {
        case .belowPersonalRange: [.orange.opacity(0.72), .orange]
        case .nearPersonalRange: [.cyan.opacity(0.75), .blue.opacity(0.9)]
        case .abovePersonalRange: [.mint.opacity(0.72), .teal.opacity(0.9)]
        case .learning: [.indigo.opacity(0.22), .gray.opacity(0.45)]
        case .unavailable: [.gray.opacity(0.18), .gray.opacity(0.35)]
        }
    }

    fileprivate var accessibilityLabel: String {
        switch self {
        case .belowPersonalRange: "HRV 低于个人近期参考的表情"
        case .nearPersonalRange: "HRV 接近个人近期参考的表情"
        case .abovePersonalRange: "HRV 高于个人近期参考的表情"
        case .learning: "正在建立 HRV 个人参考的表情"
        case .unavailable: "暂无 HRV 数据的表情"
        }
    }
}
