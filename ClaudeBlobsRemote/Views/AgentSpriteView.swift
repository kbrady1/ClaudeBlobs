// ClaudeBlobsRemote/Views/AgentSpriteView.swift
// iOS port of the macOS AgentSpriteView blob rendering
import SwiftUI
import UIKit
import Combine

struct AgentSpriteView: View {
    let status: AgentStatus
    let size: CGFloat
    var isSnoozed: Bool = false
    var prominentStateChangesEnabled: Bool = true
    var isCoding: Bool = false
    var isSearching: Bool = false
    var isExploring: Bool = false
    var isMcpTool: Bool = false
    var isTesting: Bool = false
    var isDone: Bool = false
    var hasNotified: Bool = false
    var staleness: AgentStaleness = .active
    var isPlanApproval: Bool = false
    var isAskingQuestion: Bool = false
    var isBashPermission: Bool = false
    var isFilePermission: Bool = false
    var isWebPermission: Bool = false
    var isMcpPermission: Bool = false
    var isGithubPermission: Bool = false
    var isGithubTool: Bool = false
    var isTaskJustCompleted: Bool = false
    var isInterrupted: Bool = false
    var isToolFailure: Bool = false
    var isAPIError: Bool = false
    var appIconData: Data? = nil
    var appIconShowsBorder: Bool = false

    @State private var animationPhase: CGFloat = 0
    @State private var expressionFrame: Int = 0
    @State private var expressionTimer: AnyCancellable?
    @State private var bounceTimer: AnyCancellable?
    @State private var isShowingCheckmark: Bool = false
    @State private var checkmarkTimer: AnyCancellable?
    @State private var showingFailureIcon: String?
    @State private var failureIconTimer: AnyCancellable?
    @State private var showExploringAccent: Bool = false
    @State private var exploringTimer: AnyCancellable?
    @State private var winkResetTimer: AnyCancellable?
    @State private var waveAngle: Double = 0
    @State private var compactSquished: Bool = false
    @State private var compactTimer: AnyCancellable?
    @State private var prominentScale: CGFloat = 1.0
    @State private var prominentWiggle: Double = 0
    @State private var prominentOffsetY: CGFloat = 0

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

            // Permission sub-type accent
            if !isSnoozed && status == .permission {
                permissionIconOverlay
            }

