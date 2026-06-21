import SwiftUI

struct StudyTaskOrientationSheet: View {
    @Binding var step: StudyTaskOrientationStep
    @ObservedObject var viewModel: StudyTaskDashboardViewModel

    let openHealthApp: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .hearingTest:
                        hearingTestStep
                    case .importAudiogram:
                        importStep
                    case .nextSteps:
                        nextSteps
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Study Orientation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .hearingTest {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: moveToPreviousStep) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }
                        .accessibilityLabel("Back")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: close)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var hearingTestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepLabel(text: "Step 1")
            hearingTestInstructions

            StudyActionButton(title: "Continue", isPrimary: true) {
                step = .importAudiogram
            }
        }
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepLabel(text: "Step 2")
            importStateContent

            StudyActionButton(title: "Continue", isPrimary: true) {
                step = .nextSteps
            }
            .disabled(!viewModel.isAudiogramPrerequisiteMet)
            .opacity(viewModel.isAudiogramPrerequisiteMet ? 1 : 0.5)
        }
        .task {
            await viewModel.checkOrientationImportStatus()
        }
    }

    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepLabel(text: "Step 3")

            StudyPrerequisiteCard(
                title: "Finish Orientation",
                message: "Once you finish, we will generate your full Study No. 1 task schedule."
            )

            StudyActionButton(
                title: viewModel.isCompletingStudyOnboarding ? "Finishing..." : "Finish Orientation",
                isPrimary: true,
                isLoading: viewModel.isCompletingStudyOnboarding
            ) {
                Task {
                    await viewModel.completeStudyOnboarding()
                    if !viewModel.requiresStudyOnboardingCompletion {
                        close()
                    }
                }
            }
            .disabled(!viewModel.isAudiogramPrerequisiteMet || viewModel.isCompletingStudyOnboarding)
            .opacity((viewModel.isAudiogramPrerequisiteMet && !viewModel.isCompletingStudyOnboarding) ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var importStateContent: some View {
        switch viewModel.orientationImportState {
        case .waitingForPermission:
            StudyPrerequisiteCard(
                title: "Connect Apple Health",
                message: "Allow Apple Health access so we can import your hearing test into the study."
            )

            StudyActionButton(
                title: viewModel.isSyncing ? "Connecting..." : "Connect Apple Health",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }

        case .requestingOrChecking:
            ProgressView("Checking hearing test import...")
                .frame(maxWidth: .infinity, alignment: .leading)

        case .success(let hearingTestDate):
            StudyPrerequisiteCard(
                title: "Hearing Test Imported",
                message: successMessageForHearingTestDate(hearingTestDate)
            )

        case .authorizedNoHearingTest:
            StudyPrerequisiteCard(
                title: "No Hearing Test Found Yet",
                message: "We can access your health data, but we are not seeing a hearing test yet."
            )

            hearingTestInstructions

            StudyActionButton(
                title: viewModel.isSyncing ? "Checking..." : "Check Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }

        case .permissionDenied:
            StudyPrerequisiteCard(
                title: "Permission Required",
                message: "Approve hearing-test access in Apple Health, then return here and check again."
            )

            StudyActionButton(title: "Open Health App", isPrimary: false, action: openHealthApp)

            StudyActionButton(
                title: viewModel.isSyncing ? "Checking..." : "Check Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.checkOrientationImportStatus() }
            }

        case .error(let message):
            StudyPrerequisiteCard(
                title: "Import Unavailable",
                message: message
            )

            StudyActionButton(
                title: viewModel.isSyncing ? "Retrying..." : "Try Again",
                isPrimary: true,
                isLoading: viewModel.isSyncing
            ) {
                Task { await viewModel.connectAppleHealthForOrientation() }
            }
        }
    }

    private var hearingTestInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyPrerequisiteCard(
                title: "Take an Apple Hearing Test",
                message: "Use AirPods Pro (2nd generation) with your paired iPhone. In Settings > your AirPods, tap Take a Hearing Test. Then come back and continue orientation."
            )

            Link(
                "Need help taking an Apple Hearing Test?",
                destination: URL(string: "https://support.apple.com/en-us/120991")!
            )
            .font(.subheadline)
            .fontWeight(.semibold)
        }
    }

    private func moveToPreviousStep() {
        switch step {
        case .hearingTest:
            break
        case .importAudiogram:
            step = .hearingTest
        case .nextSteps:
            step = .importAudiogram
        }
    }

    private func successMessageForHearingTestDate(_ date: Date?) -> String {
        guard let date else {
            return "Success! We got your hearing test."
        }
        return "Success! We got your hearing test from \(Self.hearingTestDateFormatter.string(from: date))."
    }

    private static let hearingTestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct StepLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
