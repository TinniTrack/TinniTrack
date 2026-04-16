import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct AudiogramImportCoordinatorTests {
    @Test
    func evaluatePrerequisiteNeedsPermissionWhenNotAuthorized() async {
        let healthKitService = MockHealthKitAudiogramService()
        healthKitService.status = .notDetermined

        let repository = MockAudiogramRepository()
        repository.latestAudiogram = nil

        let coordinator = AudiogramImportCoordinator(
            healthKitService: healthKitService,
            repository: repository
        )

        let state = await coordinator.evaluatePrerequisite()
        #expect(state == .needsPermission)
    }

    @Test
    func evaluatePrerequisitePermissionDeniedWhenAuthorizationDenied() async {
        let healthKitService = MockHealthKitAudiogramService()
        healthKitService.status = .denied
        healthKitService.fetchError = HealthKitAudiogramServiceError.authorizationDenied

        let repository = MockAudiogramRepository()
        repository.latestAudiogram = nil

        let coordinator = AudiogramImportCoordinator(
            healthKitService: healthKitService,
            repository: repository
        )

        let state = await coordinator.evaluatePrerequisite()
        #expect(state == .permissionDenied)
    }

    @Test
    func evaluatePrerequisiteImportsWhenStatusIsDeniedButReadAccessWorks() async {
        let now = Date()
        let sample = HealthKitAudiogramSample(
            sampleUUID: UUID(),
            measuredAt: now,
            sourceName: "Health",
            deviceName: "iPhone",
            points: [
                AudiogramPoint(
                    frequencyHz: 1000,
                    leftEarDBHL: 15,
                    rightEarDBHL: 18,
                    tests: []
                )
            ]
        )

        let healthKitService = MockHealthKitAudiogramService()
        healthKitService.status = .denied
        healthKitService.samples = [sample]

        let repository = MockAudiogramRepository()
        repository.latestAudiogram = nil
        repository.persistedInsertCount = 1
        repository.latestAfterSave = AudiogramRecord(
            id: UUID(),
            measuredAt: now,
            source: "healthkit",
            headphoneName: "iPhone",
            healthKitSampleUUID: sample.sampleUUID,
            points: sample.points
        )

        let coordinator = AudiogramImportCoordinator(
            healthKitService: healthKitService,
            repository: repository
        )

        let state = await coordinator.evaluatePrerequisite()
        #expect(state == .met(latestMeasuredAt: now))
    }

    @Test
    func importFromHealthKitPersistsNewSamples() async throws {
        let now = Date()
        let sample = HealthKitAudiogramSample(
            sampleUUID: UUID(),
            measuredAt: now,
            sourceName: "Health",
            deviceName: "iPhone",
            points: [
                AudiogramPoint(
                    frequencyHz: 1000,
                    leftEarDBHL: 18,
                    rightEarDBHL: 20,
                    tests: []
                )
            ]
        )

        let healthKitService = MockHealthKitAudiogramService()
        healthKitService.status = .authorized
        healthKitService.samples = [sample]

        let repository = MockAudiogramRepository()
        repository.latestAudiogram = nil
        repository.persistedInsertCount = 1
        repository.latestAfterSave = AudiogramRecord(
            id: UUID(),
            measuredAt: now,
            source: "healthkit",
            headphoneName: "iPhone",
            healthKitSampleUUID: sample.sampleUUID,
            points: sample.points
        )

        let coordinator = AudiogramImportCoordinator(
            healthKitService: healthKitService,
            repository: repository
        )

        let result = try await coordinator.importFromHealthKit()
        if case .imported(let count, let latestMeasuredAt) = result {
            #expect(count == 1)
            #expect(latestMeasuredAt == now)
        } else {
            #expect(Bool(false), "Expected .imported result")
        }
    }

    @Test
    func importFromHealthKitReturnsNoNewRecordsWhenDeduped() async throws {
        let now = Date()
        let sample = HealthKitAudiogramSample(
            sampleUUID: UUID(),
            measuredAt: now,
            sourceName: "Health",
            deviceName: nil,
            points: []
        )

        let healthKitService = MockHealthKitAudiogramService()
        healthKitService.status = .authorized
        healthKitService.samples = [sample]

        let repository = MockAudiogramRepository()
        repository.persistedInsertCount = 0
        repository.latestAfterSave = AudiogramRecord(
            id: UUID(),
            measuredAt: now,
            source: "healthkit",
            headphoneName: nil,
            healthKitSampleUUID: sample.sampleUUID,
            points: []
        )

        let coordinator = AudiogramImportCoordinator(
            healthKitService: healthKitService,
            repository: repository
        )

        let result = try await coordinator.importFromHealthKit()
        if case .noNewRecords(let latestMeasuredAt) = result {
            #expect(latestMeasuredAt == now)
        } else {
            #expect(Bool(false), "Expected .noNewRecords result")
        }
    }
}

private final class MockHealthKitAudiogramService: HealthKitAudiogramServiceProtocol {
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

private final class MockAudiogramRepository: AudiogramRepositoryProtocol {
    var latestAudiogram: AudiogramRecord?
    var latestAfterSave: AudiogramRecord?
    var persistedInsertCount: Int = 0

    func fetchLatestAudiogram() async throws -> AudiogramRecord? {
        latestAfterSave ?? latestAudiogram
    }

    func saveHealthKitAudiograms(_ samples: [HealthKitAudiogramSample]) async throws -> Int {
        if let latestAfterSave {
            latestAudiogram = latestAfterSave
        }
        return persistedInsertCount
    }
}