            // Tool failure / interrupt accent
            if let icon = showingFailureIcon {
                Image(systemName: icon)
                    .font(.system(size: accentFont, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
                    .offset(x: size * 0.35, y: size * 0.35)
                    .transition(.scale.combined(with: .opacity))
            }

            // API error fire on head
            if isAPIError && !isSnoozed {
                FireOverlay(size: size)
                    .offset(y: -size * 0.55)
            }

            // Purple notification badge
            if hasNotified {
                Circle()
                    .fill(Color.purple)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .offset(x: size * 0.35, y: -size * 0.35)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let appIconData {
                AppIconAccent(iconData: appIconData, size: size, showsBorder: appIconShowsBorder)
            }
        }
        .rotationEffect(.degrees(waveAngle + prominentWiggle))
        .scaleEffect(prominentScale)
        .offset(y: prominentOffsetY)
        .saturation(staleness == .hung ? 0 : 1)
        .scaleEffect(
            x: compactSquished ? 1.3 : 1.0,
            y: compactSquished ? 0.5 : 1.0
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.4), value: compactSquished)
        .offset(y: animationOffset)
        .onAppear {
            startBounceTimer()
            startExpressionTimer()
            startCompactTimer()
            if isExploring {
                showExploringAccent = true
                exploringTimer?.cancel()
                exploringTimer = Timer.publish(every: 30.0, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { _ in
                        showExploringAccent = false
                    }
            }
        }
        .onDisappear {
            expressionTimer?.cancel()
            bounceTimer?.cancel()
            checkmarkTimer?.cancel()
            failureIconTimer?.cancel()
            exploringTimer?.cancel()
            compactTimer?.cancel()
        }
        .onChange(of: isSnoozed) { _ in
            expressionFrame = 0
            startBounceTimer()
            startExpressionTimer()
        }
        .onChange(of: status) { newStatus in
            startBounceTimer()
            startCompactTimer()
            if newStatus == .starting || (newStatus == .waiting && isDone) {
                playWave()
            }
            if prominentStateChangesEnabled && newStatus != .working && newStatus != .compacting {
                playProminentPop()
            }
        }
        .onChange(of: isDone) { done in
            if done && status == .waiting {
                playWave()
            }
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
        .onChange(of: isInterrupted) { interrupted in
            if interrupted {
                showFailureIcon("hand.raised.fill")
            }
        }
        .onChange(of: isToolFailure) { failed in
            if failed {
                showFailureIcon("exclamationmark.triangle.fill")
            }
        }
        .onChange(of: isExploring) { exploring in
            if exploring {
                showExploringAccent = true
                exploringTimer?.cancel()
                exploringTimer = Timer.publish(every: 30.0, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { _ in
                        showExploringAccent = false
                    }
            } else {
                exploringTimer?.cancel()
                showExploringAccent = false
            }
        }
    }

    private var backgroundColor: Color {
        if isSnoozed { return .gray }
        if status == .waiting && isDone {
            return .blue  // starting color
        }
        if status == .permission && isPlanApproval {
            return Color.orange
        }
        if status == .permission && isAskingQuestion {
            return Color.orange
        }
        return statusColor
    }

    /// Maps status to color (simplified from macOS ColorTheme, uses trafficLight defaults)
    private var statusColor: Color {
        switch status {
        case .starting:   return .blue
        case .working:    return .green
        case .permission: return .red
        case .waiting:    return .purple
        case .compacting: return .yellow
        }
    }

    private var isStale: Bool { staleness == .stale || staleness == .hung }

    @ViewBuilder
    private var faceView: some View {
        if isShowingCheckmark {
            CheckmarkFace()
                .transition(.opacity)
        } else if isAPIError && !isSnoozed {
            ScreamingFace(frame: expressionFrame)
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
    private var permissionIconOverlay: some View {
        let offset = size * 0.35
        if isGithubPermission {
            githubAccentIcon
                .offset(x: offset, y: offset)
        } else {
            let icon: String? = {
                if isPlanApproval { return "checkmark.bubble.fill" }
                if isAskingQuestion { return "questionmark.bubble.fill" }
                if isBashPermission { return "chevron.forward.square.fill" }
                if isFilePermission { return "pencil" }
                if isWebPermission { return "globe" }
                if isMcpPermission { return "point.3.filled.connected.trianglepath.dotted" }
                return nil
            }()
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: accentFont, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
                    .offset(x: offset, y: offset)
            }
        }
    }

    private var githubAccentIcon: some View {
        let iconSize = accentFont * 1.43
        return GitLogoShape()
            .fill(.white, style: FillStyle(eoFill: true))
            .shadow(color: .black, radius: 2)
            .frame(width: iconSize, height: iconSize)
    }

    @ViewBuilder
    private var workingIconOverlay: some View {
        let offset = size * 0.35
        if isTesting {
            Image(systemName: "checklist")
                .font(.system(size: accentFont, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: offset, y: offset)
        } else if isGithubTool {
            githubAccentIcon
                .offset(x: offset, y: offset)
        } else if isMcpTool {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: accentFont, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .offset(x: offset, y: offset)
        } else if isCoding {
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
        } else if isExploring && showExploringAccent {
            Image(systemName: "magnifyingglass")
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
            withAnimation(.easeOut(duration: 0.5)) {
                animationPhase = 0
            }
            return
        }
        let anim = bounceAnimation
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

    private func startCompactTimer() {
        compactTimer?.cancel()
        guard status == .compacting else {
            compactSquished = false
            return
        }
        compactSquished = true
        compactTimer = Timer.publish(every: 0.7, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                compactSquished.toggle()
            }
    }

    private func startExpressionTimer() {
        expressionTimer?.cancel()
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

    private func playWave() {
        waveAngle = 0
        withAnimation(.easeInOut(duration: 0.12)) { waveAngle = 15 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.12)) { waveAngle = -12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.easeInOut(duration: 0.12)) { waveAngle = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeInOut(duration: 0.15)) { waveAngle = 0 }
        }
    }

    private func playProminentPop() {
        prominentScale = 1.0
        prominentWiggle = 0
        prominentOffsetY = 0
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            prominentScale = 1.5
            prominentOffsetY = size * 0.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.08)) { prominentWiggle = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            withAnimation(.easeInOut(duration: 0.08)) { prominentWiggle = -10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
            withAnimation(.easeInOut(duration: 0.08)) { prominentWiggle = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.39) {
            withAnimation(.easeInOut(duration: 0.08)) { prominentWiggle = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.47) {
            withAnimation(.easeInOut(duration: 0.08)) { prominentWiggle = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                prominentScale = 1.0
                prominentOffsetY = 0
            }
        }
    }

    private func showFailureIcon(_ icon: String) {
        failureIconTimer?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showingFailureIcon = icon
        }
        failureIconTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingFailureIcon = nil
                }
            }
    }

    private func scheduleWinkReset() {
        winkResetTimer?.cancel()
        winkResetTimer = Timer.publish(every: 0.35, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    expressionFrame = 0
                }
            }
    }

    private func advanceExpression() {
        winkResetTimer?.cancel()
        if isSnoozed {
            expressionFrame = (expressionFrame + 1) % 3
            return
        }
        switch status {
        case .starting:
            let roll = Int.random(in: 0..<10)
            if roll < 6 { expressionFrame = 0 }
            else if roll < 8 { expressionFrame = 1; scheduleWinkReset() }
            else { expressionFrame = 2; scheduleWinkReset() }
        case .waiting:
            if isDone {
                let roll = Int.random(in: 0..<10)
                if roll < 7 { expressionFrame = 0 }
                else { expressionFrame = 1; scheduleWinkReset() }
            } else {
                expressionFrame = (expressionFrame + 1) % 3
            }
        case .permission:
            expressionFrame = (expressionFrame + 1) % 3
        case .working, .compacting:
            expressionFrame = (expressionFrame + 1) % 4
        }
    }
}

// MARK: - App Icon Accent (bounces with blob)

private struct AppIconAccent: View {
    let iconData: Data
    let size: CGFloat
    let showsBorder: Bool

    var offset: CGFloat { size * (showsBorder ? 0.15 : 0.3) }

    var body: some View {
        let iconSize = showsBorder ? size * 0.47 : size * 0.7
        if let uiImage = UIImage(data: iconData) {
            Image(uiImage: uiImage)
                .interpolation(.high)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                .shadow(color: .black.opacity(0.5), radius: 1)
                .offset(x: -1 * offset, y: offset)
                .scaleEffect(x: showsBorder ? 1 : 0.8, y: showsBorder ? 1 : 0.8)
        }
    }
}

// MARK: - Git Logo Shape (from git-scm SVG, viewBox 0 0 24 24)

private struct GitLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.900941, y: h * 0.462881))
        path.addLine(to: CGPoint(x: w * 0.537103, y: h * 0.099052))
        path.addCurve(to: CGPoint(x: w * 0.461205, y: h * 0.099052), control1: CGPoint(x: w * 0.516154, y: h * 0.078094), control2: CGPoint(x: w * 0.482173, y: h * 0.078094))
        path.addLine(to: CGPoint(x: w * 0.385661, y: h * 0.174615))
        path.addLine(to: CGPoint(x: w * 0.481493, y: h * 0.270455))
        path.addCurve(to: CGPoint(x: w * 0.547061, y: h * 0.285728), control1: CGPoint(x: w * 0.503766, y: h * 0.262928), control2: CGPoint(x: w * 0.529304, y: h * 0.267980))
        path.addCurve(to: CGPoint(x: w * 0.562197, y: h * 0.351704), control1: CGPoint(x: w * 0.564909, y: h * 0.303593), control2: CGPoint(x: w * 0.569915, y: h * 0.329349))
        path.addLine(to: CGPoint(x: w * 0.654574, y: h * 0.444072))
        path.addCurve(to: CGPoint(x: w * 0.720550, y: h * 0.459226), control1: CGPoint(x: w * 0.676929, y: h * 0.436363), control2: CGPoint(x: w * 0.702703, y: h * 0.441342))
        path.addCurve(to: CGPoint(x: w * 0.720550, y: h * 0.549526), control1: CGPoint(x: w * 0.745490, y: h * 0.484157), control2: CGPoint(x: w * 0.745490, y: h * 0.524577))
        path.addCurve(to: CGPoint(x: w * 0.630214, y: h * 0.549526), control1: CGPoint(x: w * 0.695593, y: h * 0.574483), control2: CGPoint(x: w * 0.655181, y: h * 0.574483))
        path.addCurve(to: CGPoint(x: w * 0.616330, y: h * 0.480075), control1: CGPoint(x: w * 0.611460, y: h * 0.530753), control2: CGPoint(x: w * 0.606817, y: h * 0.503183))
        path.addLine(to: CGPoint(x: w * 0.530175, y: h * 0.393929))
        path.addLine(to: CGPoint(x: w * 0.530175, y: h * 0.620626))
        path.addCurve(to: CGPoint(x: w * 0.547061, y: h * 0.632697), control1: CGPoint(x: w * 0.536251, y: h * 0.623637), control2: CGPoint(x: w * 0.541992, y: h * 0.627646))
        path.addCurve(to: CGPoint(x: w * 0.547061, y: h * 0.723024), control1: CGPoint(x: w * 0.572001, y: h * 0.657637), control2: CGPoint(x: w * 0.572001, y: h * 0.698048))
        path.addCurve(to: CGPoint(x: w * 0.456752, y: h * 0.723024), control1: CGPoint(x: w * 0.522121, y: h * 0.747954), control2: CGPoint(x: w * 0.481683, y: h * 0.747954))
        path.addCurve(to: CGPoint(x: w * 0.456752, y: h * 0.632697), control1: CGPoint(x: w * 0.431813, y: h * 0.698048), control2: CGPoint(x: w * 0.431813, y: h * 0.657637))
        path.addCurve(to: CGPoint(x: w * 0.477674, y: h * 0.618758), control1: CGPoint(x: w * 0.462919, y: h * 0.626539), control2: CGPoint(x: w * 0.470057, y: h * 0.621878))
        path.addLine(to: CGPoint(x: w * 0.477674, y: h * 0.389966))
        path.addCurve(to: CGPoint(x: w * 0.456752, y: h * 0.376036), control1: CGPoint(x: w * 0.470057, y: h * 0.386856), control2: CGPoint(x: w * 0.462937, y: h * 0.382230))
        path.addCurve(to: CGPoint(x: w * 0.443013, y: h * 0.306223), control1: CGPoint(x: w * 0.437862, y: h * 0.357155), control2: CGPoint(x: w * 0.433318, y: h * 0.329422))
        path.addLine(to: CGPoint(x: w * 0.348532, y: h * 0.211734))
        path.addLine(to: CGPoint(x: w * 0.099045, y: h * 0.461194))
        path.addCurve(to: CGPoint(x: w * 0.099045, y: h * 0.537110), control1: CGPoint(x: w * 0.078096, y: h * 0.482170), control2: CGPoint(x: w * 0.078096, y: h * 0.516152))
        path.addLine(to: CGPoint(x: w * 0.462901, y: h * 0.900939))
        path.addCurve(to: CGPoint(x: w * 0.538799, y: h * 0.900939), control1: CGPoint(x: w * 0.483850, y: h * 0.921888), control2: CGPoint(x: w * 0.517823, y: h * 0.921888))
        path.addLine(to: CGPoint(x: w * 0.900941, y: h * 0.538797))
        path.addCurve(to: CGPoint(x: w * 0.900941, y: h * 0.462881), control1: CGPoint(x: w * 0.921909, y: h * 0.517839), control2: CGPoint(x: w * 0.921909, y: h * 0.483839))
        return path
    }
}

