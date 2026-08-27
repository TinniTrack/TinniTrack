//
//  HomeView.swift
//  TinniTrack
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var dashboardViewModel: HomeDashboardViewModel
    @State private var selectedTab: Tab = .dashboard
    @State private var dashboardNavigationPath = NavigationPath()
    private let studyService: StudyServiceProtocol
    private let consentService: ConsentServiceProtocol

    init(
        studyService: StudyServiceProtocol? = nil,
        consentService: ConsentServiceProtocol? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        #if DEBUG
        let uiTestStudyScenario = processInfo.environment["UITEST_MOCK_STUDY_SCENARIO"]
        let usesAudioPreflightFixture = UITestAudioPreflightFixture.isEnabled(processInfo: processInfo)
        let usesRecurringTaskFixture = processInfo.environment[
            UITestAudioPreflightFixture.recurringTaskEnvironmentKey
        ] == "1"
        if studyService == nil,
           consentService == nil,
           (processInfo.environment["UITEST_MOCK_STUDY_ENROLLMENT_SUCCESS"] == "1"
            || processInfo.environment["UITEST_MOCK_STUDY_ALREADY_ENROLLED"] == "1"
            || usesAudioPreflightFixture
            || usesRecurringTaskFixture
            || uiTestStudyScenario != nil) {
            let uiTestServices = UITestEnrollmentServices(processInfo: processInfo)
            self.studyService = uiTestServices
            self.consentService = uiTestServices
            _dashboardViewModel = StateObject(wrappedValue: HomeDashboardViewModel(studyService: uiTestServices))
            return
        }
        #endif

        let resolvedStudyService = studyService ?? SupabaseStudyService()
        self.studyService = resolvedStudyService
        self.consentService = consentService ?? SupabaseConsentService()
        _dashboardViewModel = StateObject(wrappedValue: HomeDashboardViewModel(studyService: resolvedStudyService))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $dashboardNavigationPath) {
                DashboardTabView(
                    firstName: displayFirstName,
                    profileTimezone: sessionStore.state.profile?.timezone,
                    viewModel: dashboardViewModel,
                    studyService: studyService,
                    consentService: consentService,
                    navigationPath: $dashboardNavigationPath
                )
            }
            .tabItem {
                Label("Dashboard", systemImage: "list.bullet.clipboard")
            }
            .tag(Tab.dashboard)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            .tag(Tab.profile)
        }
    }

    private var displayFirstName: String {
        let trimmed = sessionStore.state.profile?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Participant" : trimmed
    }
}

private enum Tab {
    case dashboard
    case profile
}

struct DashboardStudyDetailsRoute: Hashable {
    let studyCard: DashboardStudyCard

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.studyCard.id == rhs.studyCard.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(studyCard.id)
    }
}

