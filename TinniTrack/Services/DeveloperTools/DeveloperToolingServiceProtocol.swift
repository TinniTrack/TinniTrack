//
//  DeveloperToolingServiceProtocol.swift
//  TinniTrack
//

import Foundation

#if DEBUG
protocol DeveloperToolingServiceProtocol {
    func resetProfileOnboarding() async throws
    func resetStudyNo1Orientation() async throws
    func makeNextLoudnessMatchAvailableNow() async throws
    func reopenLastCompletedLoudnessMatch() async throws
}
#endif
