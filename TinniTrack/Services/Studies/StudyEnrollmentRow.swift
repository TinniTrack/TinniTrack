import Foundation

nonisolated struct StudyEnrollmentRow: Decodable, Sendable {
    let id: UUID
    let userID: UUID
    let studyID: UUID
    let status: String
    let enrolledAt: String?
    let createdAt: String?
    let onboardingCompletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case studyID = "study_id"
        case status
        case enrolledAt = "enrolled_at"
        case createdAt = "created_at"
        case onboardingCompletedAt = "onboarding_completed_at"
    }

    func toDomain() -> StudyEnrollment {
        StudyEnrollment(
            id: id,
            userID: userID,
            studyID: studyID,
            status: StudyEnrollmentStatus(rawValue: status),
            enrolledAt: Self.parseTimestamp(enrolledAt),
            createdAt: Self.parseTimestamp(createdAt),
            onboardingCompletedAt: Self.parseTimestamp(onboardingCompletedAt)
        )
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}
