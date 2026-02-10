import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class MockRecordingCaptureService: RecordingCaptureService {
    var isCapturing = false
    var lastCaptureIncludesMicrophone = true
    var lastCaptureStartWarning: String?
    var shouldFailStart = false
    var shouldFailStop = false
    var shouldDenyPermission = false
    var displays: [CaptureDisplayOption] = [CaptureDisplayOption(id: 1, label: "Display 1")]
    var audioInputs: [CaptureAudioInputOption] = [
        CaptureAudioInputOption(id: "default", label: "System Default Microphone", mode: .systemDefault),
        CaptureAudioInputOption(id: "device-42", label: "Test Mic (ID 42)", mode: .device(42)),
        CaptureAudioInputOption(id: "none", label: "No Microphone", mode: .none)
    ]
    var startedOutputURL: URL?
    var startedDisplayID: Int?
    var startedAudioInput: CaptureAudioInputMode?

    func listDisplays() -> [CaptureDisplayOption] {
        displays
    }

    func listAudioInputs() -> [CaptureAudioInputOption] {
        audioInputs
    }

    func startCapture(outputURL: URL, displayID: Int, audioInput: CaptureAudioInputMode) throws {
        if shouldDenyPermission {
            throw RecordingCaptureError.permissionDenied
        }
        if shouldFailStart {
            throw RecordingCaptureError.failedToStart("mock start failure")
        }
        if isCapturing {
            throw RecordingCaptureError.alreadyCapturing
        }
        startedOutputURL = outputURL
        startedDisplayID = displayID
        startedAudioInput = audioInput
        isCapturing = true
    }

    func stopCapture() throws {
        if shouldFailStop {
            throw RecordingCaptureError.notCapturing
        }
        guard isCapturing else {
            throw RecordingCaptureError.notCapturing
        }
        isCapturing = false
    }
}

private final class MockRecordingOverlayService: RecordingOverlayService {
    var shownDisplayIDs: [Int] = []
    var hideCallCount = 0

    func showBorder(displayID: Int) {
        shownDisplayIDs.append(displayID)
    }

    func hideBorder() {
        hideCallCount += 1
    }
}

private final class MockStoreLLMClient: LLMClient {
    var output: String
    var shouldThrowNotConfigured = false

    init(output: String) {
        self.output = output
    }

    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String {
        if shouldThrowNotConfigured {
            throw LLMClientError.notConfigured
        }
        return output
    }
}

private final class MockAPIKeyStore: APIKeyStore {
    private var values: [ProviderIdentifier: String]

    init(initialValues: [ProviderIdentifier: String] = [:]) {
        self.values = initialValues
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = values[provider] else {
            return false
        }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        values[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        values[provider] = key
    }
}

private final class MockAutomationEngine: AutomationEngine {
    var nextResult: AutomationRunResult
    var receivedMarkdowns: [String] = []

    init(nextResult: AutomationRunResult) {
        self.nextResult = nextResult
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        receivedMarkdowns.append(taskMarkdown)
        return nextResult
    }
}

private final class AlwaysGrantedPermissionService: PermissionService {
    private(set) var opened: [AppPermission] = []

    func openSystemSettings(for permission: AppPermission) {
        opened.append(permission)
    }

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        .granted
    }

    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        .granted
    }
}

struct MainShellStateStoreTests {
    @Test
    func selectTaskLoadsHeartbeatMarkdown() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Initial task")

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
        store.reloadTasks()
        store.selectTask(created.id)

