import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct MCPMessageFramerTests {
    @Test
    func framesAndParsesSingleMessage() throws {
        let body = Data("{\"hello\":\"world\"}".utf8)
        let framed = MCPMessageFramer.frame(body)

        var framer = MCPMessageFramer()
        let messages = try framer.append(framed)

        #expect(messages == [body])
    }

    @Test
    func parsesFragmentedMessagesAcrossMultipleChunks() throws {
        let firstBody = Data("{\"id\":1}".utf8)
        let secondBody = Data("{\"id\":2}".utf8)
        var framed = MCPMessageFramer.frame(firstBody)
        framed.append(MCPMessageFramer.frame(secondBody))

        let firstFrameLength = MCPMessageFramer.frame(firstBody).count
        let splitIndex = max(1, firstFrameLength - 3)
        let firstChunk = framed.subdata(in: 0..<splitIndex)
        let secondChunk = framed.subdata(in: splitIndex..<framed.count)

        var framer = MCPMessageFramer()
        let firstPass = try framer.append(firstChunk)
        #expect(firstPass.isEmpty)

        let secondPass = try framer.append(secondChunk)
        #expect(secondPass == [firstBody, secondBody])
    }
}
