import SwiftUI

struct StudyOrientationThresholdTestView: View {
    @ObservedObject var session: StudyOrientationThresholdTestSession

    let requestClose: () -> Void
    let complete: (StudyNo1OrientationThresholdResult) -> Void

    var body: some View {
        StudyTestPage(
            navigationTitle: "Orientation",
            closeAction: StudyTestCloseAction(
                accessibilityIdentifier: "study_onboarding_close_button",
                action: requestClose
            ),
            primaryAction: primaryAction
        ) {
            stageContent
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("study_onboarding_threshold_test_step")
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch session.stage {
        case .instructions(let ear):
            ThresholdEarInstructions(
                ear: ear,
                progress: session.progress
            )

        case .testing:
            ThresholdEarTest(
                isPaused: session.isPaused,
                heardTone: session.heardTone
            )

        case .failed(let ear, let message):
            ThresholdEarFailure(ear: ear, message: message)

        case .completed:
            ThresholdTestCompletion(result: session.result)
        }
    }

    private var primaryAction: StudyTestPageAction? {
        switch session.stage {
        case .instructions(let ear):
            return StudyTestPageAction(
                title: "Begin \(ear.displayName) Ear",
                accessibilityHint: "Starts the calibrated hearing threshold check for your \(ear.rawValue) ear.",
                accessibilityIdentifier: "study_threshold_begin_\(ear.rawValue)_ear_button",
                action: session.startCurrentEar
            )

        case .testing:
            return nil

        case .failed(let ear, _):
            return StudyTestPageAction(
                title: "Try \(ear.displayName) Ear Again",
                accessibilityIdentifier: "study_threshold_retry_ear_button",
                action: session.retryCurrentEar
            )

        case .completed:
            return StudyTestPageAction(
                title: "Finish Hearing Check",
                accessibilityIdentifier: "study_threshold_finish_button",
                action: finish
            )
        }
    }

    private func finish() {
        guard let result = session.result else {
            return
        }
        complete(result)
    }
}

private struct ThresholdEarInstructions: View {
    let ear: StudyOrientationThresholdTestSession.Ear
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StudyTestProgress(
                progress: progress,
                title: "Hearing check",
                valueText: "Ear \(ear == .right ? 1 : 2) of 2",
                accessibilityValue: "Preparing \(ear.rawValue) ear, ear \(ear == .right ? 1 : 2) of 2"
            )

            ZStack {
                Circle()
                    .fill(StudyTestColors.accentSurface)
                    .frame(width: 132, height: 132)

                Image(systemName: ear == .right ? "ear.fill" : "ear")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(StudyTestColors.accent)
                    .scaleEffect(x: ear == .right ? -1 : 1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            StudyTestTitleBlock(
                title: "Listen with your \(ear.rawValue) ear",
                bodyText: "You’ll hear a series of tones through one AirPod. Tap as soon as you hear a tone."
            )
        }
    }
}

private struct ThresholdEarTest: View {
    let isPaused: Bool
    let heardTone: () -> Void

    @State private var feedbackTrigger = 0

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Text(isPaused ? "Test paused" : "Listen carefully")
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(StudyTestColors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if isPaused {
                    Text("The test will resume when your audio setup is ready.")
                        .font(.title2)
                        .foregroundStyle(StudyTestColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap the button whenever you hear a tone")
                        .font(.title2)
                        .foregroundStyle(StudyTestColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Don’t tap during silence")
                        .font(.title2)
                        .foregroundStyle(StudyTestColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StudyTestToneButton(
                title: "I Hear the Tone",
                systemImage: "hand.tap.fill",
                isActive: true,
                isEnabled: !isPaused,
                feedbackTrigger: feedbackTrigger,
                size: .large,
                accessibilityLabel: "I hear the tone",
                accessibilityHint: "Records that you can hear the current tone.",
                accessibilityIdentifier: "study_threshold_heard_button",
                action: recordHeardTone
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func recordHeardTone() {
        feedbackTrigger &+= 1
        heardTone()
    }
}

private struct ThresholdEarFailure: View {
    let ear: StudyOrientationThresholdTestSession.Ear
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 76, weight: .regular))
                .foregroundStyle(StudyTestColors.accent)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            StudyTestTitleBlock(
                title: "Let’s Try the \(ear.displayName) Ear Again",
                bodyText: message
            )

            ThresholdGuidanceCard(
                systemName: "checklist",
                title: "Before retrying",
                message: "Keep both AirPods in place, leave the volume at maximum, and wait for a genuinely quiet moment."
            )
        }
    }
}

private struct ThresholdTestCompletion: View {
    let result: StudyNo1OrientationThresholdResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 82, weight: .regular))
                .foregroundStyle(StudyTestColors.success)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            StudyTestTitleBlock(
                title: "Hearing Check Complete",
                bodyText: "Both ears are complete. TinniTrack will securely save this baseline and finish setting up your study tasks."
            )

            VStack(spacing: 12) {
                completionRow(
                    title: "Right ear",
                    isComplete: result?.rightEar?.thresholdDBHL != nil
                )
                completionRow(
                    title: "Left ear",
                    isComplete: result?.leftEar?.thresholdDBHL != nil
                )
            }
        }
    }

    private func completionRow(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    isComplete
                        ? StudyTestColors.success
                        : StudyTestColors.tertiaryText
                )

            Text(title)
                .font(.headline)
                .foregroundStyle(StudyTestColors.text)

            Spacer()

            Text(isComplete ? "Complete" : "Pending")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudyTestColors.secondaryText)
        }
        .padding(16)
        .background(StudyTestColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ThresholdGuidanceCard: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(StudyTestColors.accent)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(StudyTestColors.text)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(StudyTestColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(StudyTestColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudyTestColors.separator.opacity(0.30), lineWidth: 1)
        }
    }
}

#Preview("Threshold instructions") {
    NavigationStack {
        StudyOrientationThresholdTestView(
            session: StudyOrientationThresholdTestSession(
                playTone: { _, _ in },
                stopTone: {},
                outputVolume: { 1.0 }
            ),
            requestClose: {},
            complete: { _ in }
        )
    }
}
