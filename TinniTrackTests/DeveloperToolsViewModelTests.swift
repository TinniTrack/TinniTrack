import Foundation
import Testing
@testable import TinniTrack

#if DEBUG
@MainActor
struct DeveloperToolsViewModelTests {
    @Test
    func resetProfileOnboardingCallsServiceAndRefreshes() async {
        let service = MockDeveloperToolingService()
        let refresh = RefreshRecorder()
        let viewModel = DeveloperToolsViewModel(service: service)

        await viewModel.perform(.resetProfileOnboarding) {
            refresh.record()
        }

        #expect(service.calls == [.resetProfileOnboarding])
        #expect(refresh.callCount == 1)
        #expect(viewModel.statusMessage == "App onboarding reset.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func resetStudyNo1OrientationCallsServiceAndRefreshes() async {
        let service = MockDeveloperToolingService()
        let refresh = RefreshRecorder()
        let viewModel = DeveloperToolsViewModel(service: service)

        await viewModel.perform(.resetStudyNo1Orientation) {
            refresh.record()
        }

        #expect(service.calls == [.resetStudyNo1Orientation])
        #expect(refresh.callCount == 1)
        #expect(viewModel.statusMessage == "Study No. 1 orientation reset.")
    }

    @Test
    func makeNextLoudnessMatchAvailableCallsServiceAndRefreshes() async {
        let service = MockDeveloperToolingService()
        let refresh = RefreshRecorder()
        let viewModel = DeveloperToolsViewModel(service: service)

        await viewModel.perform(.makeNextLoudnessMatchAvailableNow) {
            refresh.record()
        }

        #expect(service.calls == [.makeNextLoudnessMatchAvailableNow])
        #expect(refresh.callCount == 1)
        #expect(viewModel.statusMessage == "Next loudness-match task is available now.")
    }

    @Test
    func reopenLastCompletedLoudnessMatchCallsServiceAndRefreshes() async {
        let service = MockDeveloperToolingService()
        let refresh = RefreshRecorder()
        let viewModel = DeveloperToolsViewModel(service: service)

        await viewModel.perform(.reopenLastCompletedLoudnessMatch) {
            refresh.record()
        }

        #expect(service.calls == [.reopenLastCompletedLoudnessMatch])
        #expect(refresh.callCount == 1)
        #expect(viewModel.statusMessage == "Last completed loudness-match task reopened.")
    }

    @Test
    func failedDeveloperActionShowsErrorAndDoesNotRefresh() async {
        let service = MockDeveloperToolingService()
        service.error = DeveloperToolingTestError.denied
        let refresh = RefreshRecorder()
        let viewModel = DeveloperToolsViewModel(service: service)

        await viewModel.perform(.makeNextLoudnessMatchAvailableNow) {
            refresh.record()
        }

        #expect(service.calls == [.makeNextLoudnessMatchAvailableNow])
        #expect(refresh.callCount == 0)
        #expect(viewModel.statusMessage == nil)
        #expect(viewModel.errorMessage == "Developer tooling is not enabled for this account.")
    }
}

@MainActor
private final class MockDeveloperToolingService: DeveloperToolingServiceProtocol {
    enum Call: Equatable {
        case resetProfileOnboarding
        case resetStudyNo1Orientation
        case makeNextLoudnessMatchAvailableNow
        case reopenLastCompletedLoudnessMatch
    }

    private(set) var calls: [Call] = []
    var error: Error?

    func resetProfileOnboarding() async throws {
        calls.append(.resetProfileOnboarding)
        try throwIfNeeded()
    }

    func resetStudyNo1Orientation() async throws {
        calls.append(.resetStudyNo1Orientation)
        try throwIfNeeded()
    }

    func makeNextLoudnessMatchAvailableNow() async throws {
        calls.append(.makeNextLoudnessMatchAvailableNow)
        try throwIfNeeded()
    }

    func reopenLastCompletedLoudnessMatch() async throws {
        calls.append(.reopenLastCompletedLoudnessMatch)
        try throwIfNeeded()
    }

    private func throwIfNeeded() throws {
        if let error {
            throw error
        }
    }
}

@MainActor
private final class RefreshRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

private enum DeveloperToolingTestError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Developer tooling is not enabled for this account."
    }
}
#endif
