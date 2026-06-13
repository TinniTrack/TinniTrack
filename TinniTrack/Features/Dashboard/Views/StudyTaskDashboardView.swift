import SwiftUI

struct StudyTaskDashboardView: View {
    let study: Study
    let enrollment: StudyEnrollment
    let profileTimezone: String?

    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: StudyTaskDashboardViewModel
    @State private var isOrientationPresented = false
    @State private var orientationStep: StudyTaskOrientationStep = .hearingTest
    @State private var selectedTask: ScheduledTask?

    private let studyService: StudyServiceProtocol

    init(
        study: Study,
        enrollment: StudyEnrollment,
        profileTimezone: String? = nil,
        coordinator: AudiogramImportCoordinating = AudiogramImportCoordinator(),
        studyService: StudyServiceProtocol? = nil
    ) {
        let resolvedStudyService = studyService ?? SupabaseStudyService()
        self.study = study
        self.enrollment = enrollment
        self.profileTimezone = profileTimezone
        self.studyService = resolvedStudyService
        _viewModel = StateObject(
            wrappedValue: StudyTaskDashboardViewModel(
                study: study,
                enrollment: enrollment,
                coordinator: coordinator,
                studyService: resolvedStudyService,
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
            .alert(
                "Unable to Continue",
                isPresented: Binding(
                    get: { viewModel.taskLoadErrorMessage != nil },
                    set: { shouldShow in
                        if !shouldShow {
                            viewModel.dismissTaskError()
                        }
                    }
                )
            ) {
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
                ProgressView("Checking study prerequisites...")
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
                StudyPrerequisiteCard(
                    title: "Welcome. Thanks for choosing to participate in this study!",
                    message: "Before tasks can start, complete orientation and import your hearing-test baseline."
                )

                StudyActionButton(title: "Begin Orientation", isPrimary: true) {
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
                StudyPrerequisiteCard(
                    title: "Study Tasks Are Temporarily Locked",
                    message: "A hearing-test baseline is required before you can run loudness tasks."
                )

                StudyActionButton(title: "Resolve Prerequisites", isPrimary: true) {
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
                    ReadySyncWarningCard(warning: warning)
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
                            Text(viewModel.isSyncing ? "Syncing from Health..." : "Sync from Health")
                        }
                    }
                    .disabled(viewModel.isSyncing)
                }
            }

            Section("Future Tasks") {
                if viewModel.isLoadingTasks {
                    HStack {
                        ProgressView()
                        Text("Loading tasks...")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.futureTasks.isEmpty {
                    Text("No upcoming tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.futureTasks) { task in
                        FutureStudyTaskRow(
                            task: task,
                            canStart: viewModel.canStart(task),
                            onStart: { selectedTask = task }
                        )
                    }
                }
            }

            Section("Completed Tasks") {
                if viewModel.completedTasks.isEmpty {
                    Text("No completed tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.completedTasks) { task in
                        CompletedStudyTaskRow(task: task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var orientationSheet: some View {
        StudyTaskOrientationSheet(
            step: $orientationStep,
            viewModel: viewModel,
            openHealthApp: openHealthApp,
            close: { isOrientationPresented = false }
        )
    }

    private func openHealthApp() {
        guard let healthAppURL = URL(string: "x-apple-health://") else { return }
        openURL(healthAppURL)
    }

    private func handleOrientationDismissed() {
        orientationStep = .hearingTest
        Task { await viewModel.refresh() }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
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
