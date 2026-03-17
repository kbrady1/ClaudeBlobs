import SwiftUI
import Combine

struct AgentSpriteView: View {
    let status: AgentStatus
    let size: CGFloat
    var isSnoozed: Bool = false
    var theme: ColorTheme = .trafficLight
    var isCoding: Bool = false
    var isSearching: Bool = false
    var isDone: Bool = false
    var hasNotified: Bool = false
    var staleness: AgentStaleness = .active
    var isPlanApproval: Bool = false
    var isAskingQuestion: Bool = false
    var isTaskJustCompleted: Bool = false

    @State private var animationPhase: CGFloat = 0
    @State private var expressionFrame: Int = 0
    @State private var expressionTimer: AnyCancellable?
    @State private var bounceTimer: AnyCancellable?
    @State private var isShowingCheckmark: Bool = false
    @State private var checkmarkTimer: AnyCancellable?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(backgroundColor)
                .frame(width: size, height: size)
            faceView
                .frame(width: size * 0.7, height: size * 0.5)

            // Icon overlay for working sub-type
            if !isSnoozed && status == .working {
                workingIconOverlay
            }

            // Plan acceptance accent
            if !isSnoozed && status == .permission && isPlanApproval {
                Image(systemName: "checkmark.bubble.fill")
                    .font(.system(size: accentFont, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
                    .offset(x: size * 0.35, y: size * 0.35)
            }

            // Question bubble accent
            if !isSnoozed && status == .permission && isAskingQuestion {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: accentFont, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
                    .offset(x: size * 0.35, y: size * 0.35)
            }

            // Purple notification badge
            if hasNotified {
                Circle()
                    .fill(Color.purple)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .offset(x: size * 0.35, y: -size * 0.35)
            }
        }
        .saturation(staleness == .hung ? 0 : 1)
        .scaleEffect(
            x: status == .compacting ? 1.3 : 1.0,
            y: status == .compacting ? 0.5 : 1.0
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: status == .compacting)
        .offset(y: animationOffset)
        .onAppear {
            startBounceTimer()
            startExpressionTimer()
        }
        .onDisappear {
            expressionTimer?.cancel()
            bounceTimer?.cancel()
            checkmarkTimer?.cancel()
        }
        .onChange(of: isSnoozed) { _ in
            expressionFrame = 0
            startBounceTimer()
            startExpressionTimer()
        }
        .onChange(of: status) { _ in
            startBounceTimer()
        }
        .onChange(of: isTaskJustCompleted) { completed in
            if completed {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isShowingCheckmark = true
                }
                checkmarkTimer?.cancel()
                checkmarkTimer = Timer.publish(every: 3.0, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isShowingCheckmark = false
                        }
                    }
            }
        }
    }

    private var backgroundColor: Color {
        if isSnoozed { return .gray }
        if status == .waiting && isDone {
            return AgentStatus.starting.color(for: theme)
        }
        if status == .permission && isPlanApproval {
            return Color.orange
        }
        if status == .permission && isAskingQuestion {
            return Color.orange
        }
        return status.color(for: theme)
    }

    private var isStale: Bool { staleness == .stale || staleness == .hung }

    @ViewBuilder
    private var faceView: some View {
        if isShowingCheckmark {
            CheckmarkFace()
                .transition(.opacity)
        } else if isSnoozed {
            SnoozeFace(phase: animationPhase)
        } else {
            switch status {
            case .waiting:
                if isDone {
                    DoneFace(frame: expressionFrame, isStale: isStale)
                } else {
                    WaitingFace(frame: expressionFrame, isStale: isStale)
                }
            case .permission:
                if isPlanApproval || isAskingQuestion {
                    WaitingFace(frame: expressionFrame, isStale: isStale)
                } else {
                    PermissionFace(frame: expressionFrame, isStale: isStale)
                }
            case .working:    WorkingFace(frame: expressionFrame, isStale: isStale)
            case .starting:   StartingFace(frame: expressionFrame, isStale: isStale)
            case .compacting: CompactingFace()
            }
        }
    }

    /// Accent icons are proportionally larger in collapsed view (small sizes).
    private var accentFont: CGFloat { size < 25 ? size * 0.50 : size * 0.32 }

    @ViewBuilder
    private var workingIconOverlay: some View {
        let offset = size * 0.35
        if isCoding {
            Image(systemName: "pencil")
                .font(.system(size: accentFont, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: offset, y: offset)
        } else if isSearching {
            Image(systemName: "globe")
                .font(.system(size: accentFont, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: offset, y: offset)
        } else {
            Image(systemName: "ellipsis.bubble.fill")
                .font(.system(size: accentFont, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: offset, y: offset)
        }
    }

    private var animationOffset: CGFloat {
        if isSnoozed { return 0 }
        switch status {
        case .permission: return animationPhase * size * 0.15
        case .waiting where !isDone: return animationPhase * size * 0.08
        default:          return 0
        }
    }

    private var bounceDuration: TimeInterval {
        if isSnoozed { return 1.5 }
        switch status {
        case .permission: return 0.35
        case .waiting:    return isDone ? 0 : 0.8
        case .working:    return 1.2
        case .starting:   return 0
        case .compacting: return 0
        }
    }

    private var bounceAnimation: Animation? {
        let duration = bounceDuration
        guard duration > 0 else { return .easeOut(duration: 0.5) }
        if status == .permission && !isSnoozed {
            return .easeOut(duration: 0.25)
        }
        return .easeInOut(duration: duration)
    }

    private func startBounceTimer() {
        bounceTimer?.cancel()
        let duration = bounceDuration
        guard duration > 0 else {
            // One-shot: just set to 0 (starting, done)
            withAnimation(.easeOut(duration: 0.5)) {
                animationPhase = 0
            }
            return
        }
        let anim = bounceAnimation
        // Kick off immediately — oscillate between -1 and 1 to bob above and below center
        withAnimation(anim) {
            animationPhase = animationPhase <= 0 ? 1 : -1
        }
        bounceTimer = Timer.publish(every: duration, on: .main, in: .common)
            .autoconnect()
            .sink { [self] _ in
                withAnimation(anim) {
                    animationPhase = animationPhase <= 0 ? 1 : -1
                }
            }
    }

    private func startExpressionTimer() {
        expressionTimer?.cancel()
        // Hung agents don't cycle expressions — static x-eyes
        if staleness == .hung { return }
        let interval: TimeInterval
        if isSnoozed {
            interval = 1.0
        } else {
            switch status {
            case .starting:   interval = 1.8
            case .waiting:    interval = isDone ? 2.5 : 1.5
            case .permission: interval = 1.8
            case .working:    interval = 1.2
            case .compacting: interval = 1.2
            }
        }
        expressionTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    advanceExpression()
                }
            }
    }

    private func advanceExpression() {
        if isSnoozed {
            expressionFrame = (expressionFrame + 1) % 3
            return
        }
        switch status {
        case .starting:
            // Mostly happy (0), occasionally wink (1) or tongue (2)
            let roll = Int.random(in: 0..<10)
            if roll < 6 { expressionFrame = 0 }
            else if roll < 8 { expressionFrame = 1 }
            else { expressionFrame = 2 }
        case .waiting:
            if isDone {
                // Mostly content (0), occasionally wink (1)
                let roll = Int.random(in: 0..<10)
                expressionFrame = roll < 7 ? 0 : 1
            } else {
                // Cycle: open eyes + open mouth (0), blink (1), mouth shut (2)
                expressionFrame = (expressionFrame + 1) % 3
            }
        case .permission:
            // Alternate: tense mouth (0), yelling (1), extra angry (2)
            expressionFrame = (expressionFrame + 1) % 3
        case .working, .compacting:
            // Cycle: center (0), look left (1), look right (2), thinking mouth (3)
            expressionFrame = (expressionFrame + 1) % 4
        }
    }
}

