//
//  AudiogramRepositoryProtocol.swift
//  TinniTrack
//

import Foundation

protocol AudiogramRepositoryProtocol {
    func fetchLatestAudiogram() async throws -> AudiogramRecord?
    func saveHealthKitAudiograms(_ samples: [HealthKitAudiogramSample]) async throws -> Int
}
