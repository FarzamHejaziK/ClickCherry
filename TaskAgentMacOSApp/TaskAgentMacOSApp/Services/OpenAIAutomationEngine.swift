import Foundation

struct OpenAIAutomationEngine: AutomationEngine {
    private let runner: any LLMExecutionToolLoopRunner
    private let executor: any DesktopActionExecutor

    init(
        runner: any LLMExecutionToolLoopRunner,
        executor: any DesktopActionExecutor = SystemDesktopActionExecutor()
    ) {
        self.runner = runner
        self.executor = executor
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        do {
            return try await runner.runToolLoop(taskMarkdown: taskMarkdown, executor: executor)
        } catch let error as OpenAIExecutionPlannerError {
            let userFacingIssue: LLMUserFacingIssue?
            if case .userFacingIssue(let issue) = error {
                userFacingIssue = issue
            } else {
                userFacingIssue = nil
            }
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: error.errorDescription,
                llmSummary: nil,
                llmUserFacingIssue: userFacingIssue
            )
        } catch is CancellationError {
            return AutomationRunResult(
                outcome: .cancelled,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Cancelled by user.",
                llmUserFacingIssue: nil
            )
        } catch {
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: "Failed during execution tool loop.",
                llmSummary: nil,
                llmUserFacingIssue: nil
            )
        }
    }
}
