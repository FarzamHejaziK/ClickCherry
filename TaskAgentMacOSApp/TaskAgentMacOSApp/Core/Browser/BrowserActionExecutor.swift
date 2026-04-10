import Foundation

enum BrowserProfileMode: String, Codable, Equatable, Sendable {
    case auto
    case managed
    case userProfile = "user_profile"
}

struct BrowserLaunchOptions: Codable, Equatable, Sendable {
    var profileMode: BrowserProfileMode?
    var profileHint: String?
    var profileName: String?
    var profileDirectory: String?
    var userDataDir: String?
    var forceRelaunch: Bool?

    enum CodingKeys: String, CodingKey {
        case profileMode = "profile_mode"
        case profileHint = "profile_hint"
        case profileName = "profile_name"
        case profileDirectory = "profile_directory"
        case userDataDir = "user_data_dir"
        case forceRelaunch = "force_relaunch"
    }

    var hasProfileSelection: Bool {
        !(profileHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(profileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(profileDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(userDataDir?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        profileMode != nil ||
        forceRelaunch == true
    }

    var summary: String {
        if let profileDirectory, !profileDirectory.isEmpty {
            return "profile directory '\(profileDirectory)'"
        }
        if let profileName, !profileName.isEmpty {
            return "profile name '\(profileName)'"
        }
        if let profileHint, !profileHint.isEmpty {
            return "profile hint '\(profileHint)'"
        }
        if let profileMode {
            return "profile mode '\(profileMode.rawValue)'"
        }
        return "default profile"
    }
}

struct BrowserProfileInfo: Codable, Equatable, Sendable {
    var kind: String
    var displayName: String
    var profileDirectory: String?
    var userDataDir: String
    var isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case displayName = "display_name"
        case profileDirectory = "profile_directory"
        case userDataDir = "user_data_dir"
        case isDefault = "is_default"
    }

    var toolData: [String: Any] {
        var data: [String: Any] = [
            "kind": kind,
            "display_name": displayName,
            "user_data_dir": userDataDir,
            "is_default": isDefault
        ]
        if let profileDirectory, !profileDirectory.isEmpty {
            data["profile_directory"] = profileDirectory
        }
        return data
    }
}

struct BrowserElementQuery: Codable, Equatable, Sendable {
    var role: String?
    var name: String?
    var text: String?
    var label: String?
    var placeholder: String?
    var testID: String?
    var css: String?
    var locator: String?

    enum CodingKeys: String, CodingKey {
        case role
        case name
        case text
        case label
        case placeholder
        case testID = "test_id"
        case css
        case locator
    }

    var hasSelector: Bool {
        [role, name, text, label, placeholder, testID, css, locator]
            .contains { value in
                guard let value else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var summary: String {
        if let locator, !locator.isEmpty {
            return "locator '\(locator)'"
        }
        if let css, !css.isEmpty {
            return "css '\(css)'"
        }
        if let role, !role.isEmpty {
            if let name, !name.isEmpty {
                return "role '\(role)' named '\(name)'"
            }
            return "role '\(role)'"
        }
        if let testID, !testID.isEmpty {
            return "test id '\(testID)'"
        }
        if let label, !label.isEmpty {
            return "label '\(label)'"
        }
        if let placeholder, !placeholder.isEmpty {
            return "placeholder '\(placeholder)'"
        }
        if let text, !text.isEmpty {
            return "text '\(text)'"
        }
        if let name, !name.isEmpty {
            return "name '\(name)'"
        }
        return "unspecified element"
    }
}

struct BrowserTabSelection: Codable, Equatable, Sendable {
    var index: Int?
    var titleContains: String?
    var urlContains: String?

    enum CodingKeys: String, CodingKey {
        case index
        case titleContains = "title_contains"
        case urlContains = "url_contains"
    }

    var hasSelection: Bool {
        index != nil ||
        !(titleContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(urlContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var summary: String {
        if let index {
            return "tab index \(index)"
        }
        if let titleContains, !titleContains.isEmpty {
            return "title containing '\(titleContains)'"
        }
        if let urlContains, !urlContains.isEmpty {
            return "URL containing '\(urlContains)'"
        }
        return "current tab"
    }
}

struct BrowserWaitCondition: Codable, Equatable, Sendable {
    var urlContains: String?
    var titleContains: String?
    var text: String?
    var role: String?
    var name: String?
    var timeoutSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case urlContains = "url_contains"
        case titleContains = "title_contains"
        case text
        case role
        case name
        case timeoutSeconds = "timeout_seconds"
    }

    var hasCondition: Bool {
        !(urlContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(titleContains?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        !(role?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var summary: String {
        if let urlContains, !urlContains.isEmpty {
            return "URL containing '\(urlContains)'"
        }
        if let titleContains, !titleContains.isEmpty {
            return "title containing '\(titleContains)'"
        }
        if let text, !text.isEmpty {
            return "text '\(text)'"
        }
        if let role, !role.isEmpty {
            if let name, !name.isEmpty {
                return "role '\(role)' named '\(name)'"
            }
            return "role '\(role)'"
        }
        return "unspecified browser condition"
    }
}

struct BrowserPageState: Codable, Equatable, Sendable {
    var title: String
    var url: String
    var targetID: String?

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case targetID = "target_id"
    }

    var toolData: [String: Any] {
        var data: [String: Any] = [
            "title": title,
            "url": url
        ]
        if let targetID, !targetID.isEmpty {
            data["target_id"] = targetID
        }
        return data
    }
}

struct BrowserTabInfo: Codable, Equatable, Sendable {
    var index: Int
    var title: String
    var url: String
    var isSelected: Bool
    var targetID: String?

    enum CodingKeys: String, CodingKey {
        case index
        case title
        case url
        case isSelected = "is_selected"
        case targetID = "target_id"
    }

    var toolData: [String: Any] {
        var data: [String: Any] = [
            "index": index,
            "title": title,
            "url": url,
            "is_selected": isSelected
        ]
        if let targetID, !targetID.isEmpty {
            data["target_id"] = targetID
        }
        return data
    }
}

struct BrowserSessionInfo: Codable, Equatable, Sendable {
    var debuggingPort: Int
    var launched: Bool
    var tabCount: Int
    var currentPage: BrowserPageState?
    var profile: BrowserProfileInfo?

    enum CodingKeys: String, CodingKey {
        case debuggingPort = "debugging_port"
        case launched
        case tabCount = "tab_count"
        case currentPage = "current_page"
        case profile
    }

    var toolData: [String: Any] {
        var data: [String: Any] = [
            "debugging_port": debuggingPort,
            "launched": launched,
            "tab_count": tabCount
        ]
        if let currentPage {
            data["current_page"] = currentPage.toolData
        }
        if let profile {
            data["profile"] = profile.toolData
        }
        return data
    }
}

struct BrowserSnapshot: Codable, Equatable, Sendable {
    var page: BrowserPageState
    var textExcerpt: String

    enum CodingKeys: String, CodingKey {
        case page
        case textExcerpt = "text_excerpt"
    }

    var toolData: [String: Any] {
        var data = page.toolData
        data["text_excerpt"] = textExcerpt
        return data
    }
}

struct BrowserWaitResult: Codable, Equatable, Sendable {
    var conditionDescription: String
    var page: BrowserPageState

    enum CodingKeys: String, CodingKey {
        case conditionDescription = "condition_description"
        case page
    }

    var toolData: [String: Any] {
        var data = page.toolData
        data["condition_description"] = conditionDescription
        return data
    }
}

enum BrowserActionExecutorError: Error, Equatable, LocalizedError {
    case browserActionUnavailable(String)
    case invalidURL(String)
    case missingSelector
    case missingValue
    case nodeUnavailable(String)
    case sidecarNotFound(String)
    case sidecarDependenciesMissing(String)
    case chromeNotFound
    case executionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .browserActionUnavailable(let reason):
            return "Browser automation is unavailable: \(reason)"
        case .invalidURL(let value):
            return "Invalid browser URL '\(value)'."
        case .missingSelector:
            return "Browser action is missing an element selector."
        case .missingValue:
            return "Browser action is missing the text value to type."
        case .nodeUnavailable(let details):
            return details
        case .sidecarNotFound(let path):
            return "Browser automation helper was not found at \(path)."
        case .sidecarDependenciesMissing(let path):
            return "Browser automation dependencies are missing. Run `npm install` in \(path)."
        case .chromeNotFound:
            return "Google Chrome was not found in /Applications."
        case .executionFailed(let reason):
            return "Browser automation failed: \(reason)"
        case .invalidResponse:
            return "Browser automation returned an invalid response."
        }
    }
}

protocol BrowserActionExecutor {
    func attachOrLaunchChrome(options: BrowserLaunchOptions?) async throws -> BrowserSessionInfo
    func listTabs() async throws -> [BrowserTabInfo]
    func selectTab(using selection: BrowserTabSelection) async throws -> BrowserTabInfo
    func goto(url: URL) async throws -> BrowserPageState
    func click(query: BrowserElementQuery) async throws -> BrowserPageState
    func type(text: String, query: BrowserElementQuery, pressEnter: Bool) async throws -> BrowserPageState
    func press(key: String) async throws -> BrowserPageState
    func waitFor(_ condition: BrowserWaitCondition) async throws -> BrowserWaitResult
    func snapshot() async throws -> BrowserSnapshot
    func getURL() async throws -> String
    func getTitle() async throws -> String
}
