//
//  HomeView.swift
//  TinniTrack
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var dashboardViewModel: HomeDashboardViewModel
    @State private var selectedTab: Tab = .dashboard
    private let consentService: ConsentServiceProtocol

    init(
        studyService: StudyServiceProtocol? = nil,
        consentService: ConsentServiceProtocol? = nil
    ) {
        _dashboardViewModel = StateObject(wrappedValue: HomeDashboardViewModel(studyService: studyService ?? SupabaseStudyService()))
        self.consentService = consentService ?? SupabaseConsentService()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardTabView(
                    firstName: displayFirstName,
                    profileTimezone: sessionStore.state.profile?.timezone,
                    viewModel: dashboardViewModel,
                    consentService: consentService
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

private struct DashboardTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    let firstName: String
    let profileTimezone: String?
    @ObservedObject var viewModel: HomeDashboardViewModel
    let consentService: ConsentServiceProtocol

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
                    NavigationLink {
                        destination(for: studyCard)
                    } label: {
                        StudyCardView(studyCard: studyCard)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("study_card_\(studyCard.study.slug)")
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for studyCard: DashboardStudyCard) -> some View {
        if studyCard.isEnrolledActive, let enrollment = studyCard.enrollment {
            StudyTaskDashboardView(
                study: studyCard.study,
                enrollment: enrollment,
                profileTimezone: profileTimezone
            )
        } else {
            StudyDetailView(
                studyCard: studyCard,
                consentService: consentService
            ) {
                await viewModel.refresh()
            }
        }
    }
}

private struct StudyCardView: View {
    let studyCard: DashboardStudyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
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

                Spacer(minLength: 12)

                Text(studyCard.badgeText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(studyCard.badgeColor)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                Text(studyCard.callToActionText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DashboardColors.brandBlue)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.brandBlue)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
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
    let consentService: ConsentServiceProtocol
    let onEnrollmentCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if canEnroll, let definition = StudyConsentCatalog.definition(for: studyCard.study.slug) {
                StudyConsentFlowView(
                    study: studyCard.study,
                    definition: definition,
                    consentService: consentService
                ) {
                    await onEnrollmentCompleted()
                }
            } else {
                EnrollmentUnavailableView(
                    title: unavailableTitle,
                    message: unavailableMessage
                )
            }
        }
        .interactivePopGestureEnabled()
        .onChange(of: studyCard.enrollment?.status) { _, status in
            guard status == .enrolled else { return }
            dismiss()
        }
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
    static let cardShadow = Color.black.opacity(0.08)
}

private extension DashboardStudyCard {
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
