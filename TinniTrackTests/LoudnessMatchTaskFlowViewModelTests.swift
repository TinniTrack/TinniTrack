import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct LoudnessMatchTaskFlowViewModelTests {
    @Test
    func headphoneGateAdvancesWhenSupportedRouteAppears() {
        let routeMonitor = MockRouteMonitor()
        let ambientMonitor = MockAmbientNoiseMonitor(permissionStatus: .granted)
        let service = MockLoudnessStudyService()

        let viewModel = makeViewModel(
            routeMonitor: routeMonitor,
            ambientMonitor: ambientMonitor,
            service: service
        )

        viewModel.start()
        #expect(viewModel.step == .headphoneGate)

        routeMonitor.emit(route: AudioOutputRoute(name: "iPhone", portType: "Built-In Speaker"))
        #expect(viewModel.step == .headphoneGate)

        routeMonitor.emit(route: AudioOutputRoute(name: "AirPods Pro", portType: "BluetoothA2DPOutput"))
        #expect(viewModel.step == .ambientGate)
    }

    @Test
    func ambientGateRequiresQuietThresholdBeforeStart() {
        let routeMonitor = MockRouteMonitor()
        let ambientMonitor = MockAmbientNoiseMonitor(permissionStatus: .granted)
        let service = MockLoudnessStudyService()

        let viewModel = makeViewModel(
            routeMonitor: routeMonitor,
            ambientMonitor: ambientMonitor,
            service: service
        )

        viewModel.start()
        routeMonitor.emit(route: AudioOutputRoute(name: "AirPods Pro", portType: "BluetoothA2DPOutput"))

        ambientMonitor.emit(db: 46)
        #expect(viewModel.isAmbientQuiet == false)

        viewModel.startMatching()
        #expect(viewModel.step == .ambientGate)

        ambientMonitor.emit(db: 30)
        #expect(viewModel.isAmbientQuiet)

        viewModel.startMatching()
        #expect(viewModel.step == .matching)
    }

    @Test
    func matchingDisablesDialWhenAmbientTooLoudAndReenablesWhenQuiet() {
        let routeMonitor = MockRouteMonitor()
        let ambientMonitor = MockAmbientNoiseMonitor(permissionStatus: .granted)
        let service = MockLoudnessStudyService()

        let viewModel = makeViewModel(
            routeMonitor: routeMonitor,
            ambientMonitor: ambientMonitor,
            service: service
        )

        viewModel.start()
        routeMonitor.emit(route: AudioOutputRoute(name: "AirPods Pro", portType: "BluetoothA2DPOutput"))
        ambientMonitor.emit(db: 28)
        viewModel.startMatching()

        viewModel.updateLoudness(0.75)
        #expect(viewModel.loudnessLevel == 0.75)

        ambientMonitor.emit(db: 50)
        #expect(viewModel.isAmbientQuiet == false)
        viewModel.updateLoudness(0.2)
        #expect(viewModel.loudnessLevel == 0.75)

        ambientMonitor.emit(db: 25)
        #expect(viewModel.isAmbientQuiet)
        viewModel.updateLoudness(0.2)
        #expect(viewModel.loudnessLevel == 0.2)
    }

    @Test
    func submitMatchCallsStudyService() async {
        let routeMonitor = MockRouteMonitor()
        let ambientMonitor = MockAmbientNoiseMonitor(permissionStatus: .granted)
        let service = MockLoudnessStudyService()

        let viewModel = makeViewModel(
            routeMonitor: routeMonitor,
            ambientMonitor: ambientMonitor,
            service: service
        )

        viewModel.start()
        routeMonitor.emit(route: AudioOutputRoute(name: "AirPods Pro", portType: "BluetoothA2DPOutput"))
        ambientMonitor.emit(db: 20)
        viewModel.startMatching()
        viewModel.updateLoudness(0.64)

        let submitted = await viewModel.submitMatch()

        #expect(submitted)
        #expect(await service.submitCallCount() == 1)
        #expect(await service.lastSubmittedSubmission()?.rawPayload["matched_level_unit"] == .string("normalizedAmplitude"))
        #expect(await service.lastSubmittedSubmission()?.rawPayload["measurement_metadata"] != nil)
        #expect(await service.lastSubmittedSubmission()?.headphoneInfo["route_gate"] == .string("study-no-1-route-name-gate"))
        #expect(await service.lastSubmittedSubmission()?.calibrationVersion == "study-no-1-unvalidated-normalized-output")
    }

    private func makeViewModel(
        routeMonitor: MockRouteMonitor,
        ambientMonitor: MockAmbientNoiseMonitor,
        service: MockLoudnessStudyService
    ) -> LoudnessMatchTaskFlowViewModel {
        let enrollment = StudyEnrollment(
            id: UUID(),
            userID: UUID(),
            studyID: UUID(),
            status: .enrolled,
            enrolledAt: Date(),
            createdAt: Date(),
            onboardingCompletedAt: Date()
        )

        let task = ScheduledTask(
            id: UUID(),
            enrollmentID: enrollment.id,
            taskKey: "lm_1khz_v1",
            taskVersion: 1,
            scheduledFor: Date(),
            windowStart: Date().addingTimeInterval(-300),
            windowEnd: Date().addingTimeInterval(300),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        )

        return LoudnessMatchTaskFlowViewModel(
            scheduledTask: task,
            enrollment: enrollment,
            studyService: service,
            routeMonitor: routeMonitor,
            ambientNoiseMonitor: ambientMonitor,
            tonePlayer: MockTonePlayer(),
            routeGate: StudyNo1RouteGate(),
            deviceMetadataProvider: MockDeviceMetadataProvider(),
            resultBuilder: StudyNo1LoudnessMatchResultBuilder()
        )
    }
}

