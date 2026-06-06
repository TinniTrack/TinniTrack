//
//  StudyTaskDashboardView.swift
//  TinniTrack
//

import SwiftUI
import UIKit

struct StudyTaskDashboardView: View {
    private enum OrientationStep {
        case hearingTest
        case importAudiogram
        case nextSteps
    }

    let study: Study
    let enrollment: StudyEnrollment
    let profileTimezone: String?

    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: StudyTaskDashboardViewModel
    @State private var isOrientationPresented = false
    @State private var orientationStep: OrientationStep = .hearingTest
    @State private var selectedTask: ScheduledTask?

    private let studyService: StudyServiceProtocol

    init(
        study: Study,
        enrollment: StudyEnrollment,
        profileTimezone: String? = nil,
        coordinator: AudiogramImportCoordinating = AudiogramImportCoordinator(),
        studyService: StudyServiceProtocol? = nil
    ) {
        self.study = study
        self.enrollment = enrollment
        self.profileTimezone = profileTimezone
        self.studyService = studyService ?? SupabaseStudyService()
        _viewModel = StateObject(
            wrappedValue: StudyTaskDashboardViewModel(
                study: study,
                enrollment: enrollment,
                coordinator: coordinator,
                studyService: studyService ?? SupabaseStudyService(),
                profileTimezone: profileTimezone
            )
        )
    }

