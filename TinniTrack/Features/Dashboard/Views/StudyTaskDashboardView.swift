import SwiftUI

struct StudyTaskDashboardView: View {
    let study: Study
    let enrollment: StudyEnrollment
    let profileTimezone: String?

    @StateObject private var viewModel: StudyTaskDashboardViewModel
    #if DEBUG
    @StateObject private var developerToolsViewModel: DeveloperToolsViewModel
    #endif
    @State private var isOrientationPresented = false
    @State private var activeLoudnessTask: ScheduledTask?

    private let studyService: StudyServiceProtocol
    private let loudnessViewModel: LoudnessMatchTaskFlowViewModel?

    init(
        study: Study,
        enrollment: StudyEnrollment,
        profileTimezone: String? = nil,
        coordinator: AudiogramImportCoordinating? = nil,
        studyService: StudyServiceProtocol? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        let resolvedStudyService = studyService ?? SupabaseStudyService()
        let resolvedCoordinator: AudiogramImportCoordinating
        let resolvedLoudnessViewModel: LoudnessMatchTaskFlowViewModel?
        #if DEBUG
        if UITestAudioPreflightFixture.isEnabled(processInfo: processInfo) {
            resolvedCoordinator = UITestAudioPreflightFixture.makeAudiogramCoordinator()
            resolvedLoudnessViewModel = UITestAudioPreflightFixture.makeLoudnessViewModel(
                processInfo: processInfo
            )
        } else {
            resolvedCoordinator = coordinator ?? AudiogramImportCoordinator()
            resolvedLoudnessViewModel = nil
        }
        #else
        resolvedCoordinator = coordinator ?? AudiogramImportCoordinator()
        resolvedLoudnessViewModel = nil
        #endif

        self.study = study
        self.enrollment = enrollment
        self.profileTimezone = profileTimezone
        self.studyService = resolvedStudyService
        self.loudnessViewModel = resolvedLoudnessViewModel
        _viewModel = StateObject(
            wrappedValue: StudyTaskDashboardViewModel(
                study: study,
                enrollment: enrollment,
                coordinator: resolvedCoordinator,
                studyService: resolvedStudyService,
                profileTimezone: profileTimezone
            )
        )
        #if DEBUG
        _developerToolsViewModel = StateObject(
            wrappedValue: DeveloperToolsViewModel(service: SupabaseDeveloperToolingService())
        )
        #endif
    }

    var body: some View {
        content
            .navigationTitle(study.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadIfNeeded()
            }
            .fullScreenCover(isPresented: $isOrientationPresented, onDismiss: handleOrientationDismissed) {
                orientationSheet
            }
            .fullScreenCover(item: $activeLoudnessTask) { task in
                LoudnessMatchTaskModalFlowView(
                    scheduledTask: task,
                    enrollment: enrollment,
                    studyService: studyService,
                    viewModel: loudnessViewModel
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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 92, weight: .medium))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    LoudnessMatchModalTitleBlock(
                        title: "Welcome to Study No. 1",
                        bodyText: "We will set up your hearing-test baseline, then run the same tinnitus loudness-match flow used for every Study No. 1 task."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: max(0, proxy.size.height - 48), alignment: .top)
                .padding(.horizontal, 34)
                .padding(.vertical, 24)
            }
            .accessibilityIdentifier("study_orientation_required_content")
        }
        .background(LoudnessMatchModalColors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LoudnessMatchModalPrimaryButton(title: "Begin Orientation") {
                isOrientationPresented = true
            }
            .accessibilityIdentifier("study_begin_orientation_button")
            .padding(.horizontal, 34)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var blockedPrerequisiteContent: some View {
        studyGateContent(
            title: "Study Tasks Are Temporarily Locked",
            message: "A hearing-test baseline is required before you can run loudness tasks.",
            actionTitle: "Resolve Prerequisites",
            actionAccessibilityIdentifier: "study_resolve_prerequisites_button",
            accessibilityIdentifier: "study_prerequisites_blocked_content"
        )
    }

    private func studyGateContent(
        title: String,
        message: String,
        actionTitle: String,
        actionAccessibilityIdentifier: String,
        accessibilityIdentifier: String
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .lineLimit(3)
                        .minimumScaleFactor(0.86)

                    Text(message)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LoudnessMatchModalPrimaryButton(title: actionTitle) {
                    isOrientationPresented = true
                }
                .padding(.top, 2)
                .accessibilityIdentifier(actionAccessibilityIdentifier)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 28)
        }
        .background(LoudnessMatchModalColors.background)
        .accessibilityIdentifier(accessibilityIdentifier)
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

            #if DEBUG
            StudyTaskDeveloperToolsSection(viewModel: developerToolsViewModel) {
                await viewModel.refresh()
            }
            #endif

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
                            onStart: { activeLoudnessTask = task }
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
            viewModel: viewModel,
            enrollment: enrollment,
            studyService: studyService,
            loudnessViewModel: loudnessViewModel
        )
    }

    private func handleOrientationDismissed() {
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
