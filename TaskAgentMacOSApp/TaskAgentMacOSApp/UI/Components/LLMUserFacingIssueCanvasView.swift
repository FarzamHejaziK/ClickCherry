import SwiftUI

struct LLMUserFacingIssueCanvasView: View {
    let issue: LLMUserFacingIssue
    var onOpenSettings: (() -> Void)? = nil
    var onOpenProviderConsole: (() -> Void)? = nil

    private var accentColor: Color {
        switch issue.kind {
        case .invalidCredentials, .quotaOrBudgetExhausted, .billingOrTierNotEnabled:
            return .orange
        case .rateLimited:
            return .yellow
        }
    }

    private var iconName: String {
        switch issue.kind {
        case .invalidCredentials:
            return "key.slash.fill"
        case .rateLimited:
            return "speedometer"
        case .quotaOrBudgetExhausted:
            return "creditcard.trianglebadge.exclamationmark"
        case .billingOrTierNotEnabled:
            return "person.crop.circle.badge.exclamationmark"
        }
    }

    private var shouldShowSettingsAction: Bool {
        switch issue.kind {
        case .invalidCredentials, .billingOrTierNotEnabled:
            return true
        case .rateLimited, .quotaOrBudgetExhausted:
            return false
        }
    }

    private var shouldShowProviderAction: Bool {
        issue.providerConsoleURL != nil
    }

    private var providerActionLabel: String {
        switch issue.kind {
        case .invalidCredentials:
            return "Open API Keys"
        case .rateLimited:
            return "Open Limits"
        case .quotaOrBudgetExhausted:
            return "Open Billing"
        case .billingOrTierNotEnabled:
            return "Open Billing"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.18))
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(0.95))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(issue.detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !issue.technicalSummary.isEmpty {
                Text(issue.technicalSummary)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(3)
            }

            if shouldShowProviderAction || shouldShowSettingsAction {
                HStack(spacing: 10) {
                    if shouldShowProviderAction, let onOpenProviderConsole {
                        Button(providerActionLabel, action: onOpenProviderConsole)
                            .ccPrimaryActionButton()
                    }
                    if shouldShowSettingsAction, let onOpenSettings {
                        Button("Open Settings", action: onOpenSettings)
                            .ccPrimaryActionButton()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                shape.fill(.thinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.17),
                            accentColor.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1)
        }
    }
}
