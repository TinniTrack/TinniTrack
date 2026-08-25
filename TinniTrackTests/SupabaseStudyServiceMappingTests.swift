import Foundation
import Testing
@testable import TinniTrack

struct SupabaseStudyServiceMappingTests {
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
