import Foundation

struct AgentRunEvent: Identifiable, Equatable, Sendable, Codable {
    enum Kind: String, Equatable, Sendable, Codable {
        case info
        case llm
        case tool
        case action
        case completion
        case cancelled
        case error
    }

    var id: UUID
    var timestamp: Date
    var kind: Kind
    var message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

struct AgentRunRecord: Identifiable, Equatable, Sendable, Codable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var outcome: AutomationRunOutcome?
    var displayIndex: Int?
    var events: [AgentRunEvent]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date? = nil,
        outcome: AutomationRunOutcome? = nil,
        displayIndex: Int? = nil,
        events: [AgentRunEvent] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.displayIndex = displayIndex
        self.events = events
    }
}

