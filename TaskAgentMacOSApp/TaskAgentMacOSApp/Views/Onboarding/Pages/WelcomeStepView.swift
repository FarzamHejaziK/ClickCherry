import SwiftUI

struct WelcomeStepView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let highlights: [WelcomeHighlight] = [
        WelcomeHighlight(
            icon: "key.horizontal.fill",
            title: "Connect providers",
            detail: "Add your OpenAI and Gemini keys once."
        ),
        WelcomeHighlight(
            icon: "lock.shield.fill",
            title: "Grant macOS access",
            detail: "Enable permissions required for reliable task execution."
        ),
        WelcomeHighlight(
            icon: "sparkles",
            title: "Start automating",
            detail: "Record a workflow once, then let ClickCherry run it next time."
        )
    ]

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 12) {
                Text("Quick setup")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())

                Text("Welcome to ClickCherry")
                    .font(.system(size: 36, weight: .bold))

                Text("This setup will configure model providers and required macOS permissions before task creation.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 620)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 34) {
                OnboardingHeroView(size: .large)
                    .frame(maxWidth: 240)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(highlights) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.accent)
                                .frame(width: 26, height: 26)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                radius: colorScheme == .dark ? 24 : 12,
                x: 0,
                y: colorScheme == .dark ? 14 : 8
            )
        }
    }
}

private struct WelcomeHighlight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}
