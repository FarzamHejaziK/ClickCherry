import AppKit
import SwiftUI

struct OnboardingFooterBar: View {
    let currentIndex: Int
    let totalCount: Int
    let canGoBack: Bool
    let canContinue: Bool
    let isLastStep: Bool
    let showsSkip: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            OnboardingStepIndicatorView(currentIndex: currentIndex, totalCount: totalCount)

            HStack {
                Button("Back", action: onBack)
                    .ccPrimaryActionButton()
                    .disabled(!canGoBack)

                Spacer()

                if showsSkip && !isLastStep {
                    Button("Skip", action: onSkip)
                        .ccPrimaryActionButton()
                }

                if isLastStep {
                    Button("Finish Setup", action: onFinish)
                        .ccPrimaryActionButton()
                } else {
                    Button("Continue", action: onContinue)
                        .ccPrimaryActionButton()
                        .disabled(!canContinue)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}

struct OnboardingBackdropView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.clear
                ],
                center: .top,
                startRadius: 160,
                endRadius: 980
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }
}

struct OnboardingStepIndicatorView: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalCount, id: \.self) { index in
                if index == currentIndex {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.accentColor))
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(totalCount)")
    }
}

struct OnboardingHeroView: View {
    enum Size {
        case large
        case compact

        var iconSize: CGFloat {
            switch self {
            case .large:
                return 140
            case .compact:
                return 110
            }
        }

        var glowSize: CGFloat {
            switch self {
            case .large:
                return 320
            case .compact:
                return 240
            }
        }

        var height: CGFloat {
            switch self {
            case .large:
                return 230
            case .compact:
                return 175
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .large:
                return 30
            case .compact:
                return 24
            }
        }

        var sparkleSize: CGFloat {
            switch self {
            case .large:
                return 20
            case .compact:
                return 16
            }
        }

        var sideSymbolSize: CGFloat {
            switch self {
            case .large:
                return 18
            case .compact:
                return 14
            }
        }
    }

    let size: Size

    private var appIconImage: NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 && icon.size.height > 0 {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.35),
                            Color.accentColor.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.glowSize / 2
                    )
                )
                .frame(width: size.glowSize, height: size.glowSize)
                .blur(radius: 14)
                .offset(y: size == .large ? 6 : 0)

            Image(systemName: "sparkles")
                .font(.system(size: size.sparkleSize, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.75))
                .offset(x: size.glowSize * 0.22, y: -size.glowSize * 0.18)

            Image(systemName: "gearshape.fill")
                .font(.system(size: size.sideSymbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .offset(x: -size.glowSize * 0.24, y: size.glowSize * 0.10)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size.sideSymbolSize - 1, weight: .semibold))
                .foregroundStyle(.secondary)
                .offset(x: size.glowSize * 0.18, y: size.glowSize * 0.14)

            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size.iconSize, height: size.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 12)
        }
        .frame(height: size.height)
        .accessibilityHidden(true)
    }
}