private struct DashboardTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    let firstName: String
    let profileTimezone: String?
    @ObservedObject var viewModel: HomeDashboardViewModel
    let studyService: StudyServiceProtocol
    let consentService: ConsentServiceProtocol
    @Binding var navigationPath: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Text("CURRENT STUDIES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(0.8)
                    .foregroundStyle(DashboardColors.brandBlue)

                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DashboardStudyDetailsRoute.self) { route in
            destination(for: route)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.refreshForLifecycleEvent()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi, \(firstName)")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(.primary)
            Text("Track your tinnitus and participate in active studies.")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LazyVStack(spacing: 16) {
                ShimmerStudyCardView()
                ShimmerStudyCardView()
            }
        case .empty:
            ContentUnavailableView {
                Label("No studies available at this time.", systemImage: "magnifyingglass")
            } description: {
                Text("Please check back later.")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        case .failed(let message):
            VStack(spacing: 12) {
                ContentUnavailableView {
                    Label("Unable to Load Studies", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }

                Button("Retry") {
                    Task { await viewModel.refresh(retainingCurrentContent: false) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshing)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        case .loaded:
            LazyVStack(spacing: 16) {
                ForEach(viewModel.studies) { studyCard in
                    NavigationLink(value: DashboardStudyDetailsRoute(studyCard: studyCard)) {
                        StudyCardView(studyCard: studyCard)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("study_card_\(studyCard.study.slug)")
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: DashboardStudyDetailsRoute) -> some View {
        StudyDetailView(
            studyCard: route.studyCard,
            profileTimezone: profileTimezone,
            studyService: studyService,
            consentService: consentService,
            navigationPath: $navigationPath
        ) { enrollment in
            viewModel.confirmEnrollment(enrollment)
            Task { @MainActor in
                await viewModel.reconcileAfterEnrollment()
            }
        }
    }
}

private struct StudyCardView: View {
    let studyCard: DashboardStudyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image("TinnitusStudyIcon")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 8) {
                    Text(studyCard.study.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(studyCard.study.description)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(DashboardColors.cardDivider)
                .frame(height: 1)

            HStack(alignment: .center) {
                Spacer(minLength: 0)

                HStack(spacing: 20) {
                    Text(studyCard.displayBadgeText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(studyCard.badgeColor)
                        .clipShape(Capsule())

                    HStack(spacing: 5) {
                        Text(studyCard.callToActionText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DashboardColors.brandBlue)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DashboardColors.brandBlue)
                    }
                }
            }
        }
        .padding(20)
        .background(DashboardColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DashboardColors.cardStroke, lineWidth: 1)
        }
        .shadow(color: DashboardColors.cardShadow, radius: 4, x: 0, y: 2)
    }
}

private struct StudyDetailView: View {
    let studyCard: DashboardStudyCard
    let profileTimezone: String?
    let studyService: StudyServiceProtocol
    let consentService: ConsentServiceProtocol
    let onEnrollmentConfirmed: @MainActor (StudyEnrollment) -> Void

    @Binding private var navigationPath: NavigationPath
    @State private var confirmedEnrollment: StudyEnrollment?
    @State private var beganWithActiveEnrollment: Bool

    init(
        studyCard: DashboardStudyCard,
        profileTimezone: String?,
        studyService: StudyServiceProtocol,
        consentService: ConsentServiceProtocol,
        navigationPath: Binding<NavigationPath>,
        onEnrollmentConfirmed: @escaping @MainActor (StudyEnrollment) -> Void
    ) {
        self.studyCard = studyCard
        self.profileTimezone = profileTimezone
        self.studyService = studyService
        self.consentService = consentService
        self.onEnrollmentConfirmed = onEnrollmentConfirmed
        _navigationPath = navigationPath
        _confirmedEnrollment = State(
            initialValue: studyCard.isEnrolledActive ? studyCard.enrollment : nil
        )
        _beganWithActiveEnrollment = State(initialValue: studyCard.isEnrolledActive)
    }

    var body: some View {
        Group {
            if beganWithActiveEnrollment, let confirmedEnrollment {
                StudyTaskDashboardView(
                    study: studyCard.study,
                    enrollment: confirmedEnrollment,
                    profileTimezone: profileTimezone,
                    studyService: studyService
                )
            } else if canEnroll, let definition = StudyConsentCatalog.definition(for: studyCard.study.slug) {
                ZStack {
                    StudyConsentFlowView(
                        study: studyCard.study,
                        definition: definition,
                        consentService: consentService,
                        navigationPath: $navigationPath
                    ) { enrollment in
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            confirmedEnrollment = enrollment
                        }
                        onEnrollmentConfirmed(enrollment)
                    }
                    .opacity(confirmedEnrollment == nil ? 1 : 0)
                    .allowsHitTesting(confirmedEnrollment == nil)
                    .accessibilityHidden(confirmedEnrollment != nil)

                    if let confirmedEnrollment {
                        StudyTaskDashboardView(
                            study: studyCard.study,
                            enrollment: confirmedEnrollment,
                            profileTimezone: profileTimezone,
                            studyService: studyService
                        )
                        .zIndex(1)
                    }
                }
            } else {
                EnrollmentUnavailableView(
                    title: unavailableTitle,
                    message: unavailableMessage
                )
            }
        }
        .navigationTitle(confirmedEnrollment == nil ? "Study Details" : studyCard.study.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canEnroll: Bool {
        if case .recruiting = studyCard.study.status {
            return true
        }
        return false
    }

    private var unavailableTitle: String {
        if canEnroll {
            return "Enrollment Unavailable"
        }
        return "Study Not Recruiting"
    }

    private var unavailableMessage: String {
        if canEnroll {
            return "This study does not have an eConsent definition."
        }
        return "Enrollment is not open for this study right now."
    }
}

private struct EnrollmentUnavailableView: View {
    let title: String
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.circle")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(DashboardColors.brandBlue)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
            } label: {
                Label("Back to Dashboard", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
@MainActor
private final class UITestEnrollmentServices: StudyServiceProtocol, ConsentServiceProtocol {
    private let studyID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let enrollmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let scenario: Scenario
    private let servesRecurringTask: Bool
    private var isEnrolled: Bool
    private var finalizationAttemptCount = 0

    init(processInfo: ProcessInfo = .processInfo) {
        let usesRecurringTaskFixture = processInfo.environment[
            UITestAudioPreflightFixture.recurringTaskEnvironmentKey
        ] == "1"
        scenario = Scenario(
            rawValue: processInfo.environment["UITEST_MOCK_STUDY_SCENARIO"] ?? "success"
        ) ?? .success
        servesRecurringTask = usesRecurringTaskFixture
        isEnrolled = processInfo.environment["UITEST_MOCK_STUDY_ALREADY_ENROLLED"] == "1"
            || UITestAudioPreflightFixture.isEnabled(processInfo: processInfo)
            || usesRecurringTaskFixture
    }

    func fetchStudies() async throws -> [Study] {
        [
            Study(
                id: studyID,
                slug: StudyPrerequisiteRules.studyNo1Slug,
                title: "Loudness Matching Study",
                description: "Help us understand how tinnitus loudness changes throughout the day.",
                status: .recruiting,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
    }

    func fetchMyEnrollments() async throws -> [StudyEnrollment] {
        guard isEnrolled else { return [] }
        return [enrollment]
    }

    func availableEnrollmentRecovery(
        for study: Study
    ) async throws -> ConsentEnrollmentRecovery? {
        guard scenario == .pendingRecovery, !isEnrolled else { return nil }
        return .pendingEnrollment
    }

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        guard scenario == .pendingRecovery else {
            throw ConsentServiceError.noRecoverableConsent
        }
        isEnrolled = true
        return enrollment
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        finalizationAttemptCount += 1
        if scenario == .failOnce, finalizationAttemptCount == 1 {
            throw NSError(
                domain: "UITestEnrollmentServices",
                code: 503,
                userInfo: [NSLocalizedDescriptionKey: "Enrollment is temporarily unavailable."]
            )
        }
        isEnrolled = true
        return enrollment
    }

    func fetchScheduledTasks(enrollmentID: UUID) async throws -> [ScheduledTask] {
        guard servesRecurringTask, enrollmentID == self.enrollmentID else {
            return []
        }
        return [recurringLoudnessTask]
    }

    func beginStudyNo1OrientationThresholdTask(enrollmentID: UUID) async throws -> ScheduledTask {
        throw NSError(
            domain: "UITestEnrollmentServices",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No orientation threshold task configured for UI tests."]
        )
    }

    func completeStudyNo1Onboarding(enrollmentID: UUID, timezone: String) async throws {}

    func submitStudyNo1OrientationThreshold(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: StudyNo1OrientationThresholdSubmission
    ) async throws {}

    func submitLoudnessMatch(
        scheduledTaskID: UUID,
        enrollmentID: UUID,
        submission: LoudnessMatchSubmission
    ) async throws {}

    private var enrollment: StudyEnrollment {
        StudyEnrollment(
            id: enrollmentID,
            userID: userID,
            studyID: studyID,
            status: .enrolled,
            enrolledAt: Date(timeIntervalSince1970: 1_700_000_100),
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            onboardingCompletedAt: servesRecurringTask
                ? Date(timeIntervalSince1970: 1_700_000_200)
                : nil
        )
    }

    private var recurringLoudnessTask: ScheduledTask {
        let now = Date()
        return ScheduledTask(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            enrollmentID: enrollmentID,
            taskKey: "lm_1khz_v2",
            taskVersion: 2,
            scheduledFor: now,
            windowStart: now.addingTimeInterval(-300),
            windowEnd: now.addingTimeInterval(3_600),
            status: .scheduled,
            dayIndex: 0,
            slotIndex: 0,
            completedAt: nil
        )
    }

    private enum Scenario: String {
        case success
        case failOnce = "fail_once"
        case pendingRecovery = "pending_recovery"
    }
}
#endif

private struct ShimmerStudyCardView: View {
    @State private var shimmerOffset: CGFloat = -260

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(DashboardColors.cardBackground)
            .frame(height: 170)
            .overlay {
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 200, height: 18)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 240, height: 12)

                    Spacer()

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 100, height: 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(18)
            }
            .overlay {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.7), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geometry.size.width * 0.7)
                        .rotationEffect(.degrees(20))
                        .offset(x: shimmerOffset)
                }
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DashboardColors.cardStroke, lineWidth: 1)
            }
            .shadow(color: DashboardColors.cardShadow, radius: 4, x: 0, y: 2)
            .onAppear {
                shimmerOffset = -260
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    shimmerOffset = 320
                }
            }
    }
}

private enum DashboardColors {
    static let brandBlue = Color(red: 0.23, green: 0.43, blue: 0.73)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardStroke = Color(uiColor: .separator).opacity(0.35)
    static let cardDivider = Color(uiColor: .separator).opacity(0.22)
    static let cardShadow = Color.black.opacity(0.08)
}

private extension DashboardStudyCard {
    var displayBadgeText: String {
        badgeText
    }

    var badgeColor: Color {
        if isEnrolledActive {
            return DashboardColors.brandBlue
        }
        switch study.status {
        case .recruiting:
            return Color(uiColor: .systemGreen)
        case .recruitingPaused:
            return Color(uiColor: .systemOrange)
        case .closed:
            return Color(uiColor: .systemGray)
        case .unknown:
            return Color(uiColor: .systemGray2)
        }
    }
}
