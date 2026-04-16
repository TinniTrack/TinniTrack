//
//  StudyServiceProtocol.swift
//  TinniTrack
//

import Foundation

protocol StudyServiceProtocol {
    func fetchStudies() async throws -> [Study]
    func fetchMyEnrollments() async throws -> [StudyEnrollment]
    func enroll(studyID: UUID) async throws
}
