//
//  DeveloperToolsViewModel.swift
//  TinniTrack
//

import Foundation
import Combine

#if DEBUG
@MainActor
final class DeveloperToolsViewModel: ObservableObject {
    enum Action: Equatable {
        case resetProfileOnboarding
        case resetStudyNo1Orientation
        case makeNextLoudnessMatchAvailableNow
        case reopenLastCompletedLoudnessMatch

        var title: String {
            switch self {
            case .resetProfileOnboarding:
                return "Reset App Onboarding"
            case .resetStudyNo1Orientation:
                return "Reset Study No. 1 Orientation"
            case .makeNextLoudnessMatchAvailableNow:
                return "Make Next Loudness Match Available"
            case .reopenLastCompletedLoudnessMatch:
                return "Reopen Last Loudness Match"
            }
        }

        var successMessage: String {
            switch self {
            case .resetProfileOnboarding:
                return "App onboarding reset."
            case .resetStudyNo1Orientation:
                return "Study No. 1 orientation reset."
            case .makeNextLoudnessMatchAvailableNow:
                return "Next loudness-match task is available now."
            case .reopenLastCompletedLoudnessMatch:
                return "Last completed loudness-match task reopened."
            }
        }
    }

    @Published private(set) var activeAction: Action?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let service: DeveloperToolingServiceProtocol

    init(service: DeveloperToolingServiceProtocol) {
        self.service = service
    }

    var isBusy: Bool {
        activeAction != nil
    }

    func perform(_ action: Action, refresh: @escaping @MainActor () async -> Void) async {
        guard activeAction == nil else { return }

        activeAction = action
        statusMessage = nil
        errorMessage = nil
        defer { activeAction = nil }

        do {
            switch action {
            case .resetProfileOnboarding:
                try await service.resetProfileOnboarding()
            case .resetStudyNo1Orientation:
                try await service.resetStudyNo1Orientation()
            case .makeNextLoudnessMatchAvailableNow:
                try await service.makeNextLoudnessMatchAvailableNow()
            case .reopenLastCompletedLoudnessMatch:
                try await service.reopenLastCompletedLoudnessMatch()
            }

            await refresh()
            statusMessage = action.successMessage
        } catch {
            errorMessage = Self.userFacingErrorMessage(for: error)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Developer action failed." : message
    }
}
#endif
