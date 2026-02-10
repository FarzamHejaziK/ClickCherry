import Foundation
import Testing
@testable import TaskAgentMacOSApp

private enum MockToolLoopError: Error {
    case failed
}

private final class MockDesktopExecutor: DesktopActionExecutor {
    func openApp(named appName: String) throws {}
    func openURL(_ url: URL) throws {}
    func sendShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws {}
    func typeText(_ text: String) throws {}
    func click(x: Int, y: Int) throws {}
    func moveMouse(x: Int, y: Int) throws {}
    func rightClick(x: Int, y: Int) throws {}
    func scroll(deltaX: Int, deltaY: Int) throws {}
}

private final class MockToolLoopRunner: LLMExecutionToolLoopRunner {
    var nextResult: AutomationRunResult
    var nextError: Error?
    private(set) var receivedMarkdowns: [String] = []

    init(nextResult: AutomationRunResult, nextError: Error? = nil) {
        self.nextResult = nextResult
        self.nextError = nextError
    }

    func runToolLoop(taskMarkdown: String, executor: any DesktopActionExecutor) async throws -> AutomationRunResult {
        receivedMarkdowns.append(taskMarkdown)
        if let nextError {
            throw nextError
        }
        return nextResult
    }
}

struct AnthropicAutomationEngineTests {
    @Test
    func runReturnsRunnerResultWhenToolLoopSucceeds() async {
        let expected = AutomationRunResult(
            outcome: .success,
            executedSteps: ["Type text 'hello'"],
            generatedQuestions: [],
            errorMessage: nil,
            llmSummary: "Done"
        )
        let runner = MockToolLoopRunner(nextResult: expected)
        let engine = AnthropicAutomationEngine(runner: runner, executor: MockDesktopExecutor())

        let result = await engine.run(taskMarkdown: "# Task\nType hello")

        #expect(result == expected)
        #expect(runner.receivedMarkdowns == ["# Task\nType hello"])
    }

    @Test
    func runMapsAnthropicErrorToFailedResult() async {
        let runner = MockToolLoopRunner(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            ),
            nextError: AnthropicExecutionPlannerError.missingAPIKey
        )
        let engine = AnthropicAutomationEngine(runner: runner, executor: MockDesktopExecutor())

        let result = await engine.run(taskMarkdown: "# Task")

        #expect(result.outcome == .failed)
        #expect(result.errorMessage == AnthropicExecutionPlannerError.missingAPIKey.errorDescription)
    }

    @Test
    func runMapsUnknownErrorToFailedResult() async {
        let runner = MockToolLoopRunner(
            nextResult: AutomationRunResult(
                outcome: .success,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            ),
            nextError: MockToolLoopError.failed
        )
        let engine = AnthropicAutomationEngine(runner: runner, executor: MockDesktopExecutor())

        let result = await engine.run(taskMarkdown: "# Task")

        #expect(result.outcome == .failed)
        #expect(result.errorMessage == "Failed during execution tool loop.")
    }
}
