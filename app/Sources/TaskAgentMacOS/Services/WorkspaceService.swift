import Foundation

struct WorkspaceService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func initializeWorkspace(baseDir: URL, taskId: String) throws -> TaskWorkspace {
        let root = baseDir.appendingPathComponent("workspace-\(taskId)", isDirectory: true)
        let recordingsDir = root.appendingPathComponent("recordings", isDirectory: true)
        let runsDir = root.appendingPathComponent("runs", isDirectory: true)
        let heartbeatFile = root.appendingPathComponent("HEARTBEAT.md", isDirectory: false)

        try createDirIfNeeded(root)
        try createDirIfNeeded(recordingsDir)
        try createDirIfNeeded(runsDir)

        if !fileManager.fileExists(atPath: heartbeatFile.path) {
            let initial = "# Task\n\n## Questions\n"
            try initial.write(to: heartbeatFile, atomically: true, encoding: .utf8)
        }

        return TaskWorkspace(
            taskId: taskId,
            root: root,
            heartbeatFile: heartbeatFile,
            recordingsDir: recordingsDir,
            runsDir: runsDir
        )
    }

    private func createDirIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
