import Foundation

enum LLMUserFacingIssueKind: String, Equatable, Sendable {
    case invalidCredentials = "invalid_credentials"
    case rateLimited = "rate_limited"
    case quotaOrBudgetExhausted = "quota_or_budget_exhausted"
    case billingOrTierNotEnabled = "billing_or_tier_not_enabled"
}

struct LLMUserFacingIssue: Equatable, Sendable {
    var provider: LLMProvider
    var operation: LLMOperation
    var kind: LLMUserFacingIssueKind
    var providerMessage: String
    var httpStatus: Int?
    var providerCode: String?
    var requestID: String?

    var providerDisplayName: String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    var title: String {
        switch kind {
        case .invalidCredentials:
            return "\(providerDisplayName) credentials are invalid."
        case .rateLimited:
            return "\(providerDisplayName) rate limit reached."
        case .quotaOrBudgetExhausted:
            return "\(providerDisplayName) quota or budget is exhausted."
        case .billingOrTierNotEnabled:
            return "\(providerDisplayName) billing or model tier is not enabled."
        }
    }

    var detail: String {
        switch kind {
        case .invalidCredentials:
            return "Update the API key in Settings, then retry."
        case .rateLimited:
            return "Wait briefly and retry."
        case .quotaOrBudgetExhausted:
            return "Increase quota/budget in provider billing, then retry."
        case .billingOrTierNotEnabled:
            return "Enable billing and required access tier for this project."
        }
    }

    var userMessage: String {
        "\(title) \(detail)"
    }

    var technicalSummary: String {
        var parts: [String] = []
        if let httpStatus {
            parts.append("HTTP \(httpStatus)")
        }
        if let providerCode, !providerCode.isEmpty {
            parts.append("code=\(providerCode)")
        }
        if let requestID, !requestID.isEmpty {
            parts.append("request_id=\(requestID)")
        }
        let message = providerMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: " | ")
    }

    var providerConsoleURL: URL? {
        switch provider {
        case .openAI:
            switch kind {
            case .invalidCredentials:
                return URL(string: "https://platform.openai.com/api-keys")
            case .rateLimited:
                return URL(string: "https://platform.openai.com/settings/organization/limits")
            case .quotaOrBudgetExhausted, .billingOrTierNotEnabled:
                return URL(string: "https://platform.openai.com/settings/organization/billing/overview")
            }
        case .gemini:
            switch kind {
            case .invalidCredentials:
                return URL(string: "https://aistudio.google.com/app/apikey")
            case .rateLimited:
                return URL(string: "https://ai.google.dev/gemini-api/docs/rate-limits")
            case .quotaOrBudgetExhausted, .billingOrTierNotEnabled:
                return URL(string: "https://console.cloud.google.com/billing")
            }
        }
    }
}

extension LLMUserFacingIssue {
    nonisolated static func == (lhs: LLMUserFacingIssue, rhs: LLMUserFacingIssue) -> Bool {
        lhs.provider == rhs.provider &&
            lhs.operation == rhs.operation &&
            lhs.kind == rhs.kind &&
            lhs.providerMessage == rhs.providerMessage &&
            lhs.httpStatus == rhs.httpStatus &&
            lhs.providerCode == rhs.providerCode &&
            lhs.requestID == rhs.requestID
    }
}
