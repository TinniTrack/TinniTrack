import Foundation
import Testing
@testable import TinniTrack

@MainActor
struct LoudnessMatchTaskFlowViewModelTests {
    private let timestamp = Date(timeIntervalSince1970: 1_800_020_000)

    @Test
    func defaultParticipantWorkflowBuildsPlaybackRequestAfterMeasuredPreflightAndThreshold() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        await completePreflight(viewModel)
        completeMeasuredThreshold(viewModel, laterality: .right)
        viewModel.adjustLevel(.louder)
        viewModel.playTone()

        let request = try #require(player.playedRequests.last)
        #expect(request.frequencyHz == 1_000)
        #expect(request.levelDBHL == 16)
        #expect(request.channel == .right)
        #expect(viewModel.isPlaying)
        #expect(viewModel.events.contains { $0.kind == .playbackPlanned })

        let stopCountBeforeLoudnessStop = player.stopCallCount
        viewModel.stopTone()

        #expect(player.stopCallCount == stopCountBeforeLoudnessStop + 1)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.events.last?.kind == .stopRequested)
    }

    @Test
    func thresholdWorkflowLogsPresentationsAndRecordsMeasuredThreshold() async throws {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )

        await completePreflight(viewModel)
        viewModel.selectLaterality(.left)
        viewModel.playThresholdTone()
        viewModel.recordThresholdResponse(.heard)

        let thresholdRequest = try #require(player.playedRequests.first)
        #expect(thresholdRequest.levelDBHL == 30)
        #expect(viewModel.events.contains { $0.kind == .thresholdPlaybackPlanned })
        #expect(viewModel.events.contains { $0.kind == .thresholdResponseRecorded && $0.response == "heard" })

        for response in [
            TinnitusThresholdResponse.heard,
            .heard,
            .notHeard,
            .notHeard,
            .heard,
            .notHeard,
            .notHeard,
            .heard
        ] {
            recordThresholdCycle(viewModel, response: response)
        }

        guard case .readyForTrial(_, let candidateLevel) = viewModel.protocolState else {
            Issue.record("Expected loudness trial after measured threshold")
            return
        }
        #expect(candidateLevel == 15)
        #expect(viewModel.completedSummary == nil)
        #expect(viewModel.events.contains { $0.kind == .thresholdRecorded && $0.presentedLevelDBHL == 10 })
    }

    @Test
    func viewModelCompletesThreeTrialsAndExposesSummary() async {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        await completePreflight(viewModel)
        completeMeasuredThreshold(viewModel, laterality: .left)

        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .softer, confidence: .medium)
        acceptCurrentTrial(viewModel, adjustment: .muchLouder, confidence: .low)

        #expect(viewModel.isComplete)
        #expect(viewModel.completedSummary?.trials.map(\.acceptedLevelDBHL) == [16, 14, 20])
        #expect(viewModel.completedSummary?.medianMatchedDBHL == 16)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.lowConfidence) == true)
    }

    @Test
    func failedGuardrailsRefusePlaybackAndKeepPreflightLocked() async {
        let failed = CalibratedAudioGuardrailPolicy().validate(
            route: CalibratedAudioRouteDetails(outputs: []),
            outputVolume: 1.0,
            timestamp: timestamp
        )
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: MockCalibratedTonePlayer(),
            guardrailProvider: { failed },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        await completePreflight(viewModel)
        viewModel.selectLaterality(.left)

        viewModel.playThresholdTone()

        guard case .missingPreflight = viewModel.message else {
            Issue.record("Expected missing preflight because guardrails failed")
            return
        }
    }

    @Test
    func guardedPlaybackRequiresFullPreflight() {
        let player = MockCalibratedTonePlayer()
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            player: player,
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        viewModel.selectLaterality(.left)

        viewModel.playTone()

        guard case .missingPreflight = viewModel.message else {
            Issue.record("Expected missing preflight message")
            return
        }
        #expect(player.playedRequests.isEmpty)
    }

    @Test
    func preflightUsesEnvironmentGateResult() async {
        let passing = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        await completePreflight(passing)
        #expect(passing.preflightReady)
        #expect(passing.environmentGateResult?.gateResult == .passed)

        let failing = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 46, 33, 47, 34])
        )
        failing.fitSealConfirmed = true
        failing.safetyAcknowledged = true
        failing.refreshGuardrails()
        await failing.runEnvironmentGate()

        #expect(failing.preflightReady == false)
        #expect(failing.message == .environmentGateFailed)
    }

    @Test
    func completedStudyABuildsPhase6PayloadWithMeasuredThresholdAndPreflightMetadata() async throws {
        let viewModel = await completedViewModel()
        let payload = try viewModel.makePhase6Payload(
            scheduledTask: scheduledTask(),
            enrollment: enrollment(),
            submittedAt: timestamp.addingTimeInterval(100)
        )

        #expect(payload.identifiers.enrollmentId == enrollment().id.uuidString)
        #expect(payload.identifiers.scheduledTaskId == scheduledTask().id.uuidString)
        #expect(payload.device.deviceModel == "iPhone17,2")
        #expect(payload.airPods.modelIdentifier == "AIRPODSPROV2")
        #expect(payload.environment.samplesDBA == [31, 32, 33, 34, 35])
        #expect(payload.environment.gateResult == .passed)
        #expect(payload.fitSeal.status == .confirmedPassed)
        #expect(payload.safety.acknowledgedAt != nil)
        #expect(payload.threshold.source == .measured)
        #expect(payload.threshold.levelDBHL == 10)
        #expect(payload.summary.medianMatchedDBHL == 16)
    }

    @Test
    func submitCompletedRunUsesStudyServiceBoundary() async {
        let viewModel = await completedViewModel()
        let service = MockStudyService()
        let task = scheduledTask()
        let currentEnrollment = enrollment()

        await viewModel.submitCompletedRun(
            scheduledTask: task,
            enrollment: currentEnrollment,
            studyService: service
        )

        #expect(viewModel.hasSubmitted)
        #expect(service.submissions.count == 1)
        #expect(service.submissions.first?.scheduledTaskID == task.id)
        #expect(service.submissions.first?.enrollmentID == currentEnrollment.id)
        #expect(service.submissions.first?.submission.matchedLevel == 16)
        #expect(service.submissions.first?.submission.rawPayload["payloadVersion"] == .string("phase-6-study-a-v1"))
    }

    @Test
    func thresholdUnavailablePathPreservesQualityFlagsButCannotSubmitStudyA() async {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35])
        )
        await completePreflight(viewModel)
        viewModel.selectLaterality(.unclear)
        viewModel.markThresholdUnavailable()

        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)

        #expect(viewModel.completedSummary?.medianDBSL == nil)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.thresholdUnavailable) == true)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.dbSLInvalid) == true)
        #expect(viewModel.completedSummary?.qualityFlags.contains(.ambiguousLaterality) == true)
        #expect(throws: Phase6PayloadValidationError.self) {
            _ = try viewModel.makePhase6Payload(
                scheduledTask: scheduledTask(),
                enrollment: enrollment(),
                submittedAt: timestamp
            )
        }
    }

    private func acceptCurrentTrial(
        _ viewModel: LoudnessMatchTaskFlowViewModel,
        adjustment: TinnitusLoudnessAdjustment,
        confidence: TinnitusConfidenceRating
    ) {
        viewModel.adjustLevel(adjustment)
        viewModel.acceptCurrentLevel()
        viewModel.recordConfidence(confidence)
    }

    private func completePreflight(_ viewModel: LoudnessMatchTaskFlowViewModel) async {
        viewModel.fitSealConfirmed = true
        viewModel.safetyAcknowledged = true
        viewModel.refreshGuardrails()
        await viewModel.runEnvironmentGate()
    }

    private func completeMeasuredThreshold(
        _ viewModel: LoudnessMatchTaskFlowViewModel,
        laterality: TinnitusLaterality
    ) {
        viewModel.selectLaterality(laterality)
        finishThresholdAt10DBHL(viewModel)
    }

    private func finishThresholdAt10DBHL(_ viewModel: LoudnessMatchTaskFlowViewModel) {
        for response in [
            TinnitusThresholdResponse.heard,
            .heard,
            .heard,
            .notHeard,
            .notHeard,
            .heard,
            .notHeard,
            .notHeard,
            .heard
        ] {
            recordThresholdCycle(viewModel, response: response)
        }
    }

    private func recordThresholdCycle(
        _ viewModel: LoudnessMatchTaskFlowViewModel,
        response: TinnitusThresholdResponse
    ) {
        viewModel.playThresholdTone()
        viewModel.recordThresholdResponse(response)
    }

    private func completedViewModel() async -> LoudnessMatchTaskFlowViewModel {
        let viewModel = LoudnessMatchTaskFlowViewModel(
            engine: makeEngine(),
            guardrailProvider: { passedGuardrails() },
            environmentMeter: MockEnvironmentSPLMeter(samplesDBA: [31, 32, 33, 34, 35]),
            runtimeContextProvider: MockPhase6RuntimeContextProvider(),
            submissionExporter: Phase6LoudnessMatchSubmissionExporter(appVersion: "1.2.3"),
            dateProvider: { timestamp }
        )
        await completePreflight(viewModel)
        completeMeasuredThreshold(viewModel, laterality: .left)
        acceptCurrentTrial(viewModel, adjustment: .louder, confidence: .high)
        acceptCurrentTrial(viewModel, adjustment: .softer, confidence: .medium)
        acceptCurrentTrial(viewModel, adjustment: .muchLouder, confidence: .low)
        return viewModel
    }

    private func makeEngine() -> TinnitusProtocolEngine {
        TinnitusProtocolEngine(
            playbackPlanner: CalibratedTonePlaybackPlanner(dateProvider: { timestamp }),
            dateProvider: { timestamp }
        )
    }

    private func passedGuardrails() -> CalibratedAudioGuardrailValidation {
        CalibratedAudioGuardrailPolicy().validate(
            route: supportedRoute(),
            outputVolume: 1.0,
            timestamp: timestamp
        )
    }

    private func supportedRoute() -> CalibratedAudioRouteDetails {
        CalibratedAudioRouteDetails(outputs: [
            CalibratedAudioRouteOutput(
                portName: "Verified AirPods Pro 2",
                portType: .bluetoothA2DP,
                portUID: "verified-airpods-pro-2",
                channelNames: ["left", "right"],
                verifiedCalibratedHeadphoneIdentifier: "AIRPODSPROV2",
                verificationSource: .researchProtocol
            )
        ])
    }

    private func scheduledTask() -> ScheduledTask {
        ScheduledTask(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            enrollmentID: enrollment().id,
            taskKey: "lm_1khz_v1",
            taskVersion: 1,
            scheduledFor: timestamp,
            windowStart: timestamp.addingTimeInterval(-60),
            windowEnd: timestamp.addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        )
    }

    private func enrollment() -> StudyEnrollment {
        StudyEnrollment(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            studyID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            status: .enrolled,
            enrolledAt: timestamp,
            createdAt: timestamp
        )
    }
}

