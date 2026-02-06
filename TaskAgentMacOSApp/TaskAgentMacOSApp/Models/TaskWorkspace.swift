import Foundation

struct TaskWorkspace: Equatable {
    let taskId: String
    let root: URL
    let heartbeatFile: URL
    let recordingsDir: URL
    let runsDir: URL
}
