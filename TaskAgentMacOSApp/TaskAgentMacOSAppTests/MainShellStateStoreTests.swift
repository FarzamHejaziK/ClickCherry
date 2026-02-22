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
    var displays: [CaptureDisplayOption] = [CaptureDisplayOption(id: 1, label: "Display 1", screencaptureDisplayIndex: 1)]
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
    var windowNumber: Int? = nil

    func showBorder(displayID: Int) {
        shownDisplayIDs.append(displayID)
    }

    func hideBorder() {
        hideCallCount += 1
    }

    func windowNumberForScreenshotExclusion() -> Int? {
        windowNumber
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

private final class BlockingStoreLLMClient: LLMClient {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var shouldThrowNotConfigured = false
    private var pendingOutput: String?
    private var pendingError: Error?

    func setNotConfigured(_ value: Bool) {
        lock.lock()
        shouldThrowNotConfigured = value
        lock.unlock()
    }

    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String {
        lock.lock()
        let throwNotConfigured = shouldThrowNotConfigured
        lock.unlock()
        if throwNotConfigured {
            throw LLMClientError.notConfigured
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            lock.lock()
            if let error = pendingError {
                pendingError = nil
                lock.unlock()
                cont.resume(throwing: error)
                return
            }
            if let output = pendingOutput {
                pendingOutput = nil
                lock.unlock()
                cont.resume(returning: output)
                return
            }
            continuation = cont
            lock.unlock()
        }
    }

    func finish(with output: String) {
        lock.lock()
        let cont = continuation
        continuation = nil
        if cont == nil {
            pendingOutput = output
            pendingError = nil
        }
        lock.unlock()
        cont?.resume(returning: output)
    }

    func fail(with error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        if cont == nil {
            pendingError = error
            pendingOutput = nil
        }
        lock.unlock()
        cont?.resume(throwing: error)
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

private final class ConfigurablePermissionService: PermissionService {
    var screenRecording: PermissionGrantStatus = .granted
    var microphone: PermissionGrantStatus = .granted
    var accessibility: PermissionGrantStatus = .granted
    var inputMonitoring: PermissionGrantStatus = .granted

    func openSystemSettings(for permission: AppPermission) {}

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            return screenRecording
        case .microphone:
            return microphone
        case .accessibility:
            return accessibility
        case .inputMonitoring:
            return inputMonitoring
        }
    }

    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        currentStatus(for: permission)
    }
}

private final class MockAgentControlOverlayService: AgentControlOverlayService {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var shownDisplayIDs: [Int?] = []

    func showAgentInControl(displayID: Int?) {
        showCount += 1
        shownDisplayIDs.append(displayID)
    }

    func hideAgentInControl() {
        hideCount += 1
    }

    func windowNumberForScreenshotExclusion() -> Int? {
        nil
    }
}

private final class MockUserInterruptionMonitor: UserInterruptionMonitor {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var shouldStartSucceed = true
    private var handler: (() -> Void)?

    func start(onUserInterruption: @escaping () -> Void) -> Bool {
        startCount += 1
        handler = onUserInterruption
        return shouldStartSucceed
    }

    func stop() {
        stopCount += 1
    }

    func triggerUserInterruption() {
        handler?()
    }
}

private final class MockAgentCursorPresentationService: AgentCursorPresentationService {
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0
    var shouldActivateSucceed = true
    var shouldDeactivateSucceed = true

    func activateTakeoverCursor() -> Bool {
        activateCount += 1
        return shouldActivateSucceed
    }

    func deactivateTakeoverCursor() -> Bool {
        deactivateCount += 1
        return shouldDeactivateSucceed
    }
}

private final class BlockingAutomationEngine: AutomationEngine {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AutomationRunResult, Never>?
    private var didStartRun = false
    private var pendingResult: AutomationRunResult?

    func run(taskMarkdown: String) async -> AutomationRunResult {
        lock.lock()
        didStartRun = true
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            return pendingResult
        }
        lock.unlock()

        return await withCheckedContinuation { continuation in
            self.lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                self.lock.unlock()
                continuation.resume(returning: pendingResult)
                return
            }
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func finish(with result: AutomationRunResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()

        continuation?.resume(returning: result)
    }