        #expect(store.heartbeatMarkdown.contains("# Task"))
        #expect(store.heartbeatMarkdown.contains("Initial task"))
    }

    @Test
    func saveSelectedTaskHeartbeatPersistsContent() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Task one")

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.heartbeatMarkdown = """
        # Task
        Updated from store test

        ## Questions
        - None
        """
        store.saveSelectedTaskHeartbeat()

        let persisted = try service.readHeartbeat(taskId: created.id)
        #expect(persisted.contains("Updated from store test"))
        #expect(store.saveStatusMessage == "Saved.")
    }

    @Test
    func loadSelectedTaskHeartbeatParsesClarificationQuestions() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Clarification task")
        try taskService.saveHeartbeat(
            taskId: task.id,
            markdown: """
            # Task
            Clarification demo

            ## Questions
            - [required] Which account should be used?
            - [ ] Should we include archived items?
            """
        )

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
        store.reloadTasks()
        store.selectTask(task.id)

        #expect(store.clarificationQuestions.count == 2)
        #expect(store.unresolvedClarificationQuestions.count == 2)
        #expect(store.selectedClarificationQuestion != nil)
    }

    @Test
    func applyClarificationAnswerPersistsResolvedStateInHeartbeat() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Clarification apply task")
        try taskService.saveHeartbeat(
            taskId: task.id,
            markdown: """
            # Task
            Clarification demo

            ## Questions
            - [required] Which account should be used?
            - [ ] Should we include archived items?
            """
        )

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
        store.reloadTasks()
        store.selectTask(task.id)
        store.clarificationAnswerDraft = "Use the finance-admin account."
        store.applyClarificationAnswer()

        let persisted = try taskService.readHeartbeat(taskId: task.id)
        #expect(persisted.contains("- [x] Which account should be used?"))
        #expect(persisted.contains("Answer: Use the finance-admin account."))
        #expect(store.clarificationStatusMessage == "Applied clarification answer.")
        #expect(store.unresolvedClarificationQuestions.count == 1)
    }

    @Test
    func startAndStopCaptureUpdatesCaptureState() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Capture task")
        let captureService = MockRecordingCaptureService()
        let overlayService = MockRecordingOverlayService()

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(),
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()
        store.selectedCaptureAudioInputID = "device-42"

        store.startCapture()
        #expect(store.isCapturing)
        #expect(captureService.startedOutputURL != nil)
        #expect(captureService.startedDisplayID == 1)
        #expect(captureService.startedAudioInput == .device(42))
        #expect(overlayService.shownDisplayIDs == [1])

        store.stopCapture()
        #expect(!store.isCapturing)
        #expect(store.recordingStatusMessage == "Capture stopped.")
        #expect(overlayService.hideCallCount == 1)
    }

    @Test
    func startCaptureShowsPermissionErrorWhenDenied() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Permission task")
        let captureService = MockRecordingCaptureService()
        let overlayService = MockRecordingOverlayService()
        captureService.shouldDenyPermission = true

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(),
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()
        store.startCapture()

        #expect(!store.isCapturing)
        #expect(store.errorMessage == "Screen Recording permission denied. Grant access in System Settings and retry.")
        #expect(overlayService.hideCallCount == 1)
    }

    @Test
    func extractTaskUpdatesHeartbeatOnValidOutput() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptsRoot = tempRoot.appendingPathComponent("prompts", isDirectory: true)
        let promptDir = promptsRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Extraction task")

        let sourceRecording = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: sourceRecording)
        _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceRecording)
        let recording = try #require(taskService.listRecordings(taskId: task.id).first)

        let llm = MockStoreLLMClient(output: """
        # Task
        TaskDetected: true
        Status: TASK_FOUND
        NoTaskReason: NONE
        Title: Extracted Task
        Goal: Perform extracted task
        AppsObserved:
        - Browser
        
        ## Questions
        - None.
        """)
        let extractionService = TaskExtractionService(
            fileManager: fm,
            promptCatalog: PromptCatalogService(promptsRootURL: promptsRoot, fileManager: fm),
            llmClient: llm
        )
        let store = MainShellStateStore(
            taskService: taskService,
            taskExtractionService: extractionService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.extractTask(from: recording)

        #expect(store.errorMessage == nil)
        #expect(store.extractionStatusMessage?.contains("Extraction complete") == true)
        #expect(store.heartbeatMarkdown.contains("Title: Extracted Task"))
        #expect(!store.heartbeatMarkdown.contains("TaskDetected:"))
        #expect(!store.heartbeatMarkdown.contains("Status:"))
        #expect(!store.heartbeatMarkdown.contains("NoTaskReason:"))
    }

    @Test
    func extractTaskDoesNotOverwriteHeartbeatWhenOutputIsInvalid() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptsRoot = tempRoot.appendingPathComponent("prompts", isDirectory: true)
        let promptDir = promptsRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Extraction invalid task")
        let originalHeartbeat = try taskService.readHeartbeat(taskId: task.id)

        let sourceRecording = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: sourceRecording)
        _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceRecording)
        let recording = try #require(taskService.listRecordings(taskId: task.id).first)

        let llm = MockStoreLLMClient(output: """
        # Task
        Status: TASK_FOUND
        NoTaskReason: NONE
        Title: Missing required field
        """)
        let extractionService = TaskExtractionService(
            fileManager: fm,
            promptCatalog: PromptCatalogService(promptsRootURL: promptsRoot, fileManager: fm),
            llmClient: llm
        )
        let store = MainShellStateStore(
            taskService: taskService,
            taskExtractionService: extractionService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.extractTask(from: recording)

        let persistedHeartbeat = try taskService.readHeartbeat(taskId: task.id)
        #expect(persistedHeartbeat == originalHeartbeat)
        #expect(store.errorMessage == "Extraction output was invalid. HEARTBEAT.md was not changed.")
    }

    @Test
    func extractTaskDoesNotOverwriteHeartbeatWhenNoTaskDetected() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptsRoot = tempRoot.appendingPathComponent("prompts", isDirectory: true)
        let promptDir = promptsRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Extraction no-task")
        let originalHeartbeat = try taskService.readHeartbeat(taskId: task.id)

        let sourceRecording = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: sourceRecording)
        _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceRecording)
        let recording = try #require(taskService.listRecordings(taskId: task.id).first)

        let llm = MockStoreLLMClient(output: """
        # Task
        TaskDetected: false
        Status: NO_TASK
        NoTaskReason: NON_TASK_CONTENT
        Title: N/A
        Goal: N/A
        AppsObserved:
        - N/A
        PreferredDemonstratedApproach:
        - N/A
        ExecutionPolicy: Use demonstrated flow when practical, but any valid method is acceptable if it reaches the same goal and respects constraints.
        HardConstraints:
        - N/A
        SuccessCriteria:
        - N/A
        SuggestedPlan:
        1. N/A
        AlternativeValidApproaches:
        - N/A
        Evidence:
        - [00:00-00:05] Non-task clip.

        ## Questions
        - None.
        """)
        let extractionService = TaskExtractionService(
            fileManager: fm,
            promptCatalog: PromptCatalogService(promptsRootURL: promptsRoot, fileManager: fm),
            llmClient: llm
        )
        let store = MainShellStateStore(
            taskService: taskService,
            taskExtractionService: extractionService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.extractTask(from: recording)

        let persistedHeartbeat = try taskService.readHeartbeat(taskId: task.id)
        #expect(persistedHeartbeat == originalHeartbeat)
        #expect(store.heartbeatMarkdown == originalHeartbeat)
        #expect(store.errorMessage == nil)
        #expect(
            store.extractionStatusMessage ==
            "No actionable task detected. HEARTBEAT.md was not changed (gemini-3-pro, v2)."
        )
    }

    @Test
    func saveProviderKeyUpdatesSavedState() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let keyStore = MockAPIKeyStore()
        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: keyStore,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        #expect(!store.providerSetupState.hasGeminiKey)
        let saved = store.saveProviderKey("gemini-secret", for: .gemini)
        #expect(saved)
        #expect(store.providerSetupState.hasGeminiKey)
        #expect(store.apiKeyStatusMessage == "Saved Gemini API key.")
        #expect(store.apiKeyErrorMessage == nil)
    }

    @Test
    func clearProviderKeyUpdatesSavedState() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let keyStore = MockAPIKeyStore(initialValues: [.openAI: "test-key"])
        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: keyStore,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        #expect(store.providerSetupState.hasOpenAIKey)
        store.clearProviderKey(for: .openAI)
        #expect(!store.providerSetupState.hasOpenAIKey)
        #expect(store.apiKeyStatusMessage == "Removed OpenAI API key.")
        #expect(store.apiKeyErrorMessage == nil)
    }

    @Test
    func saveProviderKeyRejectsEmptyValue() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        let saved = store.saveProviderKey("   ", for: .anthropic)
        #expect(!saved)
        #expect(!store.providerSetupState.hasAnthropicKey)
        #expect(store.apiKeyStatusMessage == nil)
        #expect(store.apiKeyErrorMessage == "API key cannot be empty.")
    }

    @Test
    func runTaskNowSuccessPersistsRunSummary() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Runner success task")
        let engine = MockAutomationEngine(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: ["Open app 'Google Chrome'"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Task completed successfully."
            )
        )
        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.runTaskNow()

        #expect(store.runStatusMessage == "Run complete.")
        #expect(store.errorMessage == nil)
        #expect(engine.receivedMarkdowns.count == 1)
        let runFiles = try fm.contentsOfDirectory(at: task.workspace.runsDir, includingPropertiesForKeys: nil)
        #expect(runFiles.count == 1)
    }

    @Test
    func runTaskNowNeedsClarificationAppendsQuestionsToHeartbeat() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Runner clarification task")
        let engine = MockAutomationEngine(
            nextResult: AutomationRunResult(
                outcome: .needsClarification,
                executedSteps: ["Open app 'Google Chrome'"],
                generatedQuestions: ["Which account should I use?"],
                errorMessage: nil,
                llmSummary: "Need account clarification."
            )
        )
        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.runTaskNow()

        let persisted = try taskService.readHeartbeat(taskId: task.id)
        #expect(persisted.contains("- [required] Which account should I use?"))
        #expect(store.runStatusMessage == "Run needs clarification. HEARTBEAT.md was updated with follow-up questions.")
    }
}
