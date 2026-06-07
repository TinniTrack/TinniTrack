import Combine
import Foundation

@MainActor
final class LoudnessMatchTaskFlowViewModel: ObservableObject {
    enum Step: Equatable {
        case headphoneGate
        case ambientGate
        case matching
    }

    @Published private(set) var step: Step = .headphoneGate
    @Published private(set) var currentRoute: AudioOutputRoute?
    @Published private(set) var ambientPermissionStatus: AmbientNoisePermissionStatus = .notDetermined
    @Published private(set) var ambientDB: Double?
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loudnessLevel: Double = 0.3

    private let scheduledTask: ScheduledTask
    private let enrollment: StudyEnrollment
    private let studyService: StudyServiceProtocol
    private let routeMonitor: HeadphoneRouteMonitoring
    private let ambientNoiseMonitor: AmbientNoiseMonitoring
    private let tonePlayer: TonePlaying
    private let routeGate: AudioRouteGating
    private let deviceMetadataProvider: DeviceMetadataProviding
    private let resultBuilder: LoudnessMatchResultBuilding

    private var hasStarted = false
    private var startedAt: Date?
    private var loudnessEvents: [MeasurementTraceEvent] = []
    private var ambientEvents: [MeasurementTraceEvent] = []

    init(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        routeMonitor: HeadphoneRouteMonitoring,
        ambientNoiseMonitor: AmbientNoiseMonitoring,
        tonePlayer: TonePlaying,
        routeGate: AudioRouteGating,
        deviceMetadataProvider: DeviceMetadataProviding,
        resultBuilder: LoudnessMatchResultBuilding
    ) {
        self.scheduledTask = scheduledTask
        self.enrollment = enrollment
        self.studyService = studyService
        self.routeMonitor = routeMonitor
        self.ambientNoiseMonitor = ambientNoiseMonitor
        self.tonePlayer = tonePlayer
        self.routeGate = routeGate
        self.deviceMetadataProvider = deviceMetadataProvider
        self.resultBuilder = resultBuilder
    }

    var isSupportedRoute: Bool {
        routeGate.isRouteSupported(currentRoute)
    }

    var isAmbientQuiet: Bool {
        guard let ambientDB else { return false }
        return ambientDB <= StudyNo1Configuration.ambientThresholdDB
    }

    var ambientDisplayText: String {
        guard let ambientDB else {
            return "Waiting for ambient reading..."
        }
        return String(format: "Ambient: %.1f dB (threshold: %.0f dB)", ambientDB, StudyNo1Configuration.ambientThresholdDB)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        ambientPermissionStatus = ambientNoiseMonitor.permissionStatus()

        routeMonitor.startMonitoring { [weak self] route in
            guard let self else { return }
            self.currentRoute = route

            if self.isSupportedRoute && self.step == .headphoneGate {
                self.enterAmbientGate()
            }
        }
    }

    func stop() {
        routeMonitor.stopMonitoring()
        ambientNoiseMonitor.stopMonitoring()
        tonePlayer.stop()
    }

    func requestAmbientPermission() async {
        let granted = await ambientNoiseMonitor.requestPermission()
        ambientPermissionStatus = granted ? .granted : .denied

        if granted {
            startAmbientMonitoringIfNeeded()
        }
    }

    func startMatching() {
        guard step == .ambientGate else { return }
        guard isAmbientQuiet else { return }

        step = .matching
        startedAt = Date()

        tonePlayer.start()
        tonePlayer.setVolume(loudnessLevel)

        loudnessEvents.append(MeasurementTraceEvent(timestamp: Date(), value: loudnessLevel))
    }

    func updateLoudness(_ newValue: Double) {
        guard step == .matching else { return }
        guard isAmbientQuiet else { return }

        loudnessLevel = min(max(newValue, 0), 1)
        tonePlayer.setVolume(loudnessLevel)
        loudnessEvents.append(MeasurementTraceEvent(timestamp: Date(), value: loudnessLevel))
    }

    func submitMatch() async -> Bool {
        guard let startedAt else {
            errorMessage = "Task start timestamp is missing."
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let completedAt = Date()
        let submission = resultBuilder.makeSubmission(
            from: LoudnessMatchResultInput(
                scheduledTask: scheduledTask,
                startedAt: startedAt,
                completedAt: completedAt,
                matchedLevel: loudnessLevel,
                currentRoute: currentRoute,
                isSupportedRoute: isSupportedRoute,
                ambientDB: ambientDB,
                isAmbientQuiet: isAmbientQuiet,
                loudnessEvents: loudnessEvents,
                ambientEvents: ambientEvents,
                deviceInfo: deviceMetadataProvider.currentDeviceInfo(),
                outputDeviceInfo: deviceMetadataProvider.outputDeviceInfo(for: currentRoute),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        )

        do {
            try await studyService.submitLoudnessMatch(
                scheduledTaskID: scheduledTask.id,
                enrollmentID: enrollment.id,
                submission: submission
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func enterAmbientGate() {
        step = .ambientGate

        if ambientPermissionStatus == .granted {
            startAmbientMonitoringIfNeeded()
        }
    }

    private func startAmbientMonitoringIfNeeded() {
        do {
            try ambientNoiseMonitor.startMonitoring { [weak self] db in
                guard let self else { return }
                self.ambientDB = db
                self.ambientEvents.append(MeasurementTraceEvent(timestamp: Date(), value: db))
                if self.ambientEvents.count > 2_000 {
                    self.ambientEvents.removeFirst(self.ambientEvents.count - 2_000)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
