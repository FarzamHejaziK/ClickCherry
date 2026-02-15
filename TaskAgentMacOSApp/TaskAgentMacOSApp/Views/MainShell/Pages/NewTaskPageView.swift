import SwiftUI

struct NewTaskEmptyView: View {
    @Bindable var mainShellStateStore: MainShellStateStore

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    VStack(spacing: 4) {
                        Text(mainShellStateStore.isCapturing ? "Recording..." : "Start recording")
                            .font(.system(size: 34, weight: .semibold))

                        Text(mainShellStateStore.isCapturing ? "Click the button to stop." : "Explain your task in detail.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    Button {
                        mainShellStateStore.toggleNewTaskRecording()
                    } label: {
                        Image("RecordIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(mainShellStateStore.isCapturing ? Color.red : Color.primary)
                            .padding(22)
                            .background(.thinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    if !mainShellStateStore.isCapturing, mainShellStateStore.availableCaptureDisplays.count > 1 {
                        CaptureDisplayPickerView(mainShellStateStore: mainShellStateStore)
                            .padding(.top, 6)
                    }

                    if !mainShellStateStore.isCapturing, mainShellStateStore.availableMicrophoneDeviceCount > 1 {
                        CaptureMicrophonePickerView(mainShellStateStore: mainShellStateStore)
                            .padding(.top, 10)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Keep the display list fresh in case a monitor was plugged/unplugged.
                mainShellStateStore.refreshCaptureDisplays()
                mainShellStateStore.refreshCaptureAudioInputs()
            }

            if let errorMessage = mainShellStateStore.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
        }
    }
}

private struct CaptureDisplayPickerView: View {
    @Bindable var mainShellStateStore: MainShellStateStore
    @State private var thumbnailsByDisplayIndex: [Int: CGImage] = [:]

    var body: some View {
        VStack(spacing: 12) {
            Text("Screen")
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.9))

            let displays = mainShellStateStore.availableCaptureDisplays
            if displays.count <= 3 {
                HStack(spacing: 18) {
                    ForEach(displays) { display in
                        CaptureDisplayThumbnailCard(
                            label: display.label,
                            thumbnail: thumbnailsByDisplayIndex[display.id],
                            isSelected: mainShellStateStore.selectedCaptureDisplayID == display.id,
                            onSelect: {
                                mainShellStateStore.selectedCaptureDisplayID = display.id
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(displays) { display in
                            CaptureDisplayThumbnailCard(
                                label: display.label,
                                thumbnail: thumbnailsByDisplayIndex[display.id],
                                isSelected: mainShellStateStore.selectedCaptureDisplayID == display.id,
                                onSelect: {
                                    mainShellStateStore.selectedCaptureDisplayID = display.id
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 150)
            }
        }
        .frame(maxWidth: 920)
        .onAppear {
            refreshThumbnails()
        }
        .onChange(of: mainShellStateStore.availableCaptureDisplays) { _ in
            refreshThumbnails()
        }
    }

    private func refreshThumbnails() {
        let displayIndices = mainShellStateStore.availableCaptureDisplays.map(\.id)
        guard !displayIndices.isEmpty else {
            thumbnailsByDisplayIndex = [:]
            return
        }

        Task.detached(priority: .utility) {
            var next: [Int: CGImage] = [:]
            for displayIndex in displayIndices {
                if let thumbnail = try? DisplayThumbnailService.captureThumbnailForDisplayIndex(displayIndex) {
                    next[displayIndex] = thumbnail
                }
            }
            await MainActor.run {
                thumbnailsByDisplayIndex = next
            }
        }
    }
}

private struct CaptureMicrophonePickerView: View {
    @Bindable var mainShellStateStore: MainShellStateStore

    private var visibleOptions: [CaptureAudioInputOption] {
        let inputs = mainShellStateStore.availableCaptureAudioInputs
        let defaultOption = inputs.first(where: { $0.mode == .systemDefault })
        let devices = inputs.filter {
            if case .device = $0.mode { return true }
            return false
        }
        let noneOption = inputs.first(where: { $0.mode == .none })

        return [defaultOption]
            .compactMap { $0 }
            + devices
            + [noneOption].compactMap { $0 }
    }

    private var selectedLabel: String {
        guard let selectedID = mainShellStateStore.selectedCaptureAudioInputID else {
            return "System Default Microphone"
        }
        return visibleOptions.first(where: { $0.id == selectedID })?.label ?? "System Default Microphone"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Microphone")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(visibleOptions) { option in
                    Button {
                        mainShellStateStore.selectedCaptureAudioInputID = option.id
                    } label: {
                        HStack(spacing: 10) {
                            Text(option.label)
                            Spacer(minLength: 0)
                            if option.id == mainShellStateStore.selectedCaptureAudioInputID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(selectedLabel)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Keep it looking like plain text while still being an easy click target.
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: 920)
    }
}

private struct CaptureDisplayThumbnailCard: View {
    let label: String
    let thumbnail: CGImage?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.black.opacity(0.22)
                            Image(systemName: "display")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                .frame(width: 220, height: 138)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(label)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.94))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(width: 220, height: 138)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.95) : Color.primary.opacity(0.14),
                        lineWidth: isSelected ? 1.6 : 1
                    )
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(isSelected ? 0.16 : 0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
        }
        .buttonStyle(.plain)
    }
}
