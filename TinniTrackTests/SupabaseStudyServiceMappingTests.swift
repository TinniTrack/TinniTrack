import Foundation
import Testing
@testable import TinniTrack

struct SupabaseStudyServiceMappingTests {
    @Test
    @MainActor
    func enrollmentRowDecodesCanonicalRPCObject() throws {
        let data = Data(
            """
            {
              "id": "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF",
              "user_id": "11111111-2222-3333-4444-555555555555",
              "study_id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "status": "enrolled",
              "enrolled_at": "2026-08-25T04:05:06.789Z",
              "created_at": "2026-08-25T04:05:06Z",
              "onboarding_completed_at": null,
              "eligibility_snapshot": {
                "schema_version": 1,
                "study_slug": "study-no-1"
              }
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(StudyEnrollmentRow.self, from: data)
        let enrollment = row.toDomain()

        #expect(enrollment.id == row.id)
        #expect(enrollment.userID == row.userID)
        #expect(enrollment.studyID == row.studyID)
        #expect(enrollment.status == .enrolled)
        #expect(enrollment.enrolledAt != nil)
        #expect(enrollment.createdAt != nil)
        #expect(enrollment.onboardingCompletedAt == nil)
    }

    @Test
    func scheduledTaskRejectsMalformedRequiredTimestamp() {
        let row = makeRow(scheduledFor: "not-a-timestamp")

        #expect(
            throws: SupabaseStudyDataError.invalidTimestamp(
                field: "scheduled_for",
                value: "not-a-timestamp"
            )
        ) {
            try row.toDomain()
        }
    }

    @Test
    func scheduledTaskRejectsMalformedOptionalTimestamp() {
        let row = makeRow(completedAt: "not-a-timestamp")

        #expect(
            throws: SupabaseStudyDataError.invalidTimestamp(
                field: "completed_at",
                value: "not-a-timestamp"
            )
        ) {
            try row.toDomain()
        }
    }

    @Test
    func scheduledTaskMapsValidFractionalTimestamps() throws {
        let row = makeRow(completedAt: "2026-08-25T04:05:06.789Z")

        let task = try row.toDomain()

        #expect(task.id == row.id)
        #expect(task.enrollmentID == row.enrollmentID)
        #expect(task.windowStart < task.scheduledFor)
        #expect(task.scheduledFor < task.windowEnd)
        #expect(task.completedAt != nil)
    }

    private func makeRow(
        scheduledFor: String = "2026-08-25T04:00:00.000Z",
        windowStart: String = "2026-08-25T03:30:00.000Z",
        windowEnd: String = "2026-08-25T04:30:00.000Z",
        completedAt: String? = nil
    ) -> ScheduledTaskRow {
        ScheduledTaskRow(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            enrollmentID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            taskKey: "study_no_1_loudness_match",
            taskVersion: 1,
            scheduledFor: scheduledFor,
            windowStart: windowStart,
            windowEnd: windowEnd,
            status: "scheduled",
            dayIndex: 1,
            slotIndex: 1,
            completedAt: completedAt
        )
    }
}
