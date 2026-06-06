import Foundation

struct LoudnessMatchSubmission: Equatable {
    let startedAt: Date
    let completedAt: Date
    let matchedLevel: Double
    let gating: [String: JSONValue]
    let rawPayload: [String: JSONValue]
    let deviceInfo: [String: JSONValue]
    let headphoneInfo: [String: JSONValue]
    let appVersion: String?
    let calibrationVersion: String?
}
