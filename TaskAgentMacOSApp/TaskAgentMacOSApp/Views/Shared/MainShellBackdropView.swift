import SwiftUI

/// Main-shell backdrop that matches the onboarding palette: subtle accent-tinted gradients
/// over the window background, with a slightly stronger bias on the left (sidebar) side.
struct MainShellBackdropView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear
                ],
                center: UnitPoint(x: 0.42, y: 0.22),
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear
                ],
                center: .top,
                startRadius: 180,
                endRadius: 980
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }
}
