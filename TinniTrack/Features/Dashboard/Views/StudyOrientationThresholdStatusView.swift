import SwiftUI

struct StudyOrientationThresholdStatusView: View {
    let state: StudyOrientationThresholdCoordinator.State
    let retrySubmission: () -> Void
    let retryFinalization: () -> Void

    var body: some View {
        switch state {
        case .submitting:
            finishingContent(
                title: "Saving Your Hearing Threshold",
                message: "Your hearing check is complete. We’re securely saving the result before finishing orientation."
            )

        case .submissionFailure(let message):
            failureContent(
                title: "We Couldn’t Save Your Hearing Check",
                message: "Your completed hearing check is still here. \(message) Try saving it again—you won’t need to repeat either ear.",
                buttonTitle: "Try Saving Again",
                accessibilityIdentifier: "study_onboarding_submission_retry_button",
                action: retrySubmission
            )

        case .finalizing:
            finishingContent(
                title: "Finishing Orientation",
                message: "Your hearing threshold was saved. We’re setting up your study tasks now."
            )

        case .finalizationFailure(let message):
            failureContent(
                title: "We Couldn’t Finish Orientation",
                message: "Your hearing threshold was saved, so you won’t need to repeat the test. \(message) Try again to finish setting up your study tasks.",
                buttonTitle: "Try Again",
                accessibilityIdentifier: "study_onboarding_finalization_retry_button",
                action: retryFinalization
            )

        case .idle,
             .preparing,
             .readyForTest,
             .preflightFailure,
             .completed:
            EmptyView()
        }
    }

    private func finishingContent(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ProgressView()
                .controlSize(.large)
                .tint(StudyTestColors.accent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Finishing orientation")

            StudyTestTitleBlock(
                title: title,
                bodyText: message
            )
        }
        .accessibilityIdentifier("study_onboarding_finishing_state")
    }

    private func failureContent(
        title: String,
        message: String,
        buttonTitle: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 76, weight: .regular))
                .foregroundStyle(StudyTestColors.accent)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            StudyTestTitleBlock(
                title: title,
                bodyText: message
            )

            StudyTestPrimaryButton(
                title: buttonTitle,
                accessibilityIdentifier: accessibilityIdentifier,
                action: action
            )
        }
    }
}