private struct MockEnvironmentSPLMeter: EnvironmentSPLMeasuring {
    let samplesDBA: [Double]

    func runGate(configuration: TinnitusEnvironmentSPLGateConfiguration) async throws -> TinnitusEnvironmentSPLGateResult {
        TinnitusEnvironmentSPLGateEvaluator().evaluate(samplesDBA: samplesDBA, configuration: configuration)
    }
}

@MainActor
private final class MockCalibratedTonePlayer: CalibratedTonePlaying {
    var playedRequests: [CalibratedTonePlaybackRequest] = []
    var stopCallCount = 0

    func play(_ request: CalibratedTonePlaybackRequest) throws -> CalibratedTonePlaybackMetadata {
        playedRequests.append(request)
        return try CalibratedTonePlaybackPlanner(dateProvider: {
            Date(timeIntervalSince1970: 1_800_020_000)
        })
        .makePlan(for: request)
        .metadata
        .started(at: Date(timeIntervalSince1970: 1_800_020_001))
    }

    func stop() -> CalibratedTonePlaybackMetadata? {
        stopCallCount += 1
        guard let request = playedRequests.last else {
            return nil
        }
        return try? CalibratedTonePlaybackPlanner(dateProvider: {
            Date(timeIntervalSince1970: 1_800_020_000)
        })
        .makePlan(for: request)
        .metadata
        .started(at: Date(timeIntervalSince1970: 1_800_020_001))
        .stopped(at: Date(timeIntervalSince1970: 1_800_020_002))
    }
}