// MARK: - Stale X-Eyes (shared)

/// Draws two X marks where the eyes would be, used for stale/hung agents.
private struct StaleXEyes: View {
    let w: CGFloat
    let h: CGFloat
    let stroke: StrokeStyle

    var body: some View {
        // Left X
        Path { path in
            path.move(to: CGPoint(x: w * 0.16, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.40, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.42))
        }
        .stroke(.black, style: stroke)

        // Right X
        Path { path in
            path.move(to: CGPoint(x: w * 0.60, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.84, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.42))
        }
        .stroke(.black, style: stroke)
    }
}

// MARK: - Starting Face (^‿^): happy, sometimes winks or sticks tongue out

private struct StartingFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round, lineJoin: .round)

            ZStack {
                if isStale {
                    StaleXEyes(w: w, h: h, stroke: stroke)
                } else {
                // Left eye
                if frame == 1 {
                    // Wink: horizontal line for left eye
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.14, y: h * 0.28))
                        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.28))
                    }
                    .stroke(.black, style: stroke)
                } else {
                    // Normal chevron ^
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.14, y: h * 0.38))
                        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.18))
                        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.38))
                    }
                    .stroke(.black, style: stroke)
                }

                // Right eye: always chevron
                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.38))
                }
                .stroke(.black, style: stroke)
                } // end !isStale

                // Mouth
                if frame == 2 {
                    // Tongue out: smile + tongue
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.18, y: h * 0.65))
                        path.addQuadCurve(
                            to: CGPoint(x: w * 0.82, y: h * 0.65),
                            control: CGPoint(x: w * 0.50, y: h * 1.05)
                        )
                    }
                    .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))

                    // Tongue
                    Ellipse()
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.5))
                        .frame(width: w * 0.18, height: h * 0.18)
                        .position(x: w * 0.55, y: h * 0.92)
                } else {
                    // Normal arc smile
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
}

