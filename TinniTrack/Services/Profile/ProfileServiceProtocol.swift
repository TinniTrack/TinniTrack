//
//  ProfileServiceProtocol.swift
//  TinniTrack
//

import Foundation

protocol ProfileServiceProtocol {
    func fetchMyProfile() async throws -> Profile?
    func completeOnboarding(firstName: String, lastName: String, dateOfBirth: Date) async throws
}
