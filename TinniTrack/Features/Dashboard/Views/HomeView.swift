//
//  HomeView.swift
//  TinniTrack
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var dashboardViewModel: HomeDashboardViewModel
    @State private var selectedTab: Tab = .dashboard

    init(studyService: StudyServiceProtocol? = nil) {
        _dashboardViewModel = StateObject(wrappedValue: HomeDashboardViewModel(studyService: studyService ?? SupabaseStudyService()))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardTabView(
                    firstName: displayFirstName,
                    profileTimezone: sessionStore.state.profile?.timezone,
                    viewModel: dashboardViewModel
                )
            }
            .tabItem {
                Label("Dashboard", systemImage: "list.bullet.clipboard")
            }
            .tag(Tab.dashboard)

            NavigationStack {
                ProfileTabView()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Text("CURRENT STUDIES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

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
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.refreshForLifecycleEvent()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hello, \(firstName)")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(.primary)
            Text("Welcome to TinniTrack.")
                .font(.body)
                .foregroundStyle(.secondary)
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
            StudyDetailView(studyCard: studyCard) {
                try await viewModel.enroll(studyID: studyCard.study.id)
            }
        }
    }
}

private struct StudyCardView: View {
    let studyCard: DashboardStudyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(studyCard.study.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

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

            Text(studyCard.study.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct StudyDetailView: View {
    let studyCard: DashboardStudyCard
    let onEnroll: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEnrolling = false
    @State private var enrollmentErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailCard(title: "Description", body: studyCard.study.description)
                criteriaCard(title: "Inclusion Criteria", items: Self.inclusionCriteria)
                criteriaCard(title: "Exclusion Criteria", items: Self.exclusionCriteria)

                Button {
                    Task { await handleEnrollTapped() }
                } label: {
                    HStack {
                        if isEnrolling {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(canEnroll ? "Begin eConsent & Enroll" : "Enrollment Unavailable")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(canEnroll ? DashboardColors.brandBlue : Color(uiColor: .systemGray3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(!canEnroll || isEnrolling)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(studyCard.study.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unable to Enroll", isPresented: Binding(
            get: { enrollmentErrorMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    enrollmentErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                enrollmentErrorMessage = nil
            }
        } message: {
            Text(enrollmentErrorMessage ?? "")
        }
    }

    private var canEnroll: Bool {
        if case .recruiting = studyCard.study.status {
            return true
        }
        return false
    }

    private func detailCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private func criteriaCard(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    @MainActor
    private func handleEnrollTapped() async {
        guard canEnroll else { return }
        isEnrolling = true
        defer { isEnrolling = false }

        do {
            try await onEnroll()
            dismiss()
        } catch {
            enrollmentErrorMessage = error.localizedDescription
        }
    }

    private static let inclusionCriteria = [
        "Adults (18+) with self-reported tinnitus.",
        "Access to an iPhone and AirPods Pro (2nd generation).",
        "Able to complete scheduled loudness-matching tasks."
    ]

    private static let exclusionCriteria = [
        "Unable to provide informed consent.",
        "No compatible headphones for calibration workflows.",
        "Medical conditions that make headphone listening unsafe."
    ]
}

private struct ProfileTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("First Name", value: sessionStore.state.profile?.firstName ?? "Not set")
                LabeledContent("Last Name", value: sessionStore.state.profile?.lastName ?? "Not set")
            }

            Section("Research") {
                LabeledContent("Participant ID", value: participantIDText)
            }

            Section {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Text("Log Out")
                    }
                }
                .disabled(isSigningOut)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var participantIDText: String {
        guard let participantID = sessionStore.state.profile?.participantID else { return "Unavailable" }
        return String(participantID)
    }

    @MainActor
    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        await sessionStore.signOut()
    }
}

private struct ShimmerStudyCardView: View {
    @State private var shimmerOffset: CGFloat = -260

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
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
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
