import AppKit
import SwiftUI

struct RunTaskPreflightDialogCanvasView: View {
    var showsBackdrop: Bool = true
    let state: RunTaskPreflightDialogState
    let apiKeyStatusMessage: String?
    let apiKeyErrorMessage: String?
    let onDismiss: () -> Void
    let onOpenSettingsForRequirement: (RunTaskPreflightRequirement) -> Void
    let onSaveOpenAIKey: (String) -> Void
    let onContinue: () -> Void

    @State private var openAIKeyDraft = ""
    @State private var isOpenAIKeyVisible = false
    @Environment(\.dismiss) private var dismissSheet

    private let actionButtonWidth: CGFloat = 130
    private let footerButtonWidth: CGFloat = 130

    private var openAIStatusMessage: String? {
        guard let apiKeyStatusMessage, apiKeyStatusMessage.localizedCaseInsensitiveContains("OpenAI") else {
            return nil
        }
        return apiKeyStatusMessage
    }

    private var openAIErrorMessage: String? {
        guard let apiKeyErrorMessage, apiKeyErrorMessage.localizedCaseInsensitiveContains("OpenAI") else {
            return nil
        }
        return apiKeyErrorMessage
    }

    var body: some View {
        ZStack {
            if showsBackdrop {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.title)
                        .font(.system(size: 33, weight: .semibold))
                    Text(state.message)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }

                VStack(spacing: 0) {
                    ForEach(state.missingRequirements) { requirement in
                        requirementRow(requirement)
                        if requirement != state.missingRequirements.last {
                            Divider()
                                .opacity(0.35)
                                .padding(.leading, PermissionRowMetrics.rowPaddingX)
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14))
                        .allowsHitTesting(false)
                }

                HStack(spacing: 10) {
                    Button {
                        onDismiss()
                        dismissSheet()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(width: footerButtonWidth)
                    .ccPrimaryActionButton()

                    Spacer(minLength: 0)

                    Button(action: onContinue) {
                        Text("Check again")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(width: footerButtonWidth)
                    .ccPrimaryActionButton()
                }
                .padding(.horizontal, PermissionRowMetrics.rowPaddingX)
            }
            .padding(22)
            .frame(maxWidth: 760)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .overlay(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.08), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 20, x: 0, y: 12)
        }
    }

    @ViewBuilder
    private func requirementRow(_ requirement: RunTaskPreflightRequirement) -> some View {
        switch requirement {
        case .openAIAPIKey:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(requirement.title)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(requirement.detail)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    OpenAIKeyEntryFieldView(
                        placeholder: "Enter API key",
                        keyInput: $openAIKeyDraft,
                        isKeyVisible: $isOpenAIKeyVisible
                    )

                    Button {
                        onSaveOpenAIKey(openAIKeyDraft)
                        openAIKeyDraft = ""
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .frame(width: actionButtonWidth)
                    .ccPrimaryActionButton()
                    .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let openAIErrorMessage, !openAIErrorMessage.isEmpty {
                    Text(openAIErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                } else if let openAIStatusMessage, !openAIStatusMessage.isEmpty {
                    Text(openAIStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, PermissionRowMetrics.rowPaddingX)
            .padding(.vertical, PermissionRowMetrics.rowPaddingY)
        case .accessibility:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(requirement.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(requirement.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    onOpenSettingsForRequirement(requirement)
                    onDismiss()
                    dismissSheet()
                } label: {
                    Text("Open Settings")
                        .frame(maxWidth: .infinity)
                }
                .frame(width: actionButtonWidth)
                .ccPrimaryActionButton()
            }
            .padding(.horizontal, PermissionRowMetrics.rowPaddingX)
            .padding(.vertical, PermissionRowMetrics.rowPaddingY)
        }
    }
}

private struct OpenAIKeyEntryFieldView: View {
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
                if let value = NSPasteboard.general.string(forType: .string) {
                    keyInput = value
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
                .allowsHitTesting(false)
        }
    }
}
