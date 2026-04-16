//
//  StudyTaskDashboardViewModel.swift
//  TinniTrack
//

import Foundation
import Combine

@MainActor
final class StudyTaskDashboardViewModel: ObservableObject {
    enum ContentState: Equatable {
        case loading
        case blocked(AudiogramPrerequisiteState)
        case ready(latestAudiogramDate: Date?)
    }

    enum OrientationImportState: Equatable {
        case waitingForPermission
        case requestingOrChecking
        case success(hearingTestDate: Date?)
        case authorizedNoHearingTest
        case permissionDenied
        case error(message: String)
    }

    enum ReadySyncWarning: Equatable {
        case permissionDenied
        case noAudiogramInHealth
        case error(message: String)
    }

    @Published private(set) var contentState: ContentState = .loading
    @Published private(set) var isSyncing = false
    @Published private(set) var orientationImportState: OrientationImportState = .requestingOrChecking
    @Published private(set) var readySyncWarning: ReadySyncWarning?

    private let study: Study
    private let coordinator: AudiogramImportCoordinating
    private var hasLoadedOnce = false
    private var hasUnlockedTasks = false
    private var latestUnlockedAudiogramDate: Date?

    init(study: Study, coordinator: AudiogramImportCoordinating) {
        self.study = study
        self.coordinator = coordinator
    }

    var requiresAudiogramImport: Bool {
        StudyPrerequisiteRules.requiresAudiogramImport(for: study.slug)
    }

    var isAudiogramPrerequisiteMet: Bool {
        if case .ready = contentState {
            return true
        }
        return false
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refresh() async {
        await evaluatePrerequisite(showLoadingState: !hasUnlockedTasks)
        hasLoadedOnce = true
    }

    func importOrSyncAudiograms() async {
        await requestImportThenReevaluate()
    }

    func connectAppleHealthForOrientation() async {
        await requestImportThenReevaluate()
    }

    func checkOrientationImportStatus() async {
        await evaluatePrerequisite(showLoadingState: false)
    }

    private func requestImportThenReevaluate() async {
        guard requiresAudiogramImport else { return }

        isSyncing = true
        orientationImportState = .requestingOrChecking

        do {
            _ = try await coordinator.importFromHealthKit()
        } catch {
            // The prerequisite reevaluation below maps final UX state.
        }

        isSyncing = false
        await evaluatePrerequisite(showLoadingState: false)
    }

    private func evaluatePrerequisite(showLoadingState: Bool) async {
        guard requiresAudiogramImport else {
            hasUnlockedTasks = true
            latestUnlockedAudiogramDate = nil
            readySyncWarning = nil
            contentState = .ready(latestAudiogramDate: nil)
            orientationImportState = .success(hearingTestDate: nil)
            return
        }

        if showLoadingState {
            contentState = .loading
        }

        orientationImportState = .requestingOrChecking
        let prerequisiteState = await coordinator.evaluatePrerequisite()
        applyPrerequisiteState(prerequisiteState)
    }

    private func applyPrerequisiteState(_ state: AudiogramPrerequisiteState) {
        switch state {
        case .met(let latestMeasuredAt):
            hasUnlockedTasks = true
            latestUnlockedAudiogramDate = latestMeasuredAt
            readySyncWarning = nil
            contentState = .ready(latestAudiogramDate: latestMeasuredAt)
            orientationImportState = .success(hearingTestDate: latestMeasuredAt)
        case .needsPermission:
            orientationImportState = .waitingForPermission
            applyBlockedOrWarningState(for: state)
        case .permissionDenied:
            orientationImportState = .permissionDenied
            applyBlockedOrWarningState(for: state)
        case .noAudiogramInHealth:
            orientationImportState = .authorizedNoHearingTest
            applyBlockedOrWarningState(for: state)
        case .error(let message):
            orientationImportState = .error(message: message)
            applyBlockedOrWarningState(for: state)
        }
    }

    private func applyBlockedOrWarningState(for state: AudiogramPrerequisiteState) {
        if hasUnlockedTasks {
            contentState = .ready(latestAudiogramDate: latestUnlockedAudiogramDate)
            readySyncWarning = warning(for: state)
            return
        }

        contentState = .blocked(state)
        readySyncWarning = nil
    }

    private func warning(for state: AudiogramPrerequisiteState) -> ReadySyncWarning? {
        switch state {
        case .met:
            return nil
        case .needsPermission, .permissionDenied:
            return .permissionDenied
        case .noAudiogramInHealth:
            return .noAudiogramInHealth
        case .error(let message):
            return .error(message: message)
        }
    }
}
