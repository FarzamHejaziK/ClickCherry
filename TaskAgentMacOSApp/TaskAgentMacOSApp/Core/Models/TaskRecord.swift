import Foundation

struct TaskRecord: Equatable, Identifiable {
    let id: String
    let title: String
    let createdAt: Date
    let workspace: TaskWorkspace
}
