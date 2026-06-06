import Foundation

struct ScheduledTask: Identifiable, Equatable, Hashable {
    let id: UUID
    let enrollmentID: UUID
    let taskKey: String
    let taskVersion: Int
    let scheduledFor: Date
    let windowStart: Date
    let windowEnd: Date
    let status: ScheduledTaskStatus
    let dayIndex: Int
    let slotIndex: Int
    let completedAt: Date?

    func isStartable(at date: Date = Date()) -> Bool {
        status == .scheduled && date >= windowStart && date <= windowEnd
    }
}

enum ScheduledTaskStatus: Equatable, Hashable {
    case scheduled
    case completed
    case missed
    case skipped
    case cancelled
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scheduled":
            self = .scheduled
        case "completed":
            self = .completed
        case "missed":
            self = .missed
        case "skipped":
            self = .skipped
        case "cancelled":
            self = .cancelled
        default:
            self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .scheduled:
            return "scheduled"
        case .completed:
            return "completed"
        case .missed:
            return "missed"
        case .skipped:
            return "skipped"
        case .cancelled:
            return "cancelled"
        case .unknown(let raw):
            return raw
        }
    }
}
