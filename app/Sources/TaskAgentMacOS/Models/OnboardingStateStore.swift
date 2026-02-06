import Foundation
import Observation

enum AppRoute: Equatable {
    case onboarding
    case mainShell
}

@Observable
final class OnboardingStateStore {
    var providerSetupState: ProviderSetupState

    init(providerSetupState: ProviderSetupState = ProviderSetupState(hasOpenAIKey: false, hasAnthropicKey: false, hasGeminiKey: false)) {
        self.providerSetupState = providerSetupState
    }

    var route: AppRoute {
        if providerSetupState.isReadyForOnboardingCompletion {
            return .mainShell
        }

        return .onboarding
    }
}
