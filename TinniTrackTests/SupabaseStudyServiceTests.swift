import Foundation
import Testing
@testable import TinniTrack

struct SupabaseStudyServiceTests {
    @Test
    func invalidLoudnessMatchSubmissionIsBlockedBeforeRPC() async {
        let service = SupabaseStudyService()
        let submission = LoudnessMatchSubmission(
            startedAt: Date(timeIntervalSince1970: 1_750_000_000),
            completedAt: Date(timeIntervalSince1970: 1_750_000_030),
            matchedLevel: 0.5,
            validationStatus: .invalid,
            qualityFlags: [.missingAudiogramThreshold],
            gating: [:],
            rawPayload: [
                "measurement_metadata": .object([
                    "schema_version": .string("study-no-1-lm-payload-v2")
                ]),
                "quality": .object([
                    "validation_status": .string("invalid")
                ])
            ],
            deviceInfo: [:],
            headphoneInfo: [:],
            appVersion: nil,
            calibrationVersion: nil
        )

        do {
            try await service.submitLoudnessMatch(
                scheduledTaskID: UUID(),
                enrollmentID: UUID(),
                submission: submission
            )
            Issue.record("Expected invalid submission to be blocked before Supabase RPC")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == "StudyService")
            #expect(nsError.code == 422)
        }
    }
}
