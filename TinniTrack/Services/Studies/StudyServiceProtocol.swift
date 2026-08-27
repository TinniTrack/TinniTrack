//
//  StudyServiceProtocol.swift
//  TinniTrack
//

import Foundation

protocol StudyServiceProtocol {
    func fetchStudies() async throws -> [Study]
    func fetchMyEnrollments() async throws -> [StudyEnrollment]
    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask]
    func beginStudyNo1OrientationThresholdTask(enrollmentID: UUID) async throws -> ScheduledTask
    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws
    func submitStudyNo1OrientationThreshold(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: StudyNo1OrientationThresholdSubmission
    ) async throws
    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws
}