// MARK: - Stale X-Eyes (shared)

private struct StaleXEyes: View {
    let w: CGFloat
    let h: CGFloat
    let stroke: StrokeStyle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: w * 0.16, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.40, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.42))
        }
        .stroke(.black, style: stroke)

        Path { path in
            path.move(to: CGPoint(x: w * 0.60, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.42))
            path.move(to: CGPoint(x: w * 0.84, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.42))
        }
        .stroke(.black, style: stroke)
    }
}

// MARK: - Starting Face

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
                if frame == 1 {
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

                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.38))
                }
                .stroke(.black, style: stroke)
                }

                if frame == 2 {
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.18, y: h * 0.65))
                        path.addQuadCurve(
                            to: CGPoint(x: w * 0.82, y: h * 0.65),
                            control: CGPoint(x: w * 0.50, y: h * 1.05)
                        )
                    }
                    .stroke(.black, style: StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round))

                    Ellipse()
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.5))
                        .frame(width: w * 0.18, height: h * 0.18)
                        .position(x: w * 0.55, y: h * 0.92)
                } else {
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

// MARK: - Done Face

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
                if frame == 1 {
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

                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.38))
                }
                .stroke(.black, style: stroke)
                }

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

// MARK: - Waiting Face

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
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.31, y: h * 0.73))
                        path.addLine(to: CGPoint(x: w * 0.69, y: h * 0.73))
                    }
                    .stroke(.black, style: stroke)
                } else {
                    RoundedRectangle(cornerRadius: w * 0.04)
                        .fill(.black)
                        .frame(width: w * 0.38, height: h * 0.34)
                        .position(x: w * 0.5, y: h * 0.73)
                }
            }
        }
    }
}

