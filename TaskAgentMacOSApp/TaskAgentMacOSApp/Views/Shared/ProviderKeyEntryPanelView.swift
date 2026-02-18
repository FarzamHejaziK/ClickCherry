import AppKit
import SwiftUI

struct ProviderKeyEntryPanelView: View {
    let title1: String
    let iconAssetName1: String
    @Binding var keyInput1: String
    @Binding var isKeyVisible1: Bool
    let saved1: Bool
    let onSave1: () -> Void

    let title2: String
    let iconAssetName2: String
    @Binding var keyInput2: String
    @Binding var isKeyVisible2: Bool
    let saved2: Bool
    let onSave2: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProviderKeyEntryRowView(
                title: title1,
                iconAssetName: iconAssetName1,
                keyInput: $keyInput1,
                isKeyVisible: $isKeyVisible1,
                saved: saved1,
                onSave: onSave1
            )

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 18)

            ProviderKeyEntryRowView(
                title: title2,
                iconAssetName: iconAssetName2,
                keyInput: $keyInput2,
                isKeyVisible: $isKeyVisible2,
                saved: saved2,
                onSave: onSave2
            )
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
        }
        .shadow(color: Color.black.opacity(0.22), radius: 26, x: 0, y: 16)
        .frame(maxWidth: 720)
    }
}

private struct ProviderKeyEntryRowView: View {
    static let iconSize: CGFloat = 28
    private static let rowPaddingX: CGFloat = 18
    private static let rowPaddingY: CGFloat = 16
    private static let actionColumnWidth: CGFloat = 112

    let title: String
    let iconAssetName: String
    @Binding var keyInput: String
    @Binding var isKeyVisible: Bool
    let saved: Bool
    let onSave: () -> Void

    private var trimmedKeyInput: String {
        keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                ProviderKeyStatusPillView(saved: saved)
                    .frame(width: Self.actionColumnWidth, alignment: .trailing)
            }

            HStack(spacing: 12) {
                ProviderKeyEntryFieldView(
                    placeholder: "Enter API key",
                    keyInput: $keyInput,
                    isKeyVisible: $isKeyVisible
                )

                Button(action: onSave) {
                    Text(saved ? "Update" : "Save")
                        .frame(maxWidth: .infinity)
                }
                    .ccPrimaryActionButton()
                    .frame(width: Self.actionColumnWidth)
                    .disabled(trimmedKeyInput.isEmpty)
            }
        }
        .padding(.horizontal, Self.rowPaddingX)
        .padding(.vertical, Self.rowPaddingY)
    }
}

private struct ProviderKeyStatusPillView: View {
    let saved: Bool

    var body: some View {
        Text(saved ? "Saved" : "Not saved")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(saved ? Color.green.opacity(0.65) : Color.primary.opacity(0.12))
            )
            .foregroundStyle(saved ? .black : .secondary)
    }
}

private struct ProviderKeyEntryFieldView: View {
    let placeholder: String
    @Binding var keyInput: String
    @Binding var isKeyVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isKeyVisible {
                    TextField(placeholder, text: $keyInput)
                } else {
                    SecureField(placeholder, text: $keyInput)
                }
            }
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                isKeyVisible.toggle()
            } label: {
                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16))
        }
    }

    private func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            keyInput = value
        }
    }
}
