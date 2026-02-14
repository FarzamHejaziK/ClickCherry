import Foundation

struct FinishedRecordingReview: Identifiable, Equatable {
    enum Mode: Equatable {
        case newTaskStaging
        case existingTask(taskId: String)
    }

    let id: String
    let recording: RecordingRecord
    let mode: Mode

    init(recording: RecordingRecord, mode: Mode) {
        self.id = recording.id
        self.recording = recording
        self.mode = mode
    }
}