private struct MockPhase6RuntimeContextProvider: Phase6RuntimeContextProviding {
    func deviceContext() -> Phase6DeviceContext {
        Phase6DeviceContext(
            deviceModel: "iPhone17,2",
            systemName: "iOS",
            systemVersion: "26.0"
        )
    }

    func audioSessionContext() -> Phase6AudioSessionContext {
        Phase6AudioSessionContext(
            category: "playback",
            mode: "default",
            options: [],
            sampleRate: 44_100,
            bufferSize: 512
        )
    }

    func airPodsContext(guardrailValidation: CalibratedAudioGuardrailValidation) -> Phase6AirPodsContext {
        Phase6AirPodsContext(
            modelIdentifier: guardrailValidation.metadata.supportedHeadphoneIdentifier,
            firmwareVersion: nil,
            unavailableReason: "Firmware unavailable in test fixture."
        )
    }
}

private final class MockStudyService: StudyServiceProtocol {
    struct Submission: Equatable {
        let scheduledTaskID: UUID
        let enrollmentID: UUID
        let submission: LoudnessMatchSubmission
    }

    var submissions: [Submission] = []

    func fetchStudies() async throws -> [Study] { [] }
    func fetchMyEnrollments() async throws -> [StudyEnrollment] { [] }
    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] { [] }
    func enroll(studyID: UUID) async throws {}
    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {
        submissions.append(Submission(
            scheduledTaskID: scheduledTaskID,
            enrollmentID: enrollmentID,
            submission: submission
        ))
    }
}
