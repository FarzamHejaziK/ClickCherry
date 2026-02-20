import SwiftUI

struct MissingProviderKeyDialogCanvasView: View {
    let dialog: MissingProviderKeyDialog
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.18))
                            Image(systemName: "key.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor.opacity(0.95))
                        }
                        .frame(width: 32, height: 32)

                        Text(dialog.title)
                            .font(.system(size: 20, weight: .semibold))

                        Spacer(minLength: 0)
                    }

                    Text(dialog.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Divider()
                    .opacity(0.35)

                HStack(spacing: 10) {
                    Button("Not now") {
                        onDismiss()
                    }
                    .ccPrimaryActionButton()

                    Spacer(minLength: 0)

                    Button("Open Settings") {
                        onOpenSettings()
                    }
                    .ccPrimaryActionButton()
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: 520)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .padding(24)
        }
    }
}
