import SwiftUI

struct TrainIconView: View {
    let train: TrainLocation

    private var face: TrainFace {
        TrainPresentation.face(for: train)
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack(alignment: .top) {
                trainBody
                    .padding(.top, train.delayMinutes > 0 || train.status == .suspended ? 9 : 0)

                if train.status == .suspended {
                    statusBadge("見合わせ", color: Color(hex: "#2563eb"))
                        .offset(y: -1)
                } else if train.delayMinutes > 0 {
                    statusBadge("+\(train.delayMinutes)分", color: Color(hex: "#b91c1c"))
                        .offset(y: -1)
                }
            }

            Text(train.direction.displayText)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(.ultraThickMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.black.opacity(0.2), lineWidth: 0.5)
                }
        }
        .frame(width: 72, height: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrainPresentation.accessibilityLabel(for: train))
    }

    private var trainBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(hex: train.lineColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.92))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.92))
                }
                .frame(height: 12)
                .padding(.horizontal, 7)
                .padding(.top, 5)

                TrainFaceView(face: face)
                    .frame(height: 22)

                HStack {
                    Circle().fill(Color.white.opacity(0.95))
                    Spacer()
                    Circle().fill(Color.white.opacity(0.95))
                }
                .frame(height: 5)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .frame(width: 50, height: 49)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .overlay {
                Capsule().stroke(.white, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
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
                mouth.move(to: CGPoint(x: size.width * 0.38, y: size.height * 0.56))
                mouth.addQuadCurve(
                    to: CGPoint(x: size.width * 0.62, y: size.height * 0.56),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.8)
                )
                context.stroke(mouth, with: .color(ink), lineWidth: 2)

            case .troubled:
                context.stroke(
                    browsPath(size: size, inward: true),
                    with: .color(ink),
                    lineWidth: 2
                )
                var mouth = Path()
                mouth.move(to: CGPoint(x: size.width * 0.39, y: size.height * 0.72))
                mouth.addQuadCurve(
                    to: CGPoint(x: size.width * 0.61, y: size.height * 0.72),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.52)
                )
                context.stroke(mouth, with: .color(ink), lineWidth: 2)

            case .sadWithTear:
                context.stroke(
                    browsPath(size: size, inward: false),
                    with: .color(ink),
                    lineWidth: 2
                )
                var mouth = Path()
                mouth.move(to: CGPoint(x: size.width * 0.4, y: size.height * 0.72))
                mouth.addQuadCurve(
                    to: CGPoint(x: size.width * 0.6, y: size.height * 0.72),
                    control: CGPoint(x: size.width * 0.5, y: size.height * 0.53)
                )
                context.stroke(mouth, with: .color(ink), lineWidth: 2)

                var tear = Path()
                tear.move(to: CGPoint(x: size.width * 0.7, y: size.height * 0.46))
                tear.addQuadCurve(
                    to: CGPoint(x: size.width * 0.7, y: size.height * 0.72),
                    control: CGPoint(x: size.width * 0.79, y: size.height * 0.62)
                )
                tear.addQuadCurve(
                    to: CGPoint(x: size.width * 0.7, y: size.height * 0.46),
                    control: CGPoint(x: size.width * 0.61, y: size.height * 0.62)
                )
                context.fill(tear, with: .color(Color(hex: "#38bdf8")))
            }
        }
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
