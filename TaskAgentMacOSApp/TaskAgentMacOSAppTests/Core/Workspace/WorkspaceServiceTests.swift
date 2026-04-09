import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct WorkspaceServiceTests {
    @Test
    func initializeWorkspaceCreatesExpectedLayout() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = WorkspaceService(fileManager: fm)
        let workspace = try service.initializeWorkspace(baseDir: tempRoot, taskId: "demo")

        #expect(fm.fileExists(atPath: workspace.root.path))
        #expect(fm.fileExists(atPath: workspace.recordingsDir.path))
        #expect(fm.fileExists(atPath: workspace.runsDir.path))
        #expect(fm.fileExists(atPath: workspace.heartbeatFile.path))

        let heartbeatText = try String(contentsOf: workspace.heartbeatFile, encoding: .utf8)
        #expect(heartbeatText.contains("# Task"))
        #expect(heartbeatText.contains("## Questions"))
    }

    @Test
    func initializeWorkspaceIsIdempotent() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = WorkspaceService(fileManager: fm)

        _ = try service.initializeWorkspace(baseDir: tempRoot, taskId: "demo")
        let second = try service.initializeWorkspace(baseDir: tempRoot, taskId: "demo")

        #expect(fm.fileExists(atPath: second.heartbeatFile.path))
    }
}
