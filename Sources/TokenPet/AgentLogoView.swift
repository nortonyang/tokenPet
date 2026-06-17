import SwiftUI

// MARK: - Agent Brand

public enum AgentBrand { case antigravity, codex, claude }

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
        case .antigravity:
            return LinearGradient(
                colors: [Color(hex: "#8A7CFF").opacity(0.24), Color(hex: "#30D158").opacity(0.10)],
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
        case .antigravity: return Color(hex: "#8A7CFF").opacity(0.38)
        case .codex:  return Color(NSColor.labelColor).opacity(0.20)
        case .claude: return Color(hex: "#DA7756").opacity(0.38)
        }
    }

    // MARK: Logo Shape Switch

    @ViewBuilder
    private var mark: some View {
        switch brand {
        case .antigravity: AntigravityMonogram()
        case .codex:  OpenAIBloom()
        case .claude: AnthropicSunrise()
        }
    }
}

// MARK: - Antigravity — agent monogram

struct AntigravityMonogram: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Text("A")
                    .font(.system(size: size * 0.82, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#8A7CFF"), Color(hex: "#30D158")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "arrow.up")
                    .font(.system(size: size * 0.22, weight: .heavy))
                    .foregroundColor(Color(hex: "#30D158"))
                    .offset(x: size * 0.23, y: -size * 0.25)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
