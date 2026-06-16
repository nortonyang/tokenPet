import SwiftUI
import Combine

public struct PetView: View {
    @ObservedObject var stateManager = PetStateManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var processMonitor = ProcessMonitor.shared
    
    // Animation States
    @State private var floatOffset: CGFloat = 0
    @State private var blinkScaleY: CGFloat = 1.0
    @State private var typingOffsetL: CGFloat = 0
    @State private var typingOffsetR: CGFloat = 0
    @State private var jumpOffset: CGFloat = 0
    @State private var jumpScaleY: CGFloat = 1.0
    @State private var shiverOffset: CGFloat = 0
    @State private var dizzyRotation: Double = 0
    @State private var sweatOffset: CGFloat = -15
    @State private var sweatOpacity: Double = 0
    
    // Mouse Look States
    @State private var headLookOffset: CGSize = .zero
    @State private var eyeLookOffset: CGSize = .zero
    
    // Timers
    private let blinkTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    private let lookTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Background is completely transparent
            
            VStack(spacing: 0) {
                // Dizzy spirals for error state
                if stateManager.currentState == .error {
                    DizzySpiralsView(rotation: dizzyRotation)
                        .frame(height: 20)
                        .offset(y: 10)
                } else {
                    Spacer().frame(height: 20)
                }
                
                // Character Container
                ZStack {
                    // Shadows
                    Ellipse()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 80, height: 10)
                        .scaleEffect(stateManager.currentState == .working ? 0.9 : 1.0)
                        .scaleEffect(1.0 - (jumpOffset / -100.0))
                        .offset(y: 50)
                    
                    // Main Character body
                    VStack(spacing: -12) {
                        // Head structure
                        ZStack {
                            // Antenna
                            AntennaView(color: mainColor, state: stateManager.currentState)
                                .offset(y: -42)
                            
                            // Head shape
                            RoundedRectangle(cornerRadius: 32)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [mainColor.opacity(0.85), mainColor]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                )
                                .shadow(color: glowColor.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            // Screen / Face visor
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color(red: 0.1, green: 0.11, blue: 0.15))
                                .frame(width: 84, height: 64)
                                .overlay(
                                    // Visor stroke
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(glowColor.opacity(0.3), lineWidth: 1.5)
                                )
                            
                            // Eyes
                            HStack(spacing: 20) {
                                EyeView(state: stateManager.currentState, blinkScaleY: blinkScaleY, eyeGlowColor: glowColor, isLeft: true)
                                EyeView(state: stateManager.currentState, blinkScaleY: blinkScaleY, eyeGlowColor: glowColor, isLeft: false)
                            }
                            .offset(y: -2)
                            .offset(eyeLookOffset)
                            
                            // Sweat drops for Warning state
                            if stateManager.currentState == .warning {
                                SweatDropView(offsetY: sweatOffset, opacity: sweatOpacity)
                                    .offset(x: -35, y: -10)
                                SweatDropView(offsetY: sweatOffset + 10, opacity: sweatOpacity)
                                    .offset(x: 35, y: -5)
                            }
                        }
                        .offset(headLookOffset)
                        .zIndex(2)
                        
                        // Body structure
                        ZStack {
                            // Body shape
                            Ellipse()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [mainColor.opacity(0.9), mainColor.opacity(0.7)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 72, height: 50)
                                .overlay(
                                    Ellipse()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 3)
                            
                            // Screen Chest Indicator
                            Circle()
                                .fill(indicatorColor)
                                .frame(width: 12, height: 12)
                                .shadow(color: indicatorColor, radius: 4)
                                .offset(y: -4)
                        }
                        .zIndex(1)
                    }
                    .scaleEffect(y: jumpScaleY)
                    .offset(x: shiverOffset, y: floatOffset + jumpOffset)
                    
                    // Floating hands
                    HandsView(
                        state: stateManager.currentState,
                        floatOffset: floatOffset,
                        jumpOffset: jumpOffset,
                        typingOffsetL: typingOffsetL,
                        typingOffsetR: typingOffsetR,
                        handColor: mainColor
                    )
                    
