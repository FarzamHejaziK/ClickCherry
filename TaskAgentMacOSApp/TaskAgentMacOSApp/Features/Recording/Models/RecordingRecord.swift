import Foundation

struct RecordingRecord: Equatable, Identifiable {
    let id: String
    let fileName: String
    let addedAt: Date
    let fileURL: URL
    let fileSizeBytes: Int64
}
