//
//  ProfileDeveloperToolsSection.swift
//  TinniTrack
//

import SwiftUI

#if DEBUG
struct ProfileDeveloperToolsSection: View {
    @ObservedObject var viewModel: DeveloperToolsViewModel
    let environment: SupabaseEnvironmentDescriptor
    private let refreshSession: DeveloperToolRefreshAction

    init(
        viewModel: DeveloperToolsViewModel,
        environment: SupabaseEnvironmentDescriptor,
        refreshSession: @escaping @MainActor () async -> Void
    ) {
        self.viewModel = viewModel
        self.environment = environment
        self.refreshSession = DeveloperToolRefreshAction(refreshSession)
    }

    var body: some View {
        Section {
            LabeledContent("Environment", value: environment.name)
            LabeledContent("Supabase Host", value: environment.hostDescription)

            DeveloperActionButton(
                action: .resetProfileOnboarding,
                viewModel: viewModel,
                systemImage: "arrow.counterclockwise",
                role: .destructive,
                refresh: refreshSession
            )

            DeveloperActionButton(
                action: .resetStudyNo1Orientation,
                viewModel: viewModel,
                systemImage: "list.bullet.rectangle",
                role: .destructive,
                refresh: refreshSession
            )

            DeveloperActionButton(
                action: .unenrollFromStudyNo1AndDeleteData,
                viewModel: viewModel,
                systemImage: "trash",
                role: .destructive,
                refresh: refreshSession
            )

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("developer_tools_status")
            }
        } header: {
            Text("Developer Tools")
        } footer: {
            Text("DEBUG build only. RPCs require the signed-in account to be allow-listed in the connected Supabase project.")
        }
        .alert("Developer Action Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct StudyTaskDeveloperToolsSection: View {
    @ObservedObject var viewModel: DeveloperToolsViewModel
    private let refreshTasks: DeveloperToolRefreshAction

    init(
        viewModel: DeveloperToolsViewModel,
        refreshTasks: @escaping @MainActor () async -> Void
    ) {
        self.viewModel = viewModel
        self.refreshTasks = DeveloperToolRefreshAction(refreshTasks)
    }

    var body: some View {
        Section {
            DeveloperActionButton(
                action: .makeNextLoudnessMatchAvailableNow,
                viewModel: viewModel,
                systemImage: "clock.badge.checkmark",
                refresh: refreshTasks
            )

            DeveloperActionButton(
                action: .reopenLastCompletedLoudnessMatch,
                viewModel: viewModel,
                systemImage: "arrow.uturn.backward.circle",
                refresh: refreshTasks
            )

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("developer_task_tools_status")
            }
        } header: {
            Text("Developer Tools")
        } footer: {
            Text("DEBUG build only. These actions affect only the current signed-in developer account.")
        }
        .alert("Developer Action Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct DeveloperActionButton: View {
    let action: DeveloperToolsViewModel.Action
    @ObservedObject var viewModel: DeveloperToolsViewModel
    let systemImage: String
    var role: ButtonRole?
    let refresh: DeveloperToolRefreshAction

    var body: some View {
        Button(role: role) {
            Task { @MainActor in
                await viewModel.perform(action) {
                    await refresh()
                }
            }
        } label: {
            HStack {
                if viewModel.activeAction == action {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                }

                Text(action.title)
            }
        }
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var accessibilityIdentifier: String {
        switch action {
        case .resetProfileOnboarding:
            return "developer_reset_profile_onboarding_button"
        case .resetStudyNo1Orientation:
            return "developer_reset_study_no_1_orientation_button"
        case .unenrollFromStudyNo1AndDeleteData:
            return "developer_unenroll_study_no_1_button"
        case .makeNextLoudnessMatchAvailableNow:
            return "developer_make_next_loudness_match_available_button"
        case .reopenLastCompletedLoudnessMatch:
            return "developer_reopen_last_loudness_match_button"
        }
    }
}

private struct DeveloperToolRefreshAction: @unchecked Sendable {
    private let operation: @MainActor () async -> Void

    init(_ operation: @escaping @MainActor () async -> Void) {
        self.operation = operation
    }

    @MainActor
    func callAsFunction() async {
        await operation()
    }
}
#endif