    func hasStarted() -> Bool {
        lock.lock()
        let value = didStartRun
        lock.unlock()
        return value
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
    func startAndStopCaptureUpdatesCaptureState() async throws {
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-key"]),
            permissionService: AlwaysGrantedPermissionService(),
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
        // Capture launch is off-main; wait for the mock to observe start.
        for _ in 0..<50 {
            if captureService.startedOutputURL != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(captureService.startedOutputURL != nil)
        #expect(captureService.startedDisplayID == 1)
        #expect(captureService.startedAudioInput == .device(42))
        #expect(overlayService.shownDisplayIDs == [1])

        store.stopCapture()
        for _ in 0..<100 {
            if !store.isCapturing { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!store.isCapturing)
        #expect(store.recordingStatusMessage == "Capture stopped.")
        #expect(overlayService.hideCallCount == 1)
    }

    @Test
    func startCaptureShowsPermissionErrorWhenDenied() async throws {
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()
        store.startCapture()

        // Failure is surfaced async.
        for _ in 0..<50 {
            if store.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!store.isCapturing)
        #expect(store.errorMessage == "Screen Recording permission denied. Grant access in System Settings and retry.")
        #expect(overlayService.hideCallCount == 1)
    }

    @Test
    func startCaptureRefreshesInvalidDisplaySelectionBeforeShowingBorder() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Invalid display selection task")
        let captureService = MockRecordingCaptureService()
        captureService.displays = [
            CaptureDisplayOption(id: 1001, label: "Display 1", screencaptureDisplayIndex: 1),
            CaptureDisplayOption(id: 1002, label: "Display 2", screencaptureDisplayIndex: 2)
        ]
        let overlayService = MockRecordingOverlayService()

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.selectedCaptureDisplayID = 99

        store.startCapture()
        for _ in 0..<50 {
            if captureService.startedDisplayID != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(captureService.startedDisplayID == 1)
        #expect(overlayService.shownDisplayIDs == [1])
        #expect(store.errorMessage == nil)
    }

    @Test
    func startCaptureShowsCombinedRecordingPreflightDialogForMissingItems() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Preflight task")
        let permissionService = ConfigurablePermissionService()
        permissionService.screenRecording = .granted
        permissionService.microphone = .notGranted
        permissionService.inputMonitoring = .notGranted

        let store = MainShellStateStore(
            taskService: service,
            apiKeyStore: MockAPIKeyStore(),
            permissionService: permissionService,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()

        store.startCapture()

        #expect(!store.isCapturing)
        #expect(store.recordingPreflightDialogState != nil)
        #expect(
            store.recordingPreflightDialogState?.missingRequirements ==
                [.geminiAPIKey, .microphone]
        )
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-test-key"]),
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-test-key"]),
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-test-key"]),
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
    func extractFromFinishedRecordingCreatesTaskOnlyAfterExtractionReturns() async throws {
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

        let stagedURL = tempRoot.appendingPathComponent("staged.mov", isDirectory: false)
        try Data("mov".utf8).write(to: stagedURL)
        let staged = RecordingRecord(
            id: stagedURL.lastPathComponent,
            fileName: stagedURL.lastPathComponent,
            addedAt: Date(),
            fileURL: stagedURL,
            fileSizeBytes: 3
        )

        let llm = BlockingStoreLLMClient()
        let extractionService = TaskExtractionService(
            fileManager: fm,
            promptCatalog: PromptCatalogService(promptsRootURL: promptsRoot, fileManager: fm),
            llmClient: llm
        )
        let store = MainShellStateStore(
            taskService: taskService,
            taskExtractionService: extractionService,
            apiKeyStore: MockAPIKeyStore(initialValues: [.gemini: "gemini-test-key"]),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.finishedRecordingReview = FinishedRecordingReview(recording: staged, mode: .newTaskStaging)
        store.extractTaskFromFinishedRecordingDialog()

        await waitUntil(timeoutSeconds: 2.0) {
            store.isExtractingTask
        }
        #expect(store.isExtractingTask)

        let workspacesBefore = try fm.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("workspace-") }
        #expect(workspacesBefore.isEmpty)

        llm.finish(with: """
        # Task
        TaskDetected: true
        Status: TASK_FOUND
        NoTaskReason: NONE
        Title: Extracted Title
        Goal: Do something.

        ## Questions
        - None.
        """)

        await waitUntil(timeoutSeconds: 5.0) {
            store.selectedTaskID != nil
        }

        #expect(store.selectedTaskID != nil)
        #expect(store.finishedRecordingReview == nil)

        let workspacesAfter = try fm.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("workspace-") }
        #expect(workspacesAfter.count == 1)

        let createdTaskId = try #require(store.selectedTaskID)
        let heartbeat = try taskService.readHeartbeat(taskId: createdTaskId)
        #expect(heartbeat.contains("# Task"))
        #expect(heartbeat.contains("Extracted Title"))
        // Title line is normalized to a plain title for task-list parsing.
        #expect(heartbeat.contains("\nExtracted Title\n"))
    }

    @Test
    func extractTaskWithoutGeminiKeyShowsSettingsDialog() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Needs Gemini key")
        let sourceRecording = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: sourceRecording)
        _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceRecording)
        let recording = try #require(taskService.listRecordings(taskId: task.id).first)

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.extractTask(from: recording)

