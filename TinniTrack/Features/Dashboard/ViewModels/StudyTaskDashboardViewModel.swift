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
    @Published private(set) var scheduledTasks: [ScheduledTask] = []
    @Published private(set) var isLoadingTasks = false
    @Published private(set) var taskLoadErrorMessage: String?
    @Published private(set) var isCompletingStudyOnboarding = false

    private let study: Study
    private var enrollment: StudyEnrollment?
    private let coordinator: AudiogramImportCoordinating
    private let studyService: StudyServiceProtocol
    private let profileTimezone: String?
    private var hasLoadedOnce = false
    private var hasUnlockedTasks = false
    private var latestUnlockedAudiogramDate: Date?

    init(
        study: Study,
        enrollment: StudyEnrollment? = nil,
        coordinator: AudiogramImportCoordinating,
        studyService: StudyServiceProtocol? = nil,
        profileTimezone: String? = nil
    ) {
        self.study = study
        self.enrollment = enrollment
        self.coordinator = coordinator
        self.studyService = studyService ?? SupabaseStudyService()
        self.profileTimezone = profileTimezone
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

    var requiresStudyOnboardingCompletion: Bool {
        guard let enrollment else { return false }
        guard StudyPrerequisiteRules.requiresAudiogramImport(for: study.slug) else { return false }
        return enrollment.onboardingCompletedAt == nil
    }

    var futureTasks: [ScheduledTask] {
        scheduledTasks
            .filter { $0.status == .scheduled }
            .sorted { $0.scheduledFor < $1.scheduledFor }
    }

    var completedTasks: [ScheduledTask] {
        scheduledTasks
            .filter { $0.status == .completed }
            .sorted {
                let lhs = $0.completedAt ?? $0.scheduledFor
                let rhs = $1.completedAt ?? $1.scheduledFor
                return lhs > rhs
            }
    }

    func canStart(_ task: ScheduledTask, at date: Date = Date()) -> Bool {
        task.isStartable(at: date)
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refresh() async {
        await evaluatePrerequisite(showLoadingState: !hasUnlockedTasks)
        hasLoadedOnce = true
        await reloadScheduledTasksIfReady()
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

    func completeStudyOnboarding() async {
        guard requiresStudyOnboardingCompletion else {
            return
        }

        guard isAudiogramPrerequisiteMet else {
            taskLoadErrorMessage = "Complete audiogram import before finishing orientation."
            return
        }

        guard let enrollment else {
            taskLoadErrorMessage = "Unable to find enrollment for this study."
            return
        }

        isCompletingStudyOnboarding = true
        defer { isCompletingStudyOnboarding = false }

        do {
            try await studyService.completeStudyNo1Onboarding(
                enrollmentID: enrollment.id,
                timezone: resolvedTimezoneIdentifier
            )

            self.enrollment = StudyEnrollment(
                id: enrollment.id,
                userID: enrollment.userID,
                studyID: enrollment.studyID,
                status: enrollment.status,
                enrolledAt: enrollment.enrolledAt,
                createdAt: enrollment.createdAt,
                onboardingCompletedAt: Date()
            )

            taskLoadErrorMessage = nil
            await reloadScheduledTasksIfReady(force: true)
        } catch {
            taskLoadErrorMessage = error.localizedDescription
        }
    }

    func didSubmitTask() async {
        await reloadScheduledTasksIfReady(force: true)
    }

    func dismissTaskError() {
        taskLoadErrorMessage = nil
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
        scheduledTasks = []
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

    private func reloadScheduledTasksIfReady(force: Bool = false) async {
        guard let enrollment else {
            scheduledTasks = []
            return
        }

        guard isAudiogramPrerequisiteMet else {
            if force {
                scheduledTasks = []
            }
            return
        }

        guard !requiresStudyOnboardingCompletion else {
            scheduledTasks = []
            return
        }

        if isLoadingTasks {
            return
        }

        isLoadingTasks = true
        defer { isLoadingTasks = false }

        do {
            let tasks = try await studyService.fetchScheduledTasks(enrollmentID: enrollment.id)
            scheduledTasks = tasks
            taskLoadErrorMessage = nil
        } catch {
            taskLoadErrorMessage = error.localizedDescription
            if force {
                scheduledTasks = []
            }
        }
    }

    private var resolvedTimezoneIdentifier: String {
        let trimmedProfileTimezone = profileTimezone?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedProfileTimezone,
           !trimmedProfileTimezone.isEmpty,
           TimeZone(identifier: trimmedProfileTimezone) != nil {
            return trimmedProfileTimezone
        }

        return TimeZone.current.identifier
    }
}
