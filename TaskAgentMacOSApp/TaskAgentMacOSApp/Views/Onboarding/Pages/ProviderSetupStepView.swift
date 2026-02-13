import AppKit
import SwiftUI

struct ProviderSetupStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore
    @State private var openAIKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var isOpenAIKeyVisible = false
    @State private var isGeminiKeyVisible = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Provider Setup")
                    .font(.system(size: 24, weight: .semibold))
                Text("Gemini is used for screen recording analysis, and OpenAI is used for agent tasks.")
                    .foregroundStyle(.secondary)
                Text("Keys are stored securely in your macOS Keychain and only sent to the provider APIs you configure.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            ProviderKeyEntryPanelView(
                title1: "OpenAI",
                iconAssetName1: "OpenAILogo",
                keyInput1: $openAIKeyInput,
                isKeyVisible1: $isOpenAIKeyVisible,
                saved1: onboardingStateStore.providerSetupState.hasOpenAIKey,
                onSave1: {
                    if onboardingStateStore.saveProviderKey(openAIKeyInput, for: .openAI) {
                        openAIKeyInput = ""
                    }
                },
                title2: "Gemini",
                iconAssetName2: "GeminiLogo",
                keyInput2: $geminiKeyInput,
                isKeyVisible2: $isGeminiKeyVisible,
                saved2: onboardingStateStore.providerSetupState.hasGeminiKey,
                onSave2: {
                    if onboardingStateStore.saveProviderKey(geminiKeyInput, for: .gemini) {
                        geminiKeyInput = ""
                    }
                }
            )

            if let persistenceErrorMessage = onboardingStateStore.persistenceErrorMessage {
                Text(persistenceErrorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}
