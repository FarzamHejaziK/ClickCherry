import SwiftUI

/// Shared primary action button styling for ClickCherry.
/// Goal: consistent primary actions across pages, but less "shouty" than `.borderedProminent`.
struct CCPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let tint = Color.accentColor
        let fillOpacity: Double = {
            guard isEnabled else { return 0.10 }
            return configuration.isPressed ? 0.22 : 0.18
        }()
        let strokeOpacity: Double = isEnabled ? 0.42 : 0.22

        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint.opacity(fillOpacity))
                }
            )
            .overlay {
                shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

extension View {
    func ccPrimaryActionButton() -> some View {
        buttonStyle(CCPrimaryActionButtonStyle())
    }
}
