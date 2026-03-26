import Foundation

struct MissingProviderKeyDialog: Equatable {
    enum Action: Equatable {
        case extractTask
        case runTask
    }

    let provider: ProviderIdentifier
    let action: Action

    var title: String {
        switch provider {
        case .gemini:
            return "Gemini API key required"
        case .openAI:
            return "OpenAI API key required"
        }
    }

    var message: String {
        switch action {
        case .extractTask:
            return "Enter your \(providerDisplayName) API key before extracting. Open Settings to add it."
        case .runTask:
            return "Enter your \(providerDisplayName) API key before running the task. Open Settings to add it."
        }
    }

    private var providerDisplayName: String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }
}

enum RecordingPreflightRequirement: String, Identifiable, Equatable {
    case geminiAPIKey
    case screenRecording
    case microphone
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geminiAPIKey:
            return "Gemini API key"
        case .screenRecording:
            return "Screen Recording"
        case .microphone:
            return "Microphone (Voice)"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .geminiAPIKey:
            return "Required to extract tasks after recording."
        case .screenRecording:
            return "Required to capture your screen."
        case .microphone:
            return "Required to record voice audio."
        case .inputMonitoring:
            return "Required so Escape can stop recording."
        }
    }

    var permission: AppPermission? {
        switch self {
        case .screenRecording:
            return .screenRecording
        case .microphone:
            return .microphone
        case .inputMonitoring:
            return .inputMonitoring
        case .geminiAPIKey:
            return nil
        }
    }
}

struct RecordingPreflightDialogState: Equatable {
    var missingRequirements: [RecordingPreflightRequirement]

    var title: String {
        "Recording Setup Required"
    }

    var message: String {
        "Complete the missing items below before starting a recording."
    }
}

enum RunTaskPreflightRequirement: String, Identifiable, Equatable {
    case openAIAPIKey
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIAPIKey:
            return "OpenAI API key"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .openAIAPIKey:
            return "Required to run tasks with the agent."
        case .accessibility:
            return "Required so the agent can click and type."
        case .inputMonitoring:
            return "Required so Escape can stop an active run."
        }
    }

    var permission: AppPermission? {
        switch self {
        case .accessibility:
            return .accessibility
        case .inputMonitoring:
            return .inputMonitoring
        case .openAIAPIKey:
            return nil
        }
    }
}

struct RunTaskPreflightDialogState: Equatable {
    var missingRequirements: [RunTaskPreflightRequirement]

    var title: String {
        "Run Task Setup Required"
    }

    var message: String {
        "Complete the missing items below before running this task."
    }
}