                    // Laptop/Keyboard for Working state
                    if stateManager.currentState == .working {
                        MiniLaptopView(glow: glowColor)
                            .offset(y: 40)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                    
                    // Signboard for Finished or Warning states
                    if stateManager.currentState == .finished {
                        SignboardView(text: "DONE!", color: .green)
                            .offset(x: 45, y: -20)
                            .transition(.scale.combined(with: .opacity))
                    } else if stateManager.currentState == .warning {
                        SignboardView(text: "WARN", color: .orange)
                            .offset(x: 45, y: -20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 160, height: 130)
                
                Spacer().frame(height: 10)
            }
        }
        .onAppear {
            startLoopAnimations()
        }
        .onReceive(blinkTimer) { _ in
            triggerBlink()
        }
        .onReceive(lookTimer) { _ in
            updateLookOffset()
        }
        .onChange(of: stateManager.currentState) { _, newState in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                resetAndApplyAnimations(for: newState)
            }
        }
        .scaleEffect(settings.petSize)
    }
    
    // Dynamic Colors based on states
    private var mainColor: Color {
        switch stateManager.currentState {
        case .idle: return Color(red: 0.9, green: 0.93, blue: 0.98) // Soft metallic white
        case .working:
            if processMonitor.isGeminiRunning && !processMonitor.isCodexRunning && !processMonitor.isClaudeRunning {
                return Color(red: 0.8, green: 0.88, blue: 1.0) // Gemini Light Blue
            } else if processMonitor.isCodexRunning && !processMonitor.isGeminiRunning && !processMonitor.isClaudeRunning {
                return Color(red: 0.88, green: 0.82, blue: 0.98) // Codex Purple
            } else if processMonitor.isClaudeRunning && !processMonitor.isGeminiRunning && !processMonitor.isCodexRunning {
                return Color(red: 1.0, green: 0.88, blue: 0.8) // Claude Orange
            } else {
                return Color(red: 0.82, green: 0.95, blue: 0.92) // Mixed Teal
            }
        case .finished: return Color(red: 0.88, green: 0.97, blue: 0.9) // Soft mint green
        case .warning: return Color(red: 1.0, green: 0.94, blue: 0.82) // Soft yellow/orange
        case .error: return Color(red: 1.0, green: 0.85, blue: 0.85) // Reddish tint
        }
    }
    
    private var glowColor: Color {
        switch stateManager.currentState {
        case .idle: return Color(red: 0.35, green: 0.65, blue: 1.0) // Cyan-blue
        case .working:
            if processMonitor.isGeminiRunning && !processMonitor.isCodexRunning && !processMonitor.isClaudeRunning {
                return Color(red: 0.0, green: 0.5, blue: 1.0) // Gemini Blue
            } else if processMonitor.isCodexRunning && !processMonitor.isGeminiRunning && !processMonitor.isClaudeRunning {
                return Color(red: 0.6, green: 0.3, blue: 0.9) // Codex Purple
            } else if processMonitor.isClaudeRunning && !processMonitor.isGeminiRunning && !processMonitor.isCodexRunning {
                return Color(red: 1.0, green: 0.45, blue: 0.1) // Claude Orange
            } else {
                return Color(red: 0.0, green: 0.7, blue: 0.6) // Mixed Cyan/Teal
            }
        case .finished: return Color(red: 0.15, green: 0.75, blue: 0.3) // Bright green
        case .warning: return Color(red: 1.0, green: 0.53, blue: 0.0) // Vivid orange
        case .error: return Color(red: 0.95, green: 0.1, blue: 0.1) // Bright red
        }
    }
    
    private var indicatorColor: Color {
        switch stateManager.currentState {
        case .idle: return Color.green
        case .working:
            if processMonitor.isGeminiRunning && !processMonitor.isCodexRunning && !processMonitor.isClaudeRunning {
                return Color.blue
            } else if processMonitor.isCodexRunning && !processMonitor.isGeminiRunning && !processMonitor.isClaudeRunning {
                return Color.purple
            } else if processMonitor.isClaudeRunning && !processMonitor.isGeminiRunning && !processMonitor.isCodexRunning {
                return Color.orange
            } else {
                return Color.teal
            }
        case .finished: return Color.green
        case .warning: return Color.orange
        case .error: return Color.red
        }
    }
    
    // Animations Trigger Setup
    private func startLoopAnimations() {
        // Continuous gentle breathing/floating
        withAnimation(Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            floatOffset = -6
        }
        
        resetAndApplyAnimations(for: stateManager.currentState)
    }
    
    private func triggerBlink() {
        guard stateManager.currentState == .idle || stateManager.currentState == .warning else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            blinkScaleY = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.1)) {
                self.blinkScaleY = 1.0
            }
        }
    }
    
    private func updateLookOffset() {
        let mouseLoc = NSEvent.mouseLocation
        let winX = settings.windowPositionX ?? 0.0
        let winY = settings.windowPositionY ?? 0.0
        
        let petCenterX = winX + 100.0
        let petCenterY = winY + 100.0
        
        let dx = mouseLoc.x - petCenterX
        let dy = mouseLoc.y - petCenterY
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance > 10 {
            let divisor = distance + 150.0
            
            // Max head displacement: dx: ±8, dy: ±6
            let targetHeadX = 8.0 * dx / divisor
            let targetHeadY = 6.0 * dy / divisor
            
            // Max eye displacement: dx: ±6, dy: ±4.5 (relative to head)
            let targetEyeX = 6.0 * dx / divisor
            let targetEyeY = 4.5 * dy / divisor
            
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                self.headLookOffset = CGSize(width: targetHeadX, height: targetHeadY)
                self.eyeLookOffset = CGSize(width: targetEyeX, height: targetEyeY)
            }
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                self.headLookOffset = .zero
                self.eyeLookOffset = .zero
            }
        }
    }
    
    private func resetAndApplyAnimations(for state: PetVisualState) {
        // Reset everything
        typingOffsetL = 0
        typingOffsetR = 0
        jumpOffset = 0
        jumpScaleY = 1.0
        shiverOffset = 0
        dizzyRotation = 0
        sweatOffset = -15
        sweatOpacity = 0
        
        switch state {
        case .working:
            // Continuous rapid typing hands animation speed customized by tool
            let speed: Double
            if processMonitor.isGeminiRunning && !processMonitor.isCodexRunning && !processMonitor.isClaudeRunning {
                speed = 0.12 // Gemini rapid typing
            } else if processMonitor.isCodexRunning && !processMonitor.isGeminiRunning && !processMonitor.isClaudeRunning {
                speed = 0.16 // Codex steady typing
            } else if processMonitor.isClaudeRunning && !processMonitor.isGeminiRunning && !processMonitor.isCodexRunning {
                speed = 0.08 // Claude extremely fast typing
            } else {
                speed = 0.10 // Mixed/others moderate typing
            }
            
            withAnimation(Animation.linear(duration: speed).repeatForever(autoreverses: true)) {
                typingOffsetL = -6
            }
            withAnimation(Animation.linear(duration: speed).repeatForever(autoreverses: true).delay(speed / 2.0)) {
                typingOffsetR = -6
            }
            
        case .finished:
            // Joyful jumping loop
            withAnimation(Animation.interpolatingSpring(stiffness: 120, damping: 8).repeatForever(autoreverses: false)) {
                jumpOffset = -20
            }
            // Squash and stretch
            withAnimation(Animation.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                jumpScaleY = 0.85
            }
            
        case .warning:
            // Shivering/nervous
            withAnimation(Animation.linear(duration: 0.1).repeatForever(autoreverses: true)) {
                shiverOffset = 2
            }
            // Sweat sliding down
            withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                sweatOffset = 15
                sweatOpacity = 0.8
            }
            
        case .error:
            // Spin spirals
            withAnimation(Animation.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                dizzyRotation = 360
            }
            
        case .idle:
            break
        }
    }
}

