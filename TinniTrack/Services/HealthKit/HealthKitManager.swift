//
//  HealthKitManager.swift
//  TinniTrack
//

import Foundation
import HealthKit

final class HealthKitManager: HealthKitAudiogramServiceProtocol {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func readAuthorizationStatus() -> HealthKitReadAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        let audiogramType = HKObjectType.audiogramSampleType()
        switch healthStore.authorizationStatus(for: audiogramType) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAudiogramServiceError.dataUnavailable
        }

        let audiogramType = HKObjectType.audiogramSampleType()

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [audiogramType])
        } catch {
            throw HealthKitAudiogramServiceError.queryFailed(error.localizedDescription)
        }
    }

    func fetchAudiogramSamples() async throws -> [HealthKitAudiogramSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAudiogramServiceError.dataUnavailable
        }

        switch readAuthorizationStatus() {
        case .notDetermined:
            throw HealthKitAudiogramServiceError.authorizationNotDetermined
        case .unavailable:
            throw HealthKitAudiogramServiceError.dataUnavailable
        case .authorized, .denied:
            break
        }

        let sampleType = HKObjectType.audiogramSampleType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if let healthError = error as? HKError,
                       healthError.code == .errorAuthorizationDenied {
                        continuation.resume(
                            throwing: HealthKitAudiogramServiceError.authorizationDenied
                        )
                        return
                    }

                    continuation.resume(
                        throwing: HealthKitAudiogramServiceError.queryFailed(error.localizedDescription)
                    )
                    return
                }
                continuation.resume(returning: samples ?? [])
            }

            healthStore.execute(query)
        }

        return samples.compactMap(parseAudiogramSample)
    }

    private func parseAudiogramSample(_ sample: HKSample) -> HealthKitAudiogramSample? {
        guard let audiogram = sample as? HKAudiogramSample else {
            return nil
        }

        let points = audiogram.sensitivityPoints
            .compactMap(parsePoint)
            .sorted { $0.frequencyHz < $1.frequencyHz }

        guard !points.isEmpty else {
            return nil
        }

        return HealthKitAudiogramSample(
            sampleUUID: audiogram.uuid,
            measuredAt: audiogram.endDate,
            sourceName: audiogram.sourceRevision.source.name,
            deviceName: audiogram.device?.name,
            points: points
        )
    }

    private func parsePoint(_ point: HKAudiogramSensitivityPoint) -> AudiogramPoint? {
        let frequency = point.frequency.doubleValue(for: .hertz())

        var leftEar: Double?
        var rightEar: Double?

        var tests: [AudiogramSensitivityTest] = []

        if #available(iOS 18.1, *) {
            tests = point.tests.map { test in
                AudiogramSensitivityTest(
                    side: Self.side(for: test.side),
                    conduction: Self.conduction(for: test.type),
                    masked: test.masked,
                    sensitivityDBHL: test.sensitivity.doubleValue(for: .decibelHearingLevel())
                )
            }

            leftEar = Self.preferredSensitivity(for: .left, tests: point.tests) ?? leftEar
            rightEar = Self.preferredSensitivity(for: .right, tests: point.tests) ?? rightEar
        } else {
            let legacySensitivities = Self.legacyEarSensitivities(from: point)
            leftEar = legacySensitivities.left
            rightEar = legacySensitivities.right
        }

        guard leftEar != nil || rightEar != nil || !tests.isEmpty else {
            return nil
        }

        return AudiogramPoint(
            frequencyHz: frequency,
            leftEarDBHL: leftEar,
            rightEarDBHL: rightEar,
            tests: tests
        )
    }

    @available(iOS 18.1, *)
    private static func preferredSensitivity(
        for side: HKAudiogramSensitivityTestSide,
        tests: [HKAudiogramSensitivityTest]
    ) -> Double? {
        let preferred = tests.first { $0.side == side && $0.type == .air }
            ?? tests.first { $0.side == side }
        return preferred?.sensitivity.doubleValue(for: .decibelHearingLevel())
    }

    @available(iOS 18.1, *)
    private static func side(for side: HKAudiogramSensitivityTestSide) -> AudiogramSensitivityTest.Side {
        switch side {
        case .left:
            return .left
        case .right:
            return .right
        @unknown default:
            return .unknown
        }
    }

    @available(iOS 18.1, *)
    private static func conduction(for type: HKAudiogramConductionType) -> String {
        switch type {
        case .air:
            return "air"
        @unknown default:
            return "unknown"
        }
    }

    @available(iOS, introduced: 13.0, deprecated: 18.1)
    private static func legacyEarSensitivities(
        from point: HKAudiogramSensitivityPoint
    ) -> (left: Double?, right: Double?) {
        let left = point.leftEarSensitivity?.doubleValue(for: .decibelHearingLevel())
        let right = point.rightEarSensitivity?.doubleValue(for: .decibelHearingLevel())
        return (left, right)
    }
}

final class MockHealthKitManager: HealthKitAudiogramServiceProtocol {
    var status: HealthKitReadAuthorizationStatus = .notDetermined
    var samples: [HealthKitAudiogramSample] = []
    var requestAuthorizationError: Error?
    var fetchError: Error?

    func readAuthorizationStatus() -> HealthKitReadAuthorizationStatus {
        status
    }

    func requestReadAuthorization() async throws {
        if let requestAuthorizationError {
            throw requestAuthorizationError
        }
        status = .authorized
    }

    func fetchAudiogramSamples() async throws -> [HealthKitAudiogramSample] {
        if let fetchError {
            throw fetchError
        }
        return samples
    }
}