// MARK: - Done Face (^‿^): content, occasionally winks — used when agent is finished

private struct DoneFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round, lineJoin: .round)

            ZStack {
                if isStale {
                    StaleXEyes(w: w, h: h, stroke: stroke)
                } else {
                // Left eye
                if frame == 1 {
                    // Wink
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.14, y: h * 0.28))
                        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.28))
                    }
                    .stroke(.black, style: stroke)
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.14, y: h * 0.38))
                        path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.18))
                        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.38))
                    }
                    .stroke(.black, style: stroke)
                }

                // Right eye: always chevron
                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.38))
                }
                .stroke(.black, style: stroke)
                } // end !isStale

                // Smile
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

// MARK: - Waiting Face (°□°): blinks, mouth opens and shuts

private struct WaitingFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.14
            let eyeY = h * 0.25
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            ZStack {
                if isStale {
                    StaleXEyes(w: w, h: h, stroke: stroke)
                } else if frame == 1 {
                    // Blink: thin horizontal lines for eyes
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.14, y: eyeY))
                        path.addLine(to: CGPoint(x: w * 0.42, y: eyeY))
                    }
                    .stroke(.black, style: stroke)

                    Path { path in
                        path.move(to: CGPoint(x: w * 0.58, y: eyeY))
                        path.addLine(to: CGPoint(x: w * 0.86, y: eyeY))
                    }
                    .stroke(.black, style: stroke)
                } else {
                    // Open circle eyes
                    Circle()
                        .fill(.black)
                        .frame(width: eyeR * 2, height: eyeR * 2)
                        .position(x: w * 0.28, y: eyeY)

                    Circle()
                        .fill(.black)
                        .frame(width: eyeR * 2, height: eyeR * 2)
                        .position(x: w * 0.72, y: eyeY)
                }

                if frame == 2 {
                    // Mouth shut: flat line
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.31, y: h * 0.73))
                        path.addLine(to: CGPoint(x: w * 0.69, y: h * 0.73))
                    }
                    .stroke(.black, style: stroke)
                } else {
                    // Open square mouth
                    RoundedRectangle(cornerRadius: w * 0.04)
                        .fill(.black)
                        .frame(width: w * 0.38, height: h * 0.34)
                        .position(x: w * 0.5, y: h * 0.73)
                }
            }
        }
    }
}

// MARK: - Permission Face (ò_ó): yelling, raising eyebrows

private struct PermissionFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.11
            let browStroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            // Eyebrow raise amount: frame 1,2 raise higher
            let browY: CGFloat = frame == 0 ? 0 : -h * 0.08

            ZStack {
                // Left angled eyebrow
                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.12 + browY))
                    path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.22 + browY))
                }
                .stroke(.black, style: browStroke)

                // Right angled eyebrow
                Path { path in
                    path.move(to: CGPoint(x: w * 0.88, y: h * 0.12 + browY))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.22 + browY))
                }
                .stroke(.black, style: browStroke)

                if isStale {
                    StaleXEyes(w: w, h: h, stroke: browStroke)
                } else {
                // Eyes
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28, y: h * 0.44)

                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72, y: h * 0.44)
                } // end !isStale

                // Mouth — always an Ellipse to preserve view identity during bounce
                Ellipse()
                    .fill(.black)
                    .frame(
                        width: frame == 2 ? w * 0.40 : frame == 1 ? w * 0.32 : w * 0.40,
                        height: frame == 2 ? h * 0.28 : frame == 1 ? h * 0.22 : h * 0.06
                    )
                    .position(x: w * 0.5, y: h * 0.82)
            }
        }
    }
}

// MARK: - Working Face (•_•): looks around, thinks

