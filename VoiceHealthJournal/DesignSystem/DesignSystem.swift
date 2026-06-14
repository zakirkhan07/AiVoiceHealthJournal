import SwiftUI
import UIKit

/// Minimal design system: tokens + reusable components.
/// Everything user-facing pulls from here so the app restyles in one place.
enum DS {
    enum Colors {
        static let accent = Color(red: 0.18, green: 0.45, blue: 0.70)   // calm blue
        static let accentSoft = Color(red: 0.18, green: 0.45, blue: 0.70).opacity(0.12)
        static let positive = Color(red: 0.20, green: 0.60, blue: 0.45)
        static let warning = Color(red: 0.85, green: 0.55, blue: 0.15)
        static let danger = Color(red: 0.80, green: 0.30, blue: 0.30)
        static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    }

    enum Spacing {
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }
}

// MARK: - Components

struct DSCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.m)
            .background(DS.Colors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SeverityDots: View {
    let severity: Int  // 1–5
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= severity ? color : Color(UIColor.systemGray4))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Severity \(severity) out of 5")
    }
    private var color: Color {
        switch severity {
        case 1...2: return DS.Colors.positive
        case 3: return DS.Colors.warning
        default: return DS.Colors.danger
        }
    }
}

struct StatusBanner: View {
    enum Kind { case info, error }
    let kind: Kind
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(kind == .error ? DS.Colors.danger : DS.Colors.accent)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.footnote.bold())
            }
        }
        .padding(DS.Spacing.m)
        .background((kind == .error ? DS.Colors.danger : DS.Colors.accent).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Animated waveform driven by mic level — gives the user trust that we're listening.
struct WaveformView: View {
    let level: Float
    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let amplitude = CGFloat(max(level, 0.05)) * midY * 0.9
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            for x in stride(from: 0, through: size.width, by: 2) {
                let relative = x / size.width
                let y = midY + sin(relative * .pi * 6 + phase) * amplitude * sin(relative * .pi)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(DS.Colors.accent), lineWidth: 2.5)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .accessibilityHidden(true)
    }
}