// Subview Components

struct EyeView: View {
    let state: PetVisualState
    let blinkScaleY: CGFloat
    let eyeGlowColor: Color
    let isLeft: Bool
    
    @ObservedObject var processMonitor = ProcessMonitor.shared
    
    private var activeLetters: [String] {
        var letters: [String] = []
        if processMonitor.isGeminiRunning { letters.append("G") }
        if processMonitor.isCodexRunning { letters.append("C") }
        if processMonitor.isClaudeRunning { letters.append("A") }
        return letters
    }
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                Circle()
                    .fill(eyeGlowColor)
                    .frame(width: 14, height: 14)
                    .scaleEffect(y: blinkScaleY)
                    .shadow(color: eyeGlowColor, radius: 4)
                
            case .working:
                if activeLetters.isEmpty {
                    // Fallback to focused squint if in working state but monitor not updated yet
                    RoundedRectangle(cornerRadius: 3)
                        .fill(eyeGlowColor)
                        .frame(width: 16, height: 8)
                        .shadow(color: eyeGlowColor, radius: 5)
                } else {
                    Text(activeLetters.count == 1 ? activeLetters[0] : (isLeft ? activeLetters[0] : activeLetters[activeLetters.count - 1]))
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(eyeGlowColor)
                        .shadow(color: eyeGlowColor, radius: 5)
                        .scaleEffect(1.1)
                }
                
            case .finished:
                // Happy curved eyes ^ ^
                Text("^")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(eyeGlowColor)
                    .scaleEffect(x: 1.2, y: 0.8)
                    .shadow(color: eyeGlowColor, radius: 3)
                
            case .warning:
                // Slanted worried ellipses (mirrored rotation)
                Ellipse()
                    .fill(eyeGlowColor)
                    .frame(width: 14, height: 10)
                    .rotationEffect(.degrees(isLeft ? 10 : -10))
                    .scaleEffect(y: blinkScaleY)
                    .shadow(color: eyeGlowColor, radius: 4)
                
