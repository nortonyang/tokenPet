import SwiftUI

// MARK: - Agent Brand

public enum AgentBrand { case gemini, codex, claude }

// MARK: - Agent Logo Container

public struct AgentLogoView: View {
    let brand: AgentBrand
    var size: CGFloat = 36

    public var body: some View {
        ZStack {
            Circle()
                .fill(bgFill)
            Circle()
                .strokeBorder(strokeColor, lineWidth: 0.75)
            mark
                .frame(width: size * 0.56, height: size * 0.56)
        }
        .frame(width: size, height: size)
    }

    // MARK: Background

    private var bgFill: LinearGradient {
        switch brand {
        case .gemini:
            return LinearGradient(
                colors: [Color(hex: "#4285F4").opacity(0.20), Color(hex: "#8AB4F8").opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .codex:
            return LinearGradient(
                colors: [Color(NSColor.labelColor).opacity(0.13), Color(NSColor.labelColor).opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .claude:
            return LinearGradient(
                colors: [Color(hex: "#DA7756").opacity(0.22), Color(hex: "#C96A3E").opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var strokeColor: Color {
        switch brand {
        case .gemini: return Color(hex: "#4285F4").opacity(0.35)
        case .codex:  return Color(NSColor.labelColor).opacity(0.20)
        case .claude: return Color(hex: "#DA7756").opacity(0.38)
        }
    }

    // MARK: Logo Shape Switch

    @ViewBuilder
    private var mark: some View {
        switch brand {
        case .gemini: GeminiSparkle()
        case .codex:  OpenAIBloom()
        case .claude: AnthropicSunrise()
        }
    }
}

// MARK: - Google Gemini — 4-pointed sparkle (lens/vesica cross)

/// The Gemini logo is two overlapping "eye" shapes crossing at 90°, forming a
/// smooth 4-pointed star. Drawn with Bezier curves so the arms taper gracefully.
struct GeminiSparkle: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let r  = min(size.width, size.height) / 2
            let b  = r * 0.20   // control-point inset (bulge width)

            // ── Vertical arm (N → S, blue gradient) ──
            var vPath = Path()
            vPath.move(to: CGPoint(x: cx, y: cy - r))
            vPath.addCurve(
                to: CGPoint(x: cx, y: cy + r),
                control1: CGPoint(x: cx + b, y: cy - b),
                control2: CGPoint(x: cx + b, y: cy + b))
            vPath.addCurve(
                to: CGPoint(x: cx, y: cy - r),
                control1: CGPoint(x: cx - b, y: cy + b),
                control2: CGPoint(x: cx - b, y: cy - b))
            vPath.closeSubpath()

            ctx.fill(vPath, with: .linearGradient(
                Gradient(colors: [Color(hex: "#5AA0F0"), Color(hex: "#4285F4")]),
                startPoint: CGPoint(x: cx, y: cy - r),
                endPoint:   CGPoint(x: cx, y: cy + r)))

            // ── Horizontal arm (W → E, lighter blue) ──
            var hPath = Path()
            hPath.move(to: CGPoint(x: cx - r, y: cy))
            hPath.addCurve(
                to: CGPoint(x: cx + r, y: cy),
                control1: CGPoint(x: cx - b, y: cy - b),
                control2: CGPoint(x: cx + b, y: cy - b))
            hPath.addCurve(
                to: CGPoint(x: cx - r, y: cy),
                control1: CGPoint(x: cx + b, y: cy + b),
                control2: CGPoint(x: cx - b, y: cy + b))
            hPath.closeSubpath()

            ctx.fill(hPath, with: .linearGradient(
                Gradient(colors: [Color(hex: "#8AB4F8"), Color(hex: "#4285F4")]),
                startPoint: CGPoint(x: cx - r, y: cy),
                endPoint:   CGPoint(x: cx + r, y: cy)))
        }
    }
}

// MARK: - OpenAI / Codex — 6-petal bloom

/// The OpenAI logo is 6 rounded "teeth" rotated around the centre in a
/// pinwheel pattern. Each capsule is offset upward then rotated by 60°.
struct OpenAIBloom: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Capsule()
                        .fill(Color(NSColor.labelColor).opacity(0.85))
                        .frame(width: w * 0.255, height: h * 0.60)
                        .offset(y: -h * 0.135)
                        .rotationEffect(.degrees(Double(i) * 60.0))
                }
            }
            .frame(width: w, height: h)
            // Blend so petals merge cleanly
            .compositingGroup()
            .blendMode(.normal)
        }
    }
}

// MARK: - Anthropic / Claude — sunrise rays

/// Anthropic's logomark evokes a sunrise: 7 tapered rays fanning upward
/// from a shared base point. The centre ray is tallest; outer rays are shorter
/// and more translucent, creating a warm orange gradient effect.
struct AnthropicSunrise: View {
    var body: some View {
        Canvas { ctx, size in
            let cx      = size.width  / 2
            let baseY   = size.height * 0.82   // fan origin (near bottom)
            let rayCount = 7
            let maxLen   = size.height * 0.82
            let baseHW   = size.width  * 0.055  // half-width at the base

            for i in 0..<rayCount {
                let t = Double(i) / Double(rayCount - 1)    // 0…1
                // Fan from -145° → -35° (pointing up; cos/sin in standard math)
                let angleDeg = -145.0 + t * 110.0
                let angle    = angleDeg * .pi / 180.0
                let cosA = cos(angle), sinA = sin(angle)
                let perpCos = -sinA, perpSin = cosA          // perpendicular

                // Centre ray is tallest; edge rays 60% as long
                let lenFrac = 1.0 - 0.40 * abs(t - 0.5) * 2.0
                let len     = maxLen * lenFrac
                let tipX    = cx + len * cosA
                let tipY    = baseY + len * sinA

                // Trapezoid: wide at base, narrow at tip
                let tipHW   = baseHW * 0.25
                let p1 = CGPoint(x: cx    + perpCos * baseHW, y: baseY + perpSin * baseHW)
                let p2 = CGPoint(x: cx    - perpCos * baseHW, y: baseY - perpSin * baseHW)
                let p3 = CGPoint(x: tipX  - perpCos * tipHW,  y: tipY  - perpSin * tipHW)
                let p4 = CGPoint(x: tipX  + perpCos * tipHW,  y: tipY  + perpSin * tipHW)

                var path = Path()
                path.move(to: p1)
                path.addLine(to: p4)
                path.addLine(to: p3)
                path.addLine(to: p2)
                path.closeSubpath()

                // Centre rays are vivid; outer rays fade
                let alpha = 0.45 + 0.55 * (1.0 - abs(t - 0.5) * 1.6)
                ctx.fill(path, with: .color(Color(hex: "#DA7756").opacity(alpha)))
            }
        }
    }
}

// MARK: - Agent Tab Button (used in the custom tab bar)

struct AgentTabButton: View {
    let title: String
    let brand: AgentBrand
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AgentLogoView(brand: brand, size: 30)

                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected
                        ? SettingsView.Theme.textMain
                        : SettingsView.Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                        ? SettingsView.Theme.card
                        : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? SettingsView.Theme.separator : Color.clear,
                                lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
