import SwiftUI
import UIKit

struct LoudnessMatchTaskFlowView: View {
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LoudnessMatchTaskFlowViewModel
    @State private var isSubmitConfirmationPresented = false
    @State private var isErrorAlertPresented = false

    init(
        scheduledTask: ScheduledTask,
        enrollment: StudyEnrollment,
        studyService: StudyServiceProtocol,
        routeMonitor: HeadphoneRouteMonitoring = HeadphoneRouteMonitor(),
        ambientNoiseMonitor: AmbientNoiseMonitoring = AmbientNoiseMonitor(),
        outputVolumeMonitor: OutputVolumeMonitoring = SystemOutputVolumeMonitor(),
        tonePlayer: TonePlaying = ToneGenerator.shared,
        routeGate: AudioRouteGating = StudyNo1RouteGate(),
        deviceMetadataProvider: DeviceMetadataProviding = SystemDeviceMetadataProvider(),
        resultBuilder: LoudnessMatchResultBuilding = StudyNo1LoudnessMatchResultBuilder(),
        onSubmitted: @escaping () -> Void
    ) {
        self.scheduledTask = scheduledTask
        self.enrollment = enrollment
        self.studyService = studyService
        self.onSubmitted = onSubmitted

        _viewModel = StateObject(
            wrappedValue: LoudnessMatchTaskFlowViewModel(
                scheduledTask: scheduledTask,
                enrollment: enrollment,
                studyService: studyService,
                routeMonitor: routeMonitor,
                ambientNoiseMonitor: ambientNoiseMonitor,
                outputVolumeMonitor: outputVolumeMonitor,
                tonePlayer: tonePlayer,
                routeGate: routeGate,
                deviceMetadataProvider: deviceMetadataProvider,
                resultBuilder: resultBuilder
            )
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            TaskWindowHeader(
                windowStart: scheduledTask.windowStart,
                windowEnd: scheduledTask.windowEnd
            )

            switch viewModel.step {
            case .headphoneGate:
                HeadphoneGateSection(viewModel: viewModel)
            case .ambientGate:
                AmbientGateSection(viewModel: viewModel, openSettings: openSettings)
            case .matching:
                MatchingSection(
                    viewModel: viewModel,
                    confirmSubmit: { isSubmitConfirmationPresented = true }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .navigationTitle("Loudness Match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .alert("Are you sure?", isPresented: $isSubmitConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Submit", role: .destructive) {
                Task { await submitMatch() }
            }
        } message: {
            Text("Submit this loudness match and mark the task complete?")
        }
        .alert("Unable to Submit", isPresented: $isErrorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private func submitMatch() async {
        let didSubmit = await viewModel.submitMatch()
        if didSubmit {
            onSubmitted()
            dismiss()
        } else {
            isErrorAlertPresented = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct TaskWindowHeader: View {
    let windowStart: Date
    let windowEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Window")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("\(Self.timeFormatter.string(from: windowStart)) - \(Self.timeFormatter.string(from: windowEnd))")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct HeadphoneGateSection: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 1: Connect AirPods Pro")
                .font(.title3)
                .fontWeight(.semibold)

            Text("We only allow loudness matching when AirPods Pro 2 or AirPods Pro 3 are connected.")
                .foregroundStyle(.secondary)

            LoudnessStatusPill(
                title: viewModel.isSupportedRoute ? "Connected" : "Not Connected",
                subtitle: viewModel.currentRoute?.name ?? "No audio output detected",
                isGood: viewModel.isSupportedRoute
            )

            if !viewModel.isSupportedRoute {
                Text("Connect your AirPods Pro 2 or AirPods Pro 3. We will continue automatically once detected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AmbientGateSection: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step 2: Quiet Room Check")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Ambient noise must stay at or below \(Int(StudyNo1Configuration.ambientThresholdDB)) dB.")
                .foregroundStyle(.secondary)

            switch viewModel.ambientPermissionStatus {
            case .notDetermined:
                Button("Enable Microphone") {
                    Task { await viewModel.requestAmbientPermission() }
                }
                .buttonStyle(.borderedProminent)

            case .denied:
                Text("Microphone access is required for ambient-noise validation.")
                    .foregroundStyle(.secondary)

                Button("Open Settings", action: openSettings)
                    .buttonStyle(.bordered)

            case .granted:
                LoudnessStatusPill(
                    title: viewModel.isAmbientQuiet ? "Quiet Enough" : "Too Loud",
                    subtitle: viewModel.ambientDisplayText,
                    isGood: viewModel.isAmbientQuiet
                )

                Text(viewModel.isAmbientQuiet
                     ? "Environment check passed."
                     : "Move to a quieter location and wait for the reading to drop.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Start Loudness Match") {
                    viewModel.startMatching()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isAmbientQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MatchingSection: View {
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    let confirmSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Step 3: Match Ringing")
                .font(.title3)
                .fontWeight(.semibold)

            LoudnessStatusPill(
                title: viewModel.isSupportedRoute ? "Headphones Connected" : "Headphones Disconnected",
                subtitle: viewModel.currentRoute?.name ?? "No supported route detected",
                isGood: viewModel.isSupportedRoute
            )

            LoudnessStatusPill(
                title: viewModel.isAmbientQuiet ? "Quiet Enough" : "Environment Too Loud",
                subtitle: viewModel.ambientDisplayText,
                isGood: viewModel.isAmbientQuiet
            )

            LoudnessStatusPill(
                title: viewModel.hasOutputVolumeChanged ? "Device Volume Changed" : "Device Volume Stable",
                subtitle: viewModel.outputVolumeDisplayText,
                isGood: !viewModel.hasOutputVolumeChanged
            )

            if let matchingPauseMessage = viewModel.matchingPauseMessage {
                Text(matchingPauseMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            CircularDial(
                value: Binding(
                    get: { viewModel.loudnessLevel },
                    set: { viewModel.updateLoudness($0) }
                ),
                isEnabled: viewModel.canAdjustLoudness
            )
            .frame(height: 280)

            Button(action: confirmSubmit) {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Match Ringing")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(viewModel.canSubmit ? Color.blue : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(!viewModel.canSubmit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LoudnessStatusPill: View {
    let title: String
    let subtitle: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.footnote)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isGood ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