        #expect(store.isExtractingTask == false)
        #expect(store.missingProviderKeyDialog?.provider == .gemini)
        #expect(store.missingProviderKeyDialog?.action == .extractTask)
    }

    @Test
    @MainActor
    func startRunTaskNowWithoutOpenAIKeyShowsRunPreflightDialog() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Needs OpenAI key")
        let engine = MockAutomationEngine(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
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
        store.startRunTaskNow()

        #expect(store.isRunningTask == false)
        #expect(store.runTaskPreflightDialogState != nil)
        #expect(store.runTaskPreflightDialogState?.missingRequirements == [.openAIAPIKey])
        #expect(engine.receivedMarkdowns.isEmpty)
    }

    @Test
    @MainActor
    func startRunTaskNowWithMissingAccessibilityShowsRunPreflightDialog() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Needs accessibility")
        let engine = MockAutomationEngine(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )
        let permissionService = ConfigurablePermissionService()
        permissionService.accessibility = .notGranted

        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
            permissionService: permissionService,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.selectTask(task.id)
        store.startRunTaskNow()

        #expect(store.isRunningTask == false)
        #expect(store.runTaskPreflightDialogState?.missingRequirements == [.accessibility])
        #expect(engine.receivedMarkdowns.isEmpty)
    }

    @Test
    func openSettingsForMissingProviderKeyDialogRoutesToSettings() throws {
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
            apiKeyStore: MockAPIKeyStore()
        )

        store.missingProviderKeyDialog = MissingProviderKeyDialog(provider: .openAI, action: .runTask)
        store.openSettingsForMissingProviderKeyDialog()

        #expect(store.route == .settings)
        #expect(store.missingProviderKeyDialog == nil)
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
        #expect(store.apiKeyErrorMessage == "OpenAI API key is not saved.")
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        _ condition: @escaping @Sendable () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
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

        let saved = store.saveProviderKey("   ", for: .openAI)
        #expect(!saved)
        #expect(!store.providerSetupState.hasOpenAIKey)
        #expect(store.apiKeyStatusMessage == nil)
        #expect(store.apiKeyErrorMessage == "API key cannot be empty.")
    }

    @Test
    func pinningTaskShowsPinnedOnTop() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let suiteName = "MainShellStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            userDefaults: defaults,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        let a = try taskService.createTask(title: "Task A")
        // Ensure a different createdAt ordering.
        Thread.sleep(forTimeInterval: 0.01)
        let b = try taskService.createTask(title: "Task B")

        store.reloadTasks()
        #expect(store.tasks.first?.id == b.id)

        store.togglePinned(taskID: a.id)
        store.reloadTasks()
        #expect(store.tasks.first?.id == a.id)
    }

    @Test
    func deletingPinnedTaskUnpinsAndRemovesIt() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let suiteName = "MainShellStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            userDefaults: defaults,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        let task = try taskService.createTask(title: "Task A")
        store.reloadTasks()
        store.togglePinned(taskID: task.id)
        #expect(store.isTaskPinned(task.id))

        store.requestDeleteTask(taskID: task.id)
        store.confirmDeleteTask()

        store.reloadTasks()
        #expect(!store.tasks.contains(where: { $0.id == task.id }))
        #expect(!store.isTaskPinned(task.id))
    }

    @Test
    func resetOnboardingClearsCompletionFlagAndPostsNotification() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let suiteName = "MainShellStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "onboarding.completed")

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            userDefaults: defaults,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .clickCherryResetOnboardingRequested,
            object: nil,
            queue: nil
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.resetOnboardingAndReturnToSetup()

        #expect(defaults.bool(forKey: "onboarding.completed") == false)
        #expect(received)
    }

    @Test
    func resetSetupClearsProviderKeysAndPostsOnboardingResetNotification() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let suiteName = "MainShellStateStoreResetSetup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "onboarding.completed")

        let keyStore = MockAPIKeyStore(initialValues: [
            .openAI: "openai-secret",
            .gemini: "gemini-secret"
        ])
        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: keyStore,
            userDefaults: defaults,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        var received = false
        let token = NotificationCenter.default.addObserver(
            forName: .clickCherryResetOnboardingRequested,
            object: nil,
            queue: nil
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.resetSetupAndReturnToOnboarding()

        #expect(defaults.bool(forKey: "onboarding.completed") == false)
        #expect(received)
        #expect(try keyStore.readKey(for: .openAI) == nil)
        #expect(try keyStore.readKey(for: .gemini) == nil)
        #expect(store.providerSetupState.hasOpenAIKey == false)
        #expect(store.providerSetupState.hasGeminiKey == false)
    }

    @Test
    func deletingSelectedTaskReturnsToNewTaskAndClearsState() throws {
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

        let task = try taskService.createTask(title: "Task A")
        store.reloadTasks()
        store.openTask(task.id)
        #expect(store.route == .task(task.id))
        #expect(store.selectedTaskID == task.id)
        #expect(!store.heartbeatMarkdown.isEmpty)

        store.requestDeleteTask(taskID: task.id)
        store.confirmDeleteTask()

        #expect(store.route == .newTask)
        #expect(store.selectedTaskID == nil)
        #expect(store.heartbeatMarkdown.isEmpty)
    }

    @Test
    func reopeningTaskLoadsPersistedRunHistory() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Persisted run history task")

        let started = Date(timeIntervalSince1970: 1_700_000_123)
        let run = AgentRunRecord(
            id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
            startedAt: started,
            finishedAt: started.addingTimeInterval(1),
            outcome: .failed,
            displayIndex: 1,
            events: [
                AgentRunEvent(
                    id: UUID(uuidString: "aaaaaaaa-1111-2222-3333-444444444444")!,
                    timestamp: started,
                    kind: .error,
                    message: "Something went wrong"
                )
            ]
        )
        _ = try taskService.saveAgentRunLog(taskId: task.id, run: run)

        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: MockAPIKeyStore(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )

        store.reloadTasks()
        store.openTask(task.id)
        #expect(store.runHistory == [run])
    }

    @Test
    @MainActor
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
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
        // A run writes a human-readable summary plus a persisted structured run log.
        #expect(runFiles.contains(where: { $0.pathExtension.lowercased() == "md" }))
        #expect(runFiles.contains(where: { $0.pathExtension.lowercased() == "json" }))
    }

    @Test
    @MainActor
    func runTaskNowPreparesDesktopBeforeExecution() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Prepare desktop task")
        let engine = MockAutomationEngine(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )

        var prepareCalls = 0
        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService(),
            prepareDesktopForRun: {
                prepareCalls += 1
                return 3
            }
        )

        store.reloadTasks()
        store.selectTask(task.id)
        await store.runTaskNow()

        #expect(prepareCalls == 1)
        var sawPrepareTrace = store.executionTrace.contains(where: { $0.message.contains("Prepared screen by hiding 3 running app(s).") })
        if !sawPrepareTrace {
            for _ in 0..<20 {
                await Task.yield()
                sawPrepareTrace = store.executionTrace.contains(where: { $0.message.contains("Prepared screen by hiding 3 running app(s).") })
                if sawPrepareTrace { break }
            }
        }
        #expect(sawPrepareTrace)
    }

    @Test
    @MainActor
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
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
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

    @Test
    @MainActor
    func startRunTaskNowShowsOverlayAndCancelsOnEscapeKey() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Agent control cancel task")

        let engine = BlockingAutomationEngine()
        let overlay = MockAgentControlOverlayService()
        let borderOverlay = MockRecordingOverlayService()
        let monitor = MockUserInterruptionMonitor()
        let cursorPresentation = MockAgentCursorPresentationService()

        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: MockRecordingCaptureService(),
            overlayService: borderOverlay,
            agentControlOverlayService: overlay,
            userInterruptionMonitor: monitor,
            agentCursorPresentationService: cursorPresentation
        )

        store.reloadTasks()
        store.selectTask(task.id)

        store.startRunTaskNow()
        #expect(store.isRunningTask == true)
        #expect(overlay.showCount == 1)
        #expect(borderOverlay.shownDisplayIDs == [1])
        #expect(monitor.startCount == 1)
        #expect(cursorPresentation.activateCount == 1)

        monitor.triggerUserInterruption()
        await Task.yield()

        #expect(store.runStatusMessage == "Cancelling (Escape pressed)...")
        #expect(overlay.hideCount >= 1)
        #expect(borderOverlay.hideCallCount >= 1)
        #expect(monitor.stopCount >= 1)
        #expect(cursorPresentation.deactivateCount >= 1)

        engine.finish(
            with: AutomationRunResult(
                outcome: .cancelled,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )

        for _ in 0..<50 {
            if store.isRunningTask == false { break }
            await Task.yield()
        }
        #expect(store.isRunningTask == false)
        #expect(store.runStatusMessage == "Run cancelled.")
    }

    @Test
    @MainActor
    func startRunTaskNowUsesSelectedDisplayScreencaptureIndexForBothOverlays() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Selected run display task")

        let captureService = MockRecordingCaptureService()
        captureService.displays = [
            CaptureDisplayOption(id: 1001, label: "Display 1", screencaptureDisplayIndex: 1),
            CaptureDisplayOption(id: 1002, label: "Display 2", screencaptureDisplayIndex: 2)
        ]
        let overlay = MockAgentControlOverlayService()
        let borderOverlay = MockRecordingOverlayService()
        let monitor = MockUserInterruptionMonitor()
        monitor.shouldStartSucceed = false

        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: BlockingAutomationEngine(),
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: captureService,
            overlayService: borderOverlay,
            agentControlOverlayService: overlay,
            userInterruptionMonitor: monitor
        )

        store.reloadTasks()
        store.selectTask(task.id)
        store.refreshCaptureDisplays()
        store.selectedRunDisplayID = 1002

        store.startRunTaskNow()

        #expect(borderOverlay.shownDisplayIDs == [2])
        #expect(overlay.shownDisplayIDs == [2])
        #expect(store.isRunningTask == true)
        #expect(store.errorMessage == nil)

        store.stopRunTask()
    }

    @Test
    @MainActor
    func startRunTaskNowMonitorFailureDoesNotBlockRun() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Agent monitor failure task")

        let engine = BlockingAutomationEngine()
        let overlay = MockAgentControlOverlayService()
        let borderOverlay = MockRecordingOverlayService()
        let monitor = MockUserInterruptionMonitor()
        monitor.shouldStartSucceed = false
        let cursorPresentation = MockAgentCursorPresentationService()

        let store = MainShellStateStore(
            taskService: taskService,
            automationEngine: engine,
            apiKeyStore: MockAPIKeyStore(initialValues: [.openAI: "openai-test-key"]),
            permissionService: AlwaysGrantedPermissionService(),
            captureService: MockRecordingCaptureService(),
            overlayService: borderOverlay,
            agentControlOverlayService: overlay,
            userInterruptionMonitor: monitor,
            agentCursorPresentationService: cursorPresentation
        )

        store.reloadTasks()
        store.selectTask(task.id)
        store.startRunTaskNow()

        #expect(store.isRunningTask == true)
        #expect(cursorPresentation.activateCount == 1)
        #expect(borderOverlay.shownDisplayIDs == [1])
        #expect(borderOverlay.hideCallCount == 0)
        #expect(cursorPresentation.deactivateCount == 0)
        #expect(overlay.showCount == 1)
        #expect(overlay.hideCount == 0)
        #expect(store.errorMessage == nil)

        store.stopRunTask()
        #expect(borderOverlay.hideCallCount == 1)
        #expect(cursorPresentation.deactivateCount == 1)
        #expect(overlay.hideCount == 1)
    }
}
