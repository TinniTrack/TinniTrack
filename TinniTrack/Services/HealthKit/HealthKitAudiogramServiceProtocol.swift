//
//  HealthKitAudiogramServiceProtocol.swift
//  TinniTrack
//

import Foundation

enum HealthKitReadAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

enum HealthKitAudiogramServiceError: LocalizedError, Equatable {
    case dataUnavailable
    case authorizationDenied
    case authorizationNotDetermined
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .dataUnavailable:
            return "Health data is not available on this device."
        case .authorizationDenied:
            return "Apple Health access is denied. Enable it in Settings."
        case .authorizationNotDetermined:
            return "Apple Health access is required before importing audiograms."
        case .queryFailed(let reason):
            return "Unable to read Apple Health audiograms: \(reason)"
        }
    }
}

struct HealthKitAudiogramSample: Equatable {
    let sampleUUID: UUID
    let measuredAt: Date
    let sourceName: String
    let deviceName: String?
    let points: [AudiogramPoint]
}

protocol HealthKitAudiogramServiceProtocol {
    func readAuthorizationStatus() -> HealthKitReadAuthorizationStatus
    func requestReadAuthorization() async throws
    func fetchAudiogramSamples() async throws -> [HealthKitAudiogramSample]
}