    var body: some View {
        content
            .navigationTitle(study.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadIfNeeded()
            }
            .sheet(isPresented: $isOrientationPresented, onDismiss: handleOrientationDismissed) {
                orientationSheet
            }
            .navigationDestination(item: $selectedTask) { task in
                LoudnessMatchTaskFlowView(
                    scheduledTask: task,
                    enrollment: enrollment,
                    studyService: studyService
                ) {
                    Task { await viewModel.didSubmitTask() }
                }
            }
            .alert("Unable to Continue", isPresented: Binding(
                get: { viewModel.taskLoadErrorMessage != nil },
                set: { shouldShow in
                    if !shouldShow {
                        viewModel.dismissTaskError()
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.dismissTaskError()
                }
            } message: {
                Text(viewModel.taskLoadErrorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.requiresStudyOnboardingCompletion {
            orientationRequiredContent
        } else {
            switch viewModel.contentState {
            case .loading:
                ProgressView("Checking study prerequisites…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
            case .blocked:
                blockedPrerequisiteContent
            case .ready(let latestAudiogramDate):
                readyContent(latestAudiogramDate: latestAudiogramDate)
            }
        }
    }

    private var orientationRequiredContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                prerequisiteCard(
                    title: "Welcome. Thanks for choosing to participate in this study!",
                    message: "Before tasks can start, complete orientation and import your hearing-test baseline."
                )

                actionButton(title: "Begin Orientation", isPrimary: true) {
                    orientationStep = .hearingTest
                    isOrientationPresented = true
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var blockedPrerequisiteContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                prerequisiteCard(
                    title: "Study Tasks Are Temporarily Locked",
                    message: "A hearing-test baseline is required before you can run loudness tasks."
                )

                actionButton(title: "Resolve Prerequisites", isPrimary: true) {
                    orientationStep = .importAudiogram
                    isOrientationPresented = true
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func readyContent(latestAudiogramDate: Date?) -> some View {
        List {
            if let warning = viewModel.readySyncWarning {
                Section {
                    readyWarningCard(for: warning)
                }
            }

            if viewModel.requiresAudiogramImport {
                Section("Audiogram Baseline") {
                    if let latestAudiogramDate {
                        LabeledContent("Last Imported", value: Self.dateFormatter.string(from: latestAudiogramDate))
                    } else {
                        Text("Imported")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await viewModel.importOrSyncAudiograms() }
                    } label: {
                        HStack {
                            if viewModel.isSyncing {
                                ProgressView()
                            }
                            Text(viewModel.isSyncing ? "Syncing from Health…" : "Sync from Health")
                        }
                    }
                    .disabled(viewModel.isSyncing)
                }
            }

            Section("Future Tasks") {
                if viewModel.isLoadingTasks {
                    HStack {
                        ProgressView()
                        Text("Loading tasks…")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.futureTasks.isEmpty {
                    Text("No upcoming tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.futureTasks) { task in
                        futureTaskRow(task)
                    }
                }
            }

            Section("Completed Tasks") {
                if viewModel.completedTasks.isEmpty {
                    Text("No completed tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.completedTasks) { task in
                        completedTaskRow(task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func futureTaskRow(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day \(task.dayIndex + 1), Slot \(task.slotIndex + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(Self.windowFormatter.string(from: task.windowStart) + " - " + Self.timeFormatter.string(from: task.windowEnd))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                selectedTask = task
            } label: {
                Text("Start Task")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStart(task))

            if !viewModel.canStart(task) {
                Text(startAvailabilityMessage(for: task))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func completedTaskRow(_ task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Day \(task.dayIndex + 1), Slot \(task.slotIndex + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let completedAt = task.completedAt {
                Text("Completed \(Self.dateFormatter.string(from: completedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Completed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var orientationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch orientationStep {
                    case .hearingTest:
                        orientationHearingTestStep
                    case .importAudiogram:
                        orientationImportStep
                    case .nextSteps:
                        orientationNextSteps
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Study Orientation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if orientationStep != .hearingTest {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            moveToPreviousOrientationStep()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }
                        .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        isOrientationPresented = false
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var orientationHearingTestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)

            hearingTestInstructions

            actionButton(title: "Continue", isPrimary: true) {
                orientationStep = .importAudiogram
            }
        }
    }

    private var orientationImportStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)

            importStateContent

            actionButton(title: "Continue", isPrimary: true) {
                orientationStep = .nextSteps
            }
            .disabled(!viewModel.isAudiogramPrerequisiteMet)
            .opacity(viewModel.isAudiogramPrerequisiteMet ? 1 : 0.5)
        }
        .task {
            await viewModel.checkOrientationImportStatus()
        }
    }

    private var orientationNextSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 3")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(.secondary)

            prerequisiteCard(
                title: "Finish Orientation",
                message: "Once you finish, we will generate your full Study No. 1 task schedule."
            )

            actionButton(
                title: viewModel.isCompletingStudyOnboarding ? "Finishing…" : "Finish Orientation",
                isPrimary: true,
                isLoading: viewModel.isCompletingStudyOnboarding
            ) {
                Task {
                    await viewModel.completeStudyOnboarding()
                    if !viewModel.requiresStudyOnboardingCompletion {
                        isOrientationPresented = false
                    }
                }
            }
            .disabled(!viewModel.isAudiogramPrerequisiteMet || viewModel.isCompletingStudyOnboarding)
            .opacity((viewModel.isAudiogramPrerequisiteMet && !viewModel.isCompletingStudyOnboarding) ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var importStateContent: some View {
        switch viewModel.orientationImportState {
        case .waitingForPermission:
            prerequisiteCard(
                title: "Connect Apple Health",
                message: "Allow Apple Health access so we can import your hearing test into the study."
            )

            actionButton(
                title: viewModel.isSyncing ? "Connecting…" : "Connect Apple Health",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }
        case .requestingOrChecking:
            ProgressView("Checking hearing test import…")
                .frame(maxWidth: .infinity, alignment: .leading)

        case .success(let hearingTestDate):
            prerequisiteCard(
                title: "Hearing Test Imported",
                message: successMessageForHearingTestDate(hearingTestDate)
            )

        case .authorizedNoHearingTest:
            prerequisiteCard(
                title: "No Hearing Test Found Yet",
                message: "We can access your health data, but we are not seeing a hearing test yet."
            )

            hearingTestInstructions

            actionButton(
                title: viewModel.isSyncing ? "Checking…" : "Check Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }

        case .permissionDenied:
            prerequisiteCard(
                title: "Permission Required",
                message: "Approve hearing-test access in Apple Health, then return here and check again."
            )

            actionButton(title: "Open Health App", isPrimary: false) {
                guard let healthAppURL = URL(string: "x-apple-health://") else {
                    return
                }
                openURL(healthAppURL)
            }

            actionButton(
                title: viewModel.isSyncing ? "Checking…" : "Check Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.checkOrientationImportStatus() }
            }

        case .error(let message):
            prerequisiteCard(
                title: "Import Unavailable",
                message: message
            )

            actionButton(
                title: viewModel.isSyncing ? "Retrying…" : "Try Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }
        }
    }

    private var hearingTestInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            prerequisiteCard(
                title: "Take an Apple Hearing Test",
                message: "Use AirPods Pro with your paired iPhone. In Settings > your AirPods, tap Take a Hearing Test. Then come back and continue orientation."
            )

            Link(
                "Need help taking an Apple Hearing Test?",
                destination: URL(string: "https://support.apple.com/en-us/120991")!
            )
            .font(.subheadline)
            .fontWeight(.semibold)
        }
    }

    private func prerequisiteCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private func actionButton(
        title: String,
        isPrimary: Bool,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(isPrimary ? .white : .blue)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(isPrimary ? Color.blue : Color.white)
        .foregroundStyle(isPrimary ? Color.white : Color.blue)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(isPrimary ? 0 : 0.08), radius: 3, x: 0, y: 1)
    }

    private func successMessageForHearingTestDate(_ date: Date?) -> String {
        guard let date else {
            return "Success! We got your hearing test."
        }
        return "Success! We got your hearing test from \(Self.hearingTestDateFormatter.string(from: date))."
    }

    private func readyWarningCard(
        for warning: StudyTaskDashboardViewModel.ReadySyncWarning
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(readyWarningTitle(for: warning))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(readyWarningMessage(for: warning))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func readyWarningTitle(
        for warning: StudyTaskDashboardViewModel.ReadySyncWarning
    ) -> String {
        switch warning {
        case .permissionDenied:
            return "Health Access Needed for Sync"
        case .noAudiogramInHealth:
            return "No New Hearing Test Found"
        case .error:
            return "Unable to Sync from Health"
        }
    }

    private func readyWarningMessage(
        for warning: StudyTaskDashboardViewModel.ReadySyncWarning
    ) -> String {
        switch warning {
        case .permissionDenied:
            return "Tasks remain available, but we could not read hearing-test data. Re-enable Health access and tap Sync from Health again."
        case .noAudiogramInHealth:
            return "We can access your health data, but we are not seeing a hearing test yet."
        case .error(let message):
            return message
        }
    }

    private func startAvailabilityMessage(for task: ScheduledTask) -> String {
        let now = Date()
        if now < task.windowStart {
            return "Available at \(Self.windowFormatter.string(from: task.windowStart))."
        }

        if now > task.windowEnd {
            return "This task window has ended."
        }

        return "This task is temporarily unavailable."
    }

    private func handleOrientationDismissed() {
        orientationStep = .hearingTest
        Task { await viewModel.refresh() }
    }

    private func moveToPreviousOrientationStep() {
        switch orientationStep {
        case .hearingTest:
            break
        case .importAudiogram:
            orientationStep = .hearingTest
        case .nextSteps:
            orientationStep = .importAudiogram
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let hearingTestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let windowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationStack {
        StudyTaskDashboardView(
            study: Study(
                id: UUID(),
                slug: StudyPrerequisiteRules.studyNo1Slug,
                title: "Study No. 1",
                description: "Audiogram prerequisite preview",
                status: .recruiting,
                createdAt: Date()
            ),
            enrollment: StudyEnrollment(
                id: UUID(),
                userID: UUID(),
                studyID: UUID(),
                status: .enrolled,
                enrolledAt: Date(),
                createdAt: Date(),
                onboardingCompletedAt: Date()
            ),
            coordinator: AudiogramImportCoordinator()
        )
    }
}