            case .error:
                // Dead eyes X X
                Text("×")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(eyeGlowColor)
                    .offset(y: -4)
                    .shadow(color: eyeGlowColor, radius: 2)
            }
        }
    }
}

struct AntennaView: View {
    let color: Color
    let state: PetVisualState
    
    var body: some View {
        VStack(spacing: -2) {
            // Little dot at top
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .offset(y: state == .working ? 2 : 0)
            
            // Wire post
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 14)
        }
    }
}

struct HandsView: View {
    let state: PetVisualState
    let floatOffset: CGFloat
    let jumpOffset: CGFloat
    let typingOffsetL: CGFloat
    let typingOffsetR: CGFloat
    let handColor: Color
    
    var body: some View {
        ZStack {
            // Left Hand
            Circle()
                .fill(handColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.1), radius: 2)
                .offset(
                    x: -60,
                    y: state == .working
                        ? 22 + typingOffsetL
                        : 8 + floatOffset + (state == .finished ? jumpOffset * 0.5 : 0)
                )
            
            // Right Hand
            Circle()
                .fill(handColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.1), radius: 2)
                .offset(
                    x: 60,
                    y: state == .working
                        ? 22 + typingOffsetR
                        : 8 + floatOffset + (state == .finished ? -10 + jumpOffset * 0.5 : 0)
                )
        }
    }
}

struct MiniLaptopView: View {
    let glow: Color
    
    @ObservedObject var processMonitor = ProcessMonitor.shared
    
    var body: some View {
        ZStack {
            // Keyboard deck
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.2, green: 0.22, blue: 0.27))
                .frame(width: 60, height: 8)
                .shadow(color: Color.black.opacity(0.2), radius: 2)
            
            // Laptop screen
            Path { path in
                path.move(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 50, y: 0))
                path.addLine(to: CGPoint(x: 55, y: -26))
                path.addLine(to: CGPoint(x: 5, y: -26))
                path.closeSubpath()
            }
            .fill(Color(red: 0.15, green: 0.16, blue: 0.2))
            .shadow(color: glow.opacity(0.5), radius: 8)
            .overlay(
                // Coding lines representation inside the laptop screen
                VStack(alignment: .leading, spacing: 3) {
                    if processMonitor.isCodexRunning && !processMonitor.isGeminiRunning && !processMonitor.isClaudeRunning {
                        // Codex purple-themed coding lines
                        RoundedRectangle(cornerRadius: 1).fill(Color.purple).frame(width: 25, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.9, green: 0.5, blue: 0.9)).frame(width: 32, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color.blue).frame(width: 18, height: 2)
                    } else if processMonitor.isClaudeRunning && !processMonitor.isGeminiRunning && !processMonitor.isCodexRunning {
                        // Claude orange/yellow-themed coding lines
                        RoundedRectangle(cornerRadius: 1).fill(Color.orange).frame(width: 28, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color.yellow).frame(width: 20, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.9, green: 0.6, blue: 0.4)).frame(width: 25, height: 2)
                    } else {
                        // Gemini/Default cyan/blue coding lines
                        RoundedRectangle(cornerRadius: 1).fill(Color.cyan).frame(width: 25, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color.blue).frame(width: 32, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(Color.purple).frame(width: 18, height: 2)
                    }
                }
                .offset(x: -8, y: -18)
            )
        }
    }
}

struct SignboardView: View {
    let text: String
    let color: Color
    
    var body: some View {
        ZStack {
            // Stick
            Rectangle()
                .fill(Color.gray)
                .frame(width: 4, height: 24)
                .offset(y: 12)
            
            // Signboard board
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 50, height: 20)
                .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
            
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct DizzySpiralsView: View {
    let rotation: Double
    
    var body: some View {
        ZStack {
            Image(systemName: "circle.dotted")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.yellow)
                .rotationEffect(.degrees(rotation))
            
            Image(systemName: "circle.dotted")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .rotationEffect(.degrees(-rotation))
        }
    }
}

struct SweatDropView: View {
    let offsetY: CGFloat
    let opacity: Double
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 3, y: 10))
            path.addQuadCurve(to: CGPoint(x: 3, y: 0), control: CGPoint(x: 1.5, y: 5))
            path.addQuadCurve(to: CGPoint(x: 3, y: 10), control: CGPoint(x: 4.5, y: 5))
            path.addEllipse(in: CGRect(x: 0, y: 8, width: 6, height: 6))
        }
        .fill(Color(red: 0.4, green: 0.7, blue: 1.0))
        .frame(width: 6, height: 14)
        .offset(y: offsetY)
        .opacity(opacity)
    }
}
