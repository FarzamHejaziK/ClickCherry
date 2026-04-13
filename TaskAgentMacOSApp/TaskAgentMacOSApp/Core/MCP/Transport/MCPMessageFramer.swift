import Foundation

nonisolated enum MCPMessageFramerError: Error, Equatable {
    case invalidHeader
    case missingContentLength
    case invalidContentLength
}

nonisolated struct MCPMessageFramer {
    private static let separator = Data("\r\n\r\n".utf8)
    private var buffer = Data()

    mutating func append(_ chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)

        var messages: [Data] = []
        while let headerRange = buffer.range(of: Self.separator) {
            let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
            let bodyStart = headerRange.upperBound
            let contentLength = try parseContentLength(from: headerData)

            guard buffer.count >= bodyStart + contentLength else {
                break
            }

            let bodyRange = bodyStart..<(bodyStart + contentLength)
            messages.append(buffer.subdata(in: bodyRange))
            buffer.removeSubrange(0..<bodyRange.upperBound)
        }

        return messages
    }

    func frame(_ payload: Data) -> Data {
        Self.frame(payload)
    }

    static func frame(_ payload: Data) -> Data {
        var data = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        data.append(payload)
        return data
    }

    private func parseContentLength(from headerData: Data) throws -> Int {
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw MCPMessageFramerError.invalidHeader
        }

        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" {
                guard let length = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw MCPMessageFramerError.invalidContentLength
                }
                return length
            }
        }

        throw MCPMessageFramerError.missingContentLength
    }
}
