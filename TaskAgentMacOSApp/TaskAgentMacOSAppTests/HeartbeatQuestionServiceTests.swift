import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct HeartbeatQuestionServiceTests {
    @Test
    func parseQuestionsReturnsUnresolvedAndResolvedQuestions() {
        let markdown = """
        # Task
        Example task

        ## Questions
        - [required] Which account should be used?
        - [x] What date range should be used?
          Answer: Use current month.
        - [ ] Should we upload receipts?
        """

        let service = HeartbeatQuestionService()
        let questions = service.parseQuestions(from: markdown)

        #expect(questions.count == 3)
        #expect(questions[0].prompt == "Which account should be used?")
        #expect(!questions[0].isResolved)
        #expect(questions[1].isResolved)
        #expect(questions[1].answer == "Use current month.")
        #expect(questions[2].prompt == "Should we upload receipts?")
    }

    @Test
    func parseQuestionsReturnsEmptyForNoneMarker() {
        let markdown = """
        # Task
        Example task

        ## Questions
        - None.
        """

        let service = HeartbeatQuestionService()
        let questions = service.parseQuestions(from: markdown)

        #expect(questions.isEmpty)
    }

    @Test
    func applyAnswerMarksQuestionResolvedAndPersistsAnswerLine() throws {
        let markdown = """
        # Task
        Example task

        ## Questions
        - [required] Which account should be used?
        - [ ] Should we upload receipts?
        """
        let service = HeartbeatQuestionService()
        let questions = service.parseQuestions(from: markdown)
        let firstQuestionID = try #require(questions.first?.id)

        let updated = try service.applyAnswer("Use the finance admin account.", to: firstQuestionID, in: markdown)

        #expect(updated.contains("- [x] Which account should be used?"))
        #expect(updated.contains("Answer: Use the finance admin account."))
    }

    @Test
    func applyAnswerReplacesExistingAnswerLine() throws {
        let markdown = """
        # Task
        Example task

        ## Questions
        - [x] Which account should be used?
          Answer: Old answer.
        """
        let service = HeartbeatQuestionService()
        let questionID = try #require(service.parseQuestions(from: markdown).first?.id)

        let updated = try service.applyAnswer("New answer.", to: questionID, in: markdown)

        #expect(updated.contains("Answer: New answer."))
        #expect(!updated.contains("Answer: Old answer."))
    }

    @Test
    func applyAnswerThrowsOnEmptyAnswer() throws {
        let markdown = """
        # Task
        Example task

        ## Questions
        - [ ] Which account should be used?
        """
        let service = HeartbeatQuestionService()
        let questionID = try #require(service.parseQuestions(from: markdown).first?.id)

        do {
            _ = try service.applyAnswer("   ", to: questionID, in: markdown)
            #expect(Bool(false))
        } catch {
            #expect(error as? HeartbeatQuestionServiceError == .answerEmpty)
        }
    }
}