private final class MockRouteMonitor: HeadphoneRouteMonitoring {
    private var callback: ((AudioOutputRoute?) -> Void)?
    private var latestRoute: AudioOutputRoute?

    func currentRoute() -> AudioOutputRoute? {
        latestRoute
    }

    func startMonitoring(_ onChange: @escaping (AudioOutputRoute?) -> Void) {
        callback = onChange
        onChange(latestRoute)
    }

    func stopMonitoring() {
        callback = nil
    }

    func emit(route: AudioOutputRoute?) {
        latestRoute = route
        callback?(route)
    }
}

private final class MockAmbientNoiseMonitor: AmbientNoiseMonitoring {
    private let staticPermissionStatus: AmbientNoisePermissionStatus
    private var callback: ((Double) -> Void)?

    init(permissionStatus: AmbientNoisePermissionStatus) {
        self.staticPermissionStatus = permissionStatus
    }

    func permissionStatus() -> AmbientNoisePermissionStatus {
        staticPermissionStatus
    }

    func requestPermission() async -> Bool {
        staticPermissionStatus == .granted
    }

    func startMonitoring(onUpdate: @escaping (Double) -> Void) throws {
        callback = onUpdate
    }

    func stopMonitoring() {
        callback = nil
    }

    func emit(db: Double) {
        callback?(db)
    }
}

private final class MockTonePlayer: TonePlaying {
    private(set) var isStarted = false
    private(set) var latestVolume: Double?

    func start() {
        isStarted = true
    }

    func stop() {
        isStarted = false
    }

    func setVolume(_ volume: Double) {
        latestVolume = volume
    }
}

private struct MockDeviceMetadataProvider: DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue] {
        [
            "model": .string("Test Device"),
            "system_name": .string("iOS"),
            "system_version": .string("18.1")
        ]
    }

    func outputDeviceInfo(for route: AudioOutputRoute?) -> [String: JSONValue] {
        [
            "route_name": .string(route?.name ?? ""),
            "route_port_type": .string(route?.portType ?? ""),
            "route_gate": .string("study-no-1-route-name-gate")
        ]
    }
}

private actor MockLoudnessStudyService: StudyServiceProtocol {
    private var submitCount = 0
    private var submittedSubmission: LoudnessMatchSubmission?

    func fetchStudies() async throws -> [Study] {
        []
    }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] {
        []
    }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] {
        []
    }

    func enroll(studyID: UUID) async throws {}

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {
        submitCount += 1
        submittedSubmission = submission
    }

    func submitCallCount() -> Int {
        submitCount
    }

    func lastSubmittedSubmission() -> LoudnessMatchSubmission? {
        submittedSubmission
    }
}
