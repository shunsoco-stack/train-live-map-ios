import SwiftUI

struct TrainIconView: View {
    let train: TrainLocation
    var isSelected = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var face: TrainFace {
        TrainPresentation.face(for: train)
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack(alignment: .top) {
                trainBody
                    .padding(.top, hasStatusBadge ? 13 : 0)

                if let text = TrainPresentation.suspensionBadgeText(for: train) {
                    speechBadge(
                        text,
                        color: Color(hex: "#2563eb"),
                        symbol: "!"
                    )
                } else if let text = TrainPresentation.delayBubbleText(for: train) {
                    speechBadge(
                        text,
                        color: Color(hex: "#be123c"),
                        symbol: nil
                    )
                }
            }

            Text(train.direction.displayText)
                .font(RailFont.extraBold(.caption2))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(directionColor, in: Capsule())
                .overlay {
                    Capsule().stroke(.white, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        }
        .frame(width: 78, height: 86)
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(
            reduceMotion ? nil : .spring(response: 0.25),
            value: isSelected
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrainPresentation.accessibilityLabel(for: train))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hasStatusBadge: Bool {
        TrainPresentation.delayBubbleText(for: train) != nil
            || TrainPresentation.suspensionBadgeText(for: train) != nil
    }

    private var directionColor: Color {
        switch train.direction {
        case .inbound: RailTheme.inboundBlue
        case .outbound: RailTheme.outboundOrange
        }
    }

    private var trainBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: train.lineColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white, lineWidth: isSelected ? 3 : 2)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.yellow, lineWidth: 3)
                            .padding(-4)
                    }
                }
                .shadow(
                    color: isSelected
                        ? Color.yellow.opacity(0.65)
                        : Color.black.opacity(0.38),
                    radius: isSelected ? 7 : 3,
                    y: 2
                )

            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(reduceTransparency ? 1 : 0.94))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(reduceTransparency ? 1 : 0.94))
                }
                .frame(height: 12)
                .padding(.horizontal, 7)
                .padding(.top, 5)

                TrainFaceView(face: face)
                    .frame(height: 23)

                HStack {
                    Circle().fill(Color.white)
                    Spacer()
                    Circle().fill(Color.white)
                }
                .frame(height: 5)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .frame(width: 52, height: 51)
    }

    private func speechBadge(
        _ text: String,
        color: Color,
        symbol: String?
    ) -> some View {
        VStack(spacing: -1) {
            HStack(spacing: 2) {
                if let symbol {
                    Text(symbol)
                        .font(RailFont.extraBold(.caption2))
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(RailFont.extraBold(.caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .overlay {
                Capsule().stroke(.white, lineWidth: 1.5)
            }

            SpeechPointer()
                .fill(color)
                .frame(width: 9, height: 5)
                .overlay {
                    SpeechPointer()
                        .stroke(.white, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .offset(y: -2)
    }
}

private struct SpeechPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct TrainFaceView: View {
    let face: TrainFace

    var body: some View {
        Canvas { context, size in
            let ink = Color(hex: "#2b1a10")
            let leftEye = CGRect(
                x: size.width * 0.25,
                y: size.height * 0.28,
                width: 4,
                height: 5
            )
            let rightEye = CGRect(
                x: size.width * 0.65,
                y: size.height * 0.28,
                width: 4,
                height: 5
            )

            context.fill(Path(ellipseIn: leftEye), with: .color(ink))
            context.fill(Path(ellipseIn: rightEye), with: .color(ink))

            switch face {
            case .smiling:
                var mouth = Path()
                mouth.move(
                    to: CGPoint(
                        x: size.width * 0.38,
                        y: size.height * 0.56
                    )
                )
                mouth.addQuadCurve(
                    to: CGPoint(
                        x: size.width * 0.62,
                        y: size.height * 0.56
                    ),
                    control: CGPoint(
                        x: size.width * 0.5,
                        y: size.height * 0.8
                    )
                )
                context.stroke(mouth, with: .color(ink), lineWidth: 2)

            case .troubled:
                context.stroke(
                    browsPath(size: size, inward: true),
                    with: .color(ink),
                    lineWidth: 2
                )
                context.stroke(
                    sadMouth(size: size),
                    with: .color(ink),
                    lineWidth: 2
                )

            case .sadWithTear:
                context.stroke(
                    browsPath(size: size, inward: false),
                    with: .color(ink),
                    lineWidth: 2
                )
                context.stroke(
                    sadMouth(size: size),
                    with: .color(ink),
                    lineWidth: 2
                )

                let tearColor = Color(hex: "#38bdf8")
                for xPosition in [0.29, 0.7] {
                    var tear = Path()
                    tear.move(
                        to: CGPoint(
                            x: size.width * xPosition,
                            y: size.height * 0.46
                        )
                    )
                    tear.addQuadCurve(
                        to: CGPoint(
                            x: size.width * xPosition,
                            y: size.height * 0.75
                        ),
                        control: CGPoint(
                            x: size.width * (xPosition + 0.09),
                            y: size.height * 0.63
                        )
                    )
                    tear.addQuadCurve(
                        to: CGPoint(
                            x: size.width * xPosition,
                            y: size.height * 0.46
                        ),
                        control: CGPoint(
                            x: size.width * (xPosition - 0.09),
                            y: size.height * 0.63
                        )
                    )
                    context.fill(tear, with: .color(tearColor))
                }
            }
        }
    }

    private func sadMouth(size: CGSize) -> Path {
        var mouth = Path()
        mouth.move(
            to: CGPoint(x: size.width * 0.39, y: size.height * 0.72)
        )
        mouth.addQuadCurve(
            to: CGPoint(x: size.width * 0.61, y: size.height * 0.72),
            control: CGPoint(x: size.width * 0.5, y: size.height * 0.52)
        )
        return mouth
    }

    private func browsPath(size: CGSize, inward: Bool) -> Path {
        var brows = Path()
        let innerY = inward ? size.height * 0.18 : size.height * 0.1
        let outerY = inward ? size.height * 0.1 : size.height * 0.18
        brows.move(to: CGPoint(x: size.width * 0.22, y: outerY))
        brows.addLine(to: CGPoint(x: size.width * 0.34, y: innerY))
        brows.move(to: CGPoint(x: size.width * 0.66, y: innerY))
        brows.addLine(to: CGPoint(x: size.width * 0.78, y: outerY))
        return brows
    }
}
