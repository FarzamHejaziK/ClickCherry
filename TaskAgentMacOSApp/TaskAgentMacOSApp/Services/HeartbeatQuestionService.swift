import Foundation

struct HeartbeatQuestion: Identifiable, Equatable {
    let id: String
    let lineIndex: Int
    let prompt: String
    let isResolved: Bool
    let answer: String?
}

enum HeartbeatQuestionServiceError: Error, Equatable {
    case questionsSectionMissing
    case questionNotFound
    case answerEmpty
}

struct HeartbeatQuestionService {
    func parseQuestions(from markdown: String) -> [HeartbeatQuestion] {
        let lines = markdown.components(separatedBy: .newlines)
        guard let section = questionsSectionRange(in: lines) else {
            return []
        }

        var questions: [HeartbeatQuestion] = []
        var index = section.start

        while index < section.end {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.caseInsensitiveCompare("- None.") == .orderedSame {
                return []
            }

            guard let parsed = parseQuestionLine(trimmed) else {
                index += 1
                continue
            }

            let questionLineIndex = index
            var answer: String? = nil
            if index + 1 < section.end {
                let nextTrimmed = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if nextTrimmed.lowercased().hasPrefix("answer:") {
                    let answerText = String(nextTrimmed.dropFirst("answer:".count)).trimmingCharacters(in: .whitespaces)
                    answer = answerText.isEmpty ? nil : answerText
                    index += 1
                }
            }

            questions.append(
                HeartbeatQuestion(
                    id: questionID(for: questionLineIndex),
                    lineIndex: questionLineIndex,
                    prompt: parsed.prompt,
                    isResolved: parsed.isResolved,
                    answer: answer
                )
            )
            index += 1
        }

        return questions
    }

    func applyAnswer(_ rawAnswer: String, to questionID: String, in markdown: String) throws -> String {
        let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            throw HeartbeatQuestionServiceError.answerEmpty
        }

        var lines = markdown.components(separatedBy: .newlines)
        guard let section = questionsSectionRange(in: lines) else {
            throw HeartbeatQuestionServiceError.questionsSectionMissing
        }

        let questions = parseQuestions(from: markdown)
        guard let question = questions.first(where: { $0.id == questionID }) else {
            throw HeartbeatQuestionServiceError.questionNotFound
        }

        let questionLineIndex = question.lineIndex
        guard questionLineIndex >= section.start && questionLineIndex < section.end else {
            throw HeartbeatQuestionServiceError.questionNotFound
        }

        lines[questionLineIndex] = "- [x] \(question.prompt)"
        let answerLine = "  Answer: \(answer)"
        let nextLineIndex = questionLineIndex + 1

        if nextLineIndex < section.end {
            let nextTrimmed = lines[nextLineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if nextTrimmed.lowercased().hasPrefix("answer:") {
                lines[nextLineIndex] = answerLine
            } else {
                lines.insert(answerLine, at: nextLineIndex)
            }
        } else {
            lines.append(answerLine)
        }

        let hadTrailingNewline = markdown.hasSuffix("\n")
        var updated = lines.joined(separator: "\n")
        if hadTrailingNewline {
            updated.append("\n")
        }
        return updated
    }

    private func questionID(for lineIndex: Int) -> String {
        "question-\(lineIndex)"
    }

    private func questionsSectionRange(in lines: [String]) -> (start: Int, end: Int)? {
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "## questions"
        }) else {
            return nil
        }

        let contentStart = headerIndex + 1
        if contentStart >= lines.count {
            return (start: lines.count, end: lines.count)
        }

        let remainder = lines[contentStart...]
        let nextHeader = remainder.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
        })

        let end = nextHeader ?? lines.count
        return (start: contentStart, end: end)
    }

    private func parseQuestionLine(_ trimmedLine: String) -> (prompt: String, isResolved: Bool)? {
        guard trimmedLine.hasPrefix("-") else {
            return nil
        }

        var content = String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            return nil
        }
        if content.lowercased().hasPrefix("answer:") {
            return nil
        }

        var isResolved = false
        if content.lowercased().hasPrefix("[x]") {
            isResolved = true
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if content.lowercased().hasPrefix("[ ]") {
            content = String(content.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tagPrefixes = ["[required]", "[optional]", "[open]", "[resolved]"]
        for tag in tagPrefixes where content.lowercased().hasPrefix(tag) {
            content = String(content.dropFirst(tag.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        guard !content.isEmpty else {
            return nil
        }

        return (prompt: content, isResolved: isResolved)
    }
}
