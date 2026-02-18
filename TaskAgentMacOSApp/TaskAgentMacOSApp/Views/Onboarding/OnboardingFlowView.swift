import SwiftUI

struct OnboardingFlowView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    private var progressText: String {
        "Step \(onboardingStateStore.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(onboardingStateStore.currentStep.title)"
    }

    var body: some View {
        ZStack {
            OnboardingBackdropView()
            VStack(spacing: 18) {
                onboardingHeader
                onboardingStepContent
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 52)
            .padding(.top, 46)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            OnboardingFooterBar(
                currentIndex: onboardingStateStore.currentStep.rawValue,
                totalCount: OnboardingStep.allCases.count,
                canGoBack: onboardingStateStore.canGoBack,
                canContinue: onboardingStateStore.canContinueCurrentStep,
                isLastStep: onboardingStateStore.currentStep == .ready,
                showsSkip: onboardingStateStore.currentStep == .providerSetup || onboardingStateStore.currentStep == .permissionsPreflight,
                onBack: {
                    onboardingStateStore.goBack()
                },
                onSkip: {
                    switch onboardingStateStore.currentStep {
                    case .providerSetup:
                        onboardingStateStore.skipProviderSetup()
                    case .permissionsPreflight:
                        onboardingStateStore.skipPermissionsPreflight()
                    default:
                        break
                    }
                },
                onContinue: {
                    onboardingStateStore.goForward()
                },
                onFinish: {
                    onboardingStateStore.completeOnboarding()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }

    private var onboardingHeader: some View {
        VStack(spacing: 8) {
            Text("First-Run Setup")
                .font(.system(size: 34, weight: .semibold))
            Text(progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var onboardingStepContent: some View {
        Group {
            switch onboardingStateStore.currentStep {
            case .welcome:
                WelcomeStepView()
            case .providerSetup:
                ProviderSetupStepView(onboardingStateStore: onboardingStateStore)
            case .permissionsPreflight:
                PermissionsStepView(onboardingStateStore: onboardingStateStore)
            case .ready:
                ReadyStepView(onboardingStateStore: onboardingStateStore)
            }
        }
        .frame(maxWidth: onboardingStateStore.currentStep == .providerSetup ? 640 : 560)
    }
}
