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
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
