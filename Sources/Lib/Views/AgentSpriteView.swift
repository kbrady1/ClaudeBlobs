import SwiftUI

struct AgentSpriteView: View {
    let status: AgentStatus
    let size: CGFloat
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(status.color)
                .frame(width: size, height: size)
            faceView
                .frame(width: size * 0.7, height: size * 0.5)
        }
        .offset(y: animationOffset)
        .onAppear { startAnimation() }
    }

    @ViewBuilder
    private var faceView: some View {
        switch status {
        case .waiting:    WaitingFace()
        case .permission: PermissionFace()
        case .working:    WorkingFace()
        case .starting:   StartingFace()
        }
    }

    private var animationOffset: CGFloat {
        switch status {
        case .permission: return -animationPhase * size * 0.15
        case .waiting:    return -animationPhase * size * 0.08
        default:          return 0
        }
    }

    private func startAnimation() {
        switch status {
        case .permission:
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .waiting:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .working:
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .starting:
            withAnimation(.easeOut(duration: 0.5)) {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Waiting Face (°□°): wide circle eyes + open square mouth

private struct WaitingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.14
            let eyeY = h * 0.25

            ZStack {
                // Left eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28, y: eyeY)

                // Right eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72, y: eyeY)

                // Open square mouth
                RoundedRectangle(cornerRadius: w * 0.04)
                    .fill(.black)
                    .frame(width: w * 0.38, height: h * 0.34)
                    .position(x: w * 0.5, y: h * 0.73)
            }
        }
    }
}

// MARK: - Permission Face (ò_ó): angled eyebrows + circle eyes + flat tense mouth

private struct PermissionFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.11

            ZStack {
                // Left angled eyebrow (slopes down toward center)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.12))
                    path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.22))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))

                // Right angled eyebrow (slopes down toward center)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.88, y: h * 0.12))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.22))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))

                // Left eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28, y: h * 0.44)

                // Right eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72, y: h * 0.44)

                // Flat tense mouth (short horizontal line)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.30, y: h * 0.82))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.82))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))
            }
        }
    }
}

// MARK: - Working Face (•_•): small dot eyes + flat line mouth

private struct WorkingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.08

            ZStack {
                // Left dot eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28, y: h * 0.30)

                // Right dot eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72, y: h * 0.30)

                // Flat line mouth
                Path { path in
                    path.move(to: CGPoint(x: w * 0.28, y: h * 0.75))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.75))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))
            }
        }
    }
}

// MARK: - Starting Face (^‿^): chevron eyes + arc smile

private struct StartingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Left chevron eye (^)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.14, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.38))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round, lineJoin: .round))

                // Right chevron eye (^)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.38))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round, lineJoin: .round))

                // Arc smile (‿)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.18, y: h * 0.65))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.82, y: h * 0.65),
                        control: CGPoint(x: w * 0.50, y: h * 1.05)
                    )
                }
                .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))
            }
        }
    }
}