private struct WorkingFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.08
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            // Eye horizontal offset based on frame
            let eyeShift: CGFloat = {
                switch frame {
                case 1: return -w * 0.06  // look left
                case 2: return  w * 0.06  // look right
                default: return 0          // center
                }
            }()

            ZStack {
                if isStale {
                    StaleXEyes(w: w, h: h, stroke: stroke)
                } else {
                // Left dot eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28 + eyeShift, y: h * 0.30)

                // Right dot eye
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72 + eyeShift, y: h * 0.30)
                } // end !isStale

                if frame == 3 {
                    // Thinking mouth: three dots
                    let dotR = w * 0.04
                    Circle().fill(.black)
                        .frame(width: dotR * 2, height: dotR * 2)
                        .position(x: w * 0.38, y: h * 0.75)
                    Circle().fill(.black)
                        .frame(width: dotR * 2, height: dotR * 2)
                        .position(x: w * 0.50, y: h * 0.75)
                    Circle().fill(.black)
                        .frame(width: dotR * 2, height: dotR * 2)
                        .position(x: w * 0.62, y: h * 0.75)
                } else {
                    // Flat line mouth
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.28, y: h * 0.75))
                        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.75))
                    }
                    .stroke(.black, style: stroke)
                }
            }
        }
    }
}

// MARK: - Compacting Face: squished dizzy look

private struct CompactingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            ZStack {
                // Dizzy spiral left eye
                Text("@")
                    .font(.system(size: max(4, w * 0.32), weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .position(x: w * 0.28, y: h * 0.30)

                // Dizzy spiral right eye
                Text("@")
                    .font(.system(size: max(4, w * 0.32), weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .position(x: w * 0.72, y: h * 0.30)

                // Wavy mouth
                Path { path in
                    path.move(to: CGPoint(x: w * 0.20, y: h * 0.75))
                    path.addCurve(
                        to: CGPoint(x: w * 0.80, y: h * 0.75),
                        control1: CGPoint(x: w * 0.35, y: h * 0.60),
                        control2: CGPoint(x: w * 0.65, y: h * 0.90)
                    )
                }
                .stroke(.black, style: stroke)
            }
        }
    }
}

// MARK: - Checkmark Face: task completed flash

private struct CheckmarkFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                path.move(to: CGPoint(x: w * 0.15, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.80))
                path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.15))
            }
            .stroke(.black, style: StrokeStyle(lineWidth: max(2, w * 0.10), lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Snooze Face: sleeping with floating Zzz

private struct SnoozeFace: View {
    let phase: CGFloat  // 0→1 oscillating

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            ZStack {
                // Closed left eye (horizontal arc, like ‿)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.42, y: h * 0.30),
                        control: CGPoint(x: w * 0.27, y: h * 0.42)
                    )
                }
                .stroke(.black, style: stroke)

                // Closed right eye
                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.88, y: h * 0.30),
                        control: CGPoint(x: w * 0.73, y: h * 0.42)
                    )
                }
                .stroke(.black, style: stroke)

                // Small peaceful mouth
                Path { path in
                    path.move(to: CGPoint(x: w * 0.35, y: h * 0.72))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.65, y: h * 0.72),
                        control: CGPoint(x: w * 0.50, y: h * 0.82)
                    )
                }
                .stroke(.black, style: stroke)

                // Floating Zzz
                ZzzOverlay(phase: phase, w: w, h: h)
            }
        }
    }
}

private struct ZzzOverlay: View {
    let phase: CGFloat
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        let baseX = w * 0.78
        let baseY = h * 0.05

        ZStack {
            Text("z")
                .font(.system(size: max(4, w * 0.18), weight: .bold))
                .foregroundColor(.black.opacity(0.7))
                .position(x: baseX, y: baseY - phase * h * 0.1)
                .opacity(1.0 - Double(phase) * 0.3)

            Text("z")
                .font(.system(size: max(3, w * 0.13), weight: .bold))
                .foregroundColor(.black.opacity(0.5))
                .position(x: baseX + w * 0.12, y: baseY - h * 0.15 - phase * h * 0.1)
                .opacity(0.7 - Double(phase) * 0.2)

            Text("z")
                .font(.system(size: max(2, w * 0.09), weight: .bold))
                .foregroundColor(.black.opacity(0.3))
                .position(x: baseX + w * 0.20, y: baseY - h * 0.26 - phase * h * 0.1)
                .opacity(0.5 - Double(phase) * 0.15)
        }
    }
}