// MARK: - Permission Face

private struct PermissionFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.11
            let browStroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)
            let browY: CGFloat = frame == 0 ? 0 : -h * 0.08

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.12 + browY))
                    path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.22 + browY))
                }
                .stroke(.black, style: browStroke)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.88, y: h * 0.12 + browY))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.22 + browY))
                }
                .stroke(.black, style: browStroke)

                if isStale {
                    StaleXEyes(w: w, h: h, stroke: browStroke)
                } else {
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28, y: h * 0.44)

                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72, y: h * 0.44)
                }

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

// MARK: - Working Face

private struct WorkingFace: View {
    let frame: Int
    var isStale: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeR = w * 0.08
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            let eyeShift: CGFloat = {
                switch frame {
                case 1: return -w * 0.06
                case 2: return  w * 0.06
                default: return 0
                }
            }()

            ZStack {
                if isStale {
                    StaleXEyes(w: w, h: h, stroke: stroke)
                } else {
                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.28 + eyeShift, y: h * 0.30)

                Circle()
                    .fill(.black)
                    .frame(width: eyeR * 2, height: eyeR * 2)
                    .position(x: w * 0.72 + eyeShift, y: h * 0.30)
                }

                if frame == 3 {
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

// MARK: - Compacting Face

private struct CompactingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            ZStack {
                Text("@")
                    .font(.system(size: max(4, w * 0.32), weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .position(x: w * 0.28, y: h * 0.30)

                Text("@")
                    .font(.system(size: max(4, w * 0.32), weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .position(x: w * 0.72, y: h * 0.30)

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

// MARK: - Checkmark Face

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

// MARK: - Screaming Face

private struct ScreamingFace: View {
    let frame: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let shake: CGFloat = frame % 2 == 0 ? -w * 0.03 : w * 0.03

            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.30, height: w * 0.30)
                    .position(x: w * 0.28 + shake, y: h * 0.25)

                Circle()
                    .fill(.white)
                    .frame(width: w * 0.10, height: w * 0.10)
                    .position(x: w * 0.22 + shake, y: h * 0.20)

                Circle()
                    .fill(.black)
                    .frame(width: w * 0.30, height: w * 0.30)
                    .position(x: w * 0.72 + shake, y: h * 0.25)

                Circle()
                    .fill(.white)
                    .frame(width: w * 0.10, height: w * 0.10)
                    .position(x: w * 0.66 + shake, y: h * 0.20)

                Ellipse()
                    .fill(.black)
                    .frame(width: w * 0.40, height: h * 0.35)
                    .position(x: w * 0.50 + shake, y: h * 0.75)
            }
        }
    }
}

// MARK: - Fire Overlay

private struct FireOverlay: View {
    let size: CGFloat

    @State private var opacities: [Double] = [1.0, 0.4, 0.7]
    @State private var timer: AnyCancellable?

    var body: some View {
        ZStack {
            let fireSize = size * 0.28
            let overlap = fireSize * 0.5
            Text("\u{1F525}").opacity(opacities[0]).offset(x: -overlap)
            Text("\u{1F525}").opacity(opacities[1])
            Text("\u{1F525}").opacity(opacities[2]).offset(x: overlap)
        }
        .font(.system(size: size * 0.28))
        .onAppear { startFlicker() }
        .onDisappear { timer?.cancel() }
    }

    private func startFlicker() {
        timer?.cancel()
        timer = Timer.publish(every: 0.4, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.35)) {
                    opacities = (0..<3).map { _ in Double.random(in: 0.3...1.0) }
                }
            }
    }
}

// MARK: - Snooze Face

private struct SnoozeFace: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = StrokeStyle(lineWidth: max(1, w * 0.055), lineCap: .round)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.42, y: h * 0.30),
                        control: CGPoint(x: w * 0.27, y: h * 0.42)
                    )
                }
                .stroke(.black, style: stroke)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.58, y: h * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.88, y: h * 0.30),
                        control: CGPoint(x: w * 0.73, y: h * 0.42)
                    )
                }
                .stroke(.black, style: stroke)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.35, y: h * 0.72))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.65, y: h * 0.72),
                        control: CGPoint(x: w * 0.50, y: h * 0.82)
                    )
                }
                .stroke(.black, style: stroke)

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
