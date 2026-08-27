import SwiftUI

struct StudyOrientationHearingTestView: View {
    @Environment(\.openURL) private var openURL

    @ObservedObject var viewModel: StudyTaskDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "airpodspro")
                .font(.system(size: 86, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Take an Apple Hearing Test",
                bodyText: "Use AirPods Pro 2 with your paired iPhone. In Settings, open your AirPods and tap Take a Hearing Test. When you return, connect Apple Health so TinniTrack can import the result."
            )

            importStateContent

            Link(
                "Need help taking an Apple Hearing Test?",
                destination: URL(string: "https://support.apple.com/en-us/120991")!
            )
            .font(.callout)
            .fontWeight(.semibold)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.checkOrientationImportStatus()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study_onboarding_hearing_test_step")
    }

    @ViewBuilder
    private var importStateContent: some View {
        switch viewModel.orientationImportState {
        case .waitingForPermission:
            StudyOrientationImportStatusCard(
                systemName: "heart.text.square",
                title: "Apple Health access needed",
                message: "Allow audiogram read access to import your Apple hearing test."
            )

            StudyOrientationImportActionButton(
                title: viewModel.isSyncing ? "Connecting" : "Connect Apple Health",
                isLoading: viewModel.isSyncing,
                action: connectAppleHealth
            )

        case .requestingOrChecking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking hearing-test import...")
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            }

        case .success(let hearingTestDate):
            StudyOrientationImportStatusCard(
                systemName: "checkmark.circle.fill",
                title: "Hearing test imported",
                message: successMessageForHearingTestDate(hearingTestDate),
                tint: LoudnessMatchModalColors.success
            )

        case .authorizedNoHearingTest:
            StudyOrientationImportStatusCard(
                systemName: "exclamationmark.circle",
                title: "No hearing test found yet",
                message: "Apple Health is connected, but no audiogram is available yet. Complete the Apple Hearing Test and check again."
            )

            StudyOrientationImportActionButton(
                title: viewModel.isSyncing ? "Checking" : "Check Again",
                isLoading: viewModel.isSyncing,
                action: connectAppleHealth
            )

        case .permissionDenied:
            StudyOrientationImportStatusCard(
                systemName: "lock.circle",
                title: "Permission required",
                message: "Approve hearing-test access in Apple Health, then return here and check again."
            )

            HStack(spacing: 12) {
                StudyOrientationImportActionButton(
                    title: "Open Health",
                    isLoading: false,
                    action: openHealthApp
                )
                StudyOrientationImportActionButton(
                    title: viewModel.isSyncing ? "Checking" : "Check Again",
                    isLoading: viewModel.isSyncing,
                    action: checkImportStatus
                )
            }

        case .error(let message):
            StudyOrientationImportStatusCard(
                systemName: "exclamationmark.triangle",
                title: "Import unavailable",
                message: message
            )

            StudyOrientationImportActionButton(
                title: viewModel.isSyncing ? "Retrying" : "Try Again",
                isLoading: viewModel.isSyncing,
                action: connectAppleHealth
            )
        }
    }

    private func connectAppleHealth() {
        Task {
            await viewModel.connectAppleHealthForOrientation()
        }
    }

    private func checkImportStatus() {
        Task {
            await viewModel.checkOrientationImportStatus()
        }
    }

    private func openHealthApp() {
        guard let healthAppURL = URL(string: "x-apple-health://") else {
            return
        }

        openURL(healthAppURL)
    }

    private func successMessageForHearingTestDate(_ date: Date?) -> String {
        guard let date else {
            return "Success. We imported your hearing test."
        }
        return "Success. We imported your hearing test from \(Self.hearingTestDateFormatter.string(from: date))."
    }

    private static let hearingTestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct StudyOrientationImportStatusCard: View {
    let systemName: String
    let title: String
    let message: String
    var tint: Color = LoudnessMatchModalColors.secondaryText

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(LoudnessMatchModalColors.text)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(16)
        .background(LoudnessMatchModalColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }
}

private struct StudyOrientationImportActionButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(isLoading ? LoudnessMatchModalColors.disabledText : LoudnessMatchModalColors.text)
            .background(LoudnessMatchModalColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(AppRoundedButtonStyle(cornerRadius: 8))
        .disabled(isLoading)
    }
}
