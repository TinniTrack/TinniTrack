import SwiftUI

struct StudyOrientationThresholdStatusView: View {
    let state: StudyOrientationThresholdCoordinator.State
    let retryFinalization: () -> Void

    var body: some View {
        switch state {
        case .submitting:
            finishingContent(
                title: "Saving Your Hearing Threshold",
                message: "Your hearing check is complete. We’re securely saving the result before finishing orientation."
            )

        case .finalizing:
            finishingContent(
                title: "Finishing Orientation",
                message: "Your hearing threshold was saved. We’re setting up your study tasks now."
            )

        case .finalizationFailure(let message):
            finalizationFailureContent(message: message)

        case .idle,
             .preparing,
             .presentingResearchKit,
             .preflightFailure,
             .completed:
            EmptyView()
        }
    }

    private func finishingContent(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ProgressView()
                .controlSize(.large)
                .tint(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Finishing orientation")

            LoudnessMatchModalTitleBlock(
                title: title,
                bodyText: message
            )
        }
        .accessibilityIdentifier("study_onboarding_finishing_state")
    }

    private func finalizationFailureContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 76, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "We Couldn’t Finish Orientation",
                bodyText: "Your hearing threshold was saved, so you won’t need to repeat the test. \(message) Try again to finish setting up your study tasks."
            )

            LoudnessMatchModalPrimaryButton(
                title: "Try Again",
                action: retryFinalization
            )
            .accessibilityIdentifier("study_onboarding_finalization_retry_button")
        }
    }
}
