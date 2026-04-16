//
//  AudiogramImportCoordinator.swift
//  TinniTrack
//

import Foundation

protocol AudiogramImportCoordinating {
    func evaluatePrerequisite() async -> AudiogramPrerequisiteState
    func importFromHealthKit() async throws -> AudiogramImportResult
}

enum AudiogramImportCoordinatorError: LocalizedError, Equatable {
    case healthDataUnavailable
    case authorizationDenied
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .authorizationDenied:
            return "Apple Health access is required to import audiogram data."
        case .importFailed(let reason):
            return reason
        }
    }
}

final class AudiogramImportCoordinator: AudiogramImportCoordinating {
    private let healthKitService: HealthKitAudiogramServiceProtocol
    private let repository: AudiogramRepositoryProtocol

    init(
        healthKitService: HealthKitAudiogramServiceProtocol,
        repository: AudiogramRepositoryProtocol
    ) {
        self.healthKitService = healthKitService
        self.repository = repository
    }

    convenience init() {
        self.init(
            healthKitService: HealthKitManager(),
            repository: SupabaseAudiogramRepository()
        )
    }

    func evaluatePrerequisite() async -> AudiogramPrerequisiteState {
        do {
            if let latest = try await repository.fetchLatestAudiogram() {
                return .met(latestMeasuredAt: latest.measuredAt)
            }

            switch healthKitService.readAuthorizationStatus() {
            case .notDetermined:
                return .needsPermission
            case .unavailable:
                return .error(message: AudiogramImportCoordinatorError.healthDataUnavailable.localizedDescription)
            case .authorized, .denied:
                do {
                    let importResult = try await importAuthorizedData()
                    switch importResult {
                    case .imported(_, let latestMeasuredAt), .noNewRecords(let latestMeasuredAt):
                        return .met(latestMeasuredAt: latestMeasuredAt)
                    case .noAudiogramInHealth:
                        return .noAudiogramInHealth
                    }
                } catch {
                    let mappedError = mapToCoordinatorError(error)
                    if mappedError == .authorizationDenied {
                        return .permissionDenied
                    }
                    return .error(message: mappedError.localizedDescription)
                }
            }
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    func importFromHealthKit() async throws -> AudiogramImportResult {
        switch healthKitService.readAuthorizationStatus() {
        case .authorized:
            return try await importAuthorizedData()
        case .notDetermined, .denied:
            do {
                try await healthKitService.requestReadAuthorization()
            } catch {
                throw mapToCoordinatorError(error)
            }
            return try await importAuthorizedData()
        case .unavailable:
            throw AudiogramImportCoordinatorError.healthDataUnavailable
        }
    }

    private func importAuthorizedData() async throws -> AudiogramImportResult {
        let samples: [HealthKitAudiogramSample]
        do {
            samples = try await healthKitService.fetchAudiogramSamples()
        } catch {
            throw mapToCoordinatorError(error)
        }

        guard !samples.isEmpty else {
            return .noAudiogramInHealth
        }

        let insertedCount = try await repository.saveHealthKitAudiograms(samples)
        let latestMeasuredAt = try await repository.fetchLatestAudiogram()?.measuredAt

        if insertedCount > 0 {
            return .imported(newRecords: insertedCount, latestMeasuredAt: latestMeasuredAt)
        }

        return .noNewRecords(latestMeasuredAt: latestMeasuredAt)
    }

    private func mapToCoordinatorError(_ error: Error) -> AudiogramImportCoordinatorError {
        if let coordinatorError = error as? AudiogramImportCoordinatorError {
            return coordinatorError
        }

        if let healthKitError = error as? HealthKitAudiogramServiceError {
            switch healthKitError {
            case .dataUnavailable:
                return .healthDataUnavailable
            case .authorizationDenied, .authorizationNotDetermined:
                return .authorizationDenied
            case .queryFailed(let reason):
                return .importFailed(reason)
            }
        }

        return .importFailed(error.localizedDescription)
    }
}
