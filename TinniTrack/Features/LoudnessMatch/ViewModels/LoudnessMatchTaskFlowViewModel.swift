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
    @Published private(set) var currentOutputVolume: Double?
    @Published private(set) var outputVolumeAtStart: Double?
    @Published private(set) var hasOutputVolumeChanged = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loudnessLevel: Double = 0.3

    private let scheduledTask: ScheduledTask
    private let enrollment: StudyEnrollment
    private let studyService: StudyServiceProtocol
    private let routeMonitor: HeadphoneRouteMonitoring
    private let ambientNoiseMonitor: AmbientNoiseMonitoring
    private let outputVolumeMonitor: OutputVolumeMonitoring
    private let tonePlayer: TonePlaying
    private let routeGate: AudioRouteGating
    private let deviceMetadataProvider: DeviceMetadataProviding
    private let resultBuilder: LoudnessMatchResultBuilding

    private var hasStarted = false
    private var startedAt: Date?
    private var loudnessEvents: [MeasurementTraceEvent] = []
    private var ambientEvents: [MeasurementTraceEvent] = []
    private var outputVolumeEvents: [MeasurementTraceEvent] = []

    init(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        routeMonitor: HeadphoneRouteMonitoring,
        ambientNoiseMonitor: AmbientNoiseMonitoring,
        outputVolumeMonitor: OutputVolumeMonitoring,
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
        self.outputVolumeMonitor = outputVolumeMonitor
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

    var canAdjustLoudness: Bool {
        step == .matching && isSupportedRoute && isAmbientQuiet && isOutputVolumeStable
    }

    var canSubmit: Bool {
        canAdjustLoudness && startedAt != nil && !isSubmitting
    }

    var ambientDisplayText: String {
        guard let ambientDB else {
            return "Waiting for ambient reading..."
        }
        return String(format: "Ambient: %.1f dB (threshold: %.0f dB)", ambientDB, StudyNo1Configuration.ambientThresholdDB)
    }

    var outputVolumeDisplayText: String {
        guard let outputVolumeAtStart, let currentOutputVolume else {
            return "Device volume baseline unavailable."
        }
        return String(
            format: "Device volume: %.0f%% (start: %.0f%%)",
            currentOutputVolume * 100,
            outputVolumeAtStart * 100
        )
    }

    var matchingPauseMessage: String? {
        guard step == .matching else { return nil }

        if !isSupportedRoute {
            return "Reconnect AirPods Pro 2 or AirPods Pro 3 to continue."
        }
        if !isAmbientQuiet {
            return "Adjustment is paused until ambient noise returns below the threshold."
        }
        if outputVolumeAtStart == nil || currentOutputVolume == nil {
            return "Device volume monitoring is unavailable."
        }
        if hasOutputVolumeChanged {
            return "Use the on-screen dial only. Return device volume to its starting level to continue."
        }

        return nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        ambientPermissionStatus = ambientNoiseMonitor.permissionStatus()
        currentOutputVolume = outputVolumeMonitor.currentOutputVolume()

        outputVolumeMonitor.startMonitoring { [weak self] volume in
            guard let self else { return }
            self.currentOutputVolume = volume
            self.recordOutputVolumeIfMatching(volume)
            self.updateOutputVolumeValidity()
            self.applyTonePlaybackState()
        }

        routeMonitor.startMonitoring { [weak self] route in
            guard let self else { return }
            self.currentRoute = route

            if self.isSupportedRoute && self.step == .headphoneGate {
                self.enterAmbientGate()
            }

            self.applyTonePlaybackState()
        }
    }

    func stop() {
        routeMonitor.stopMonitoring()
        ambientNoiseMonitor.stopMonitoring()
        outputVolumeMonitor.stopMonitoring()
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
        guard isSupportedRoute else { return }
        guard isAmbientQuiet else { return }
        guard let baselineOutputVolume = currentOutputVolume ?? outputVolumeMonitor.currentOutputVolume() else {
            errorMessage = "Device volume monitoring is unavailable."
            return
        }

        step = .matching
        startedAt = Date()
        outputVolumeAtStart = baselineOutputVolume
        hasOutputVolumeChanged = false
        outputVolumeEvents = []

        outputVolumeEvents.append(MeasurementTraceEvent(timestamp: Date(), value: baselineOutputVolume))

        loudnessEvents.append(MeasurementTraceEvent(timestamp: Date(), value: loudnessLevel))
        applyTonePlaybackState()
    }

    func updateLoudness(_ newValue: Double) {
        guard canAdjustLoudness else { return }

        loudnessLevel = min(max(newValue, 0), 1)
        applyTonePlaybackState()
        loudnessEvents.append(MeasurementTraceEvent(timestamp: Date(), value: loudnessLevel))
    }

    func submitMatch() async -> Bool {
        guard let startedAt else {
            errorMessage = "Task start timestamp is missing."
            return false
        }
        guard canSubmit else {
            errorMessage = matchingPauseMessage ?? "Resolve task validation before submitting."
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
                systemOutputVolumeAtStart: outputVolumeAtStart,
                systemOutputVolumeAtSubmit: currentOutputVolume,
                didSystemOutputVolumeChange: hasOutputVolumeChanged,
                loudnessEvents: loudnessEvents,
                ambientEvents: ambientEvents,
                systemOutputVolumeEvents: outputVolumeEvents,
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
                self.applyTonePlaybackState()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyTonePlaybackState() {
        guard step == .matching else { return }

        if canAdjustLoudness {
            tonePlayer.start()
            tonePlayer.setVolume(loudnessLevel)
        } else {
            tonePlayer.setVolume(0)
            if !isSupportedRoute {
                tonePlayer.stop()
            }
        }
    }

    private var isOutputVolumeStable: Bool {
        outputVolumeAtStart != nil && currentOutputVolume != nil && !hasOutputVolumeChanged
    }

    private func recordOutputVolumeIfMatching(_ volume: Double) {
        guard step == .matching else { return }
        outputVolumeEvents.append(MeasurementTraceEvent(timestamp: Date(), value: volume))
        if outputVolumeEvents.count > 2_000 {
            outputVolumeEvents.removeFirst(outputVolumeEvents.count - 2_000)
        }
    }

    private func updateOutputVolumeValidity() {
        guard step == .matching, let outputVolumeAtStart, let currentOutputVolume else {
            if step != .matching {
                hasOutputVolumeChanged = false
            }
            return
        }

        hasOutputVolumeChanged = abs(currentOutputVolume - outputVolumeAtStart) > StudyNo1Configuration.outputVolumeChangeTolerance
    }
}
