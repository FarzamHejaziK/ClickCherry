import AppKit
import SwiftUI

struct BridgeTokenEntryPanelView: View {
    let title: String
    let subtitle: String
    @Binding var tokenInput: String
    @Binding var isTokenVisible: Bool
    let saved: Bool
    let onSave: () -> Void
    let onClear: () -> Void

    private var trimmedTokenInput: String {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

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

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Group {
                        if isTokenVisible {
                            TextField("Enter Playwright MCP Bridge token", text: $tokenInput)
                        } else {
                            SecureField("Enter Playwright MCP Bridge token", text: $tokenInput)
                        }
                    }
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        if let value = NSPasteboard.general.string(forType: .string) {
                            tokenInput = value
                        }
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

                Button(action: onSave) {
                    Text(saved ? "Update" : "Save")
                        .frame(maxWidth: .infinity)
                }
                .ccPrimaryActionButton()
                .frame(width: 112)
                .disabled(trimmedTokenInput.isEmpty)

                Button("Clear", action: onClear)
                    .frame(width: 92)
                    .disabled(!saved)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
