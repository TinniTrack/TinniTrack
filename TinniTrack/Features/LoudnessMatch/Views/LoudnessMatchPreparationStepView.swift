import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LoudnessMatchPreparationStepView: View {
    let step: LoudnessMatchModalStep
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    var selectedLaterality: TinnitusLaterality?
    var maxVolumeActionTitle = "Continue"
    let showNoiseSuggestions: () -> Void
    var selectLaterality: (TinnitusLaterality) -> Void = { _ in }

    var body: some View {
        switch step {
        case .intro:
            IntroStepView()
                .accessibilityIdentifier("loudness_intro_step")
        case .quietRoom:
            LoudnessMatchNoiseGateView(
                update: viewModel.environmentGateUpdate,
                showSuggestions: showNoiseSuggestions
            )
        case .correctEar:
            AirPodsCorrectEarStepView(
                assessment: viewModel.headphoneRouteAssessment,
                isAirPodsPro2Confirmed: viewModel.isCurrentAirPodsPro2PlaybackRouteConfirmed,
                isConfirmedAirPodsUsingCallAudio: viewModel.isAirPodsPlaybackRouteBlockedByAnotherApp,
                refreshRoute: viewModel.refreshHeadphoneRouteAssessment
            )
        case .fit:
            AirPodsFitStepView()
        case .maxVolume:
            MaxVolumeGateStepView(
                validation: viewModel.currentGuardrailValidation,
                primaryActionTitle: maxVolumeActionTitle
            )
                .accessibilityIdentifier("loudness_volume_gate_step")
        case .tinnitusLocation:
            TinnitusLocationStepView(
                selectedLaterality: selectedLaterality,
                isSelectionCommitted: viewModel.selectedLaterality != nil,
                isResolvingSelection: viewModel.isResolvingAudiogramThreshold,
                selectLaterality: selectLaterality
            )
            .accessibilityIdentifier("loudness_tinnitus_location_step")
        }
    }
}

private struct IntroStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 92, weight: .medium))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Test Your Tinnitus",
                bodyText: "This quick test will help us measure the intensity of your tinnitus."
            )

            Spacer(minLength: 0)

            Text("Note: If You've experienced a sudden change in your hearing, you should talk to a doctor.")
                .font(.callout)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct AirPodsCorrectEarStepView: View {
    let assessment: HeadphoneRouteAssessment
    let isAirPodsPro2Confirmed: Bool
    let isConfirmedAirPodsUsingCallAudio: Bool
    let refreshRoute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 52) {
                airPodGlyph(systemName: "airpodpro.left", label: "L")
                airPodGlyph(systemName: "airpodpro.right", label: "R")
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Place your AirPods in the correct ear",
                bodyText: "Put the right AirPod in your right ear and the left AirPod in your left ear. Remove any hearing aids before continuing.",
                titleLineLimit: nil,
                bodyLineLimit: nil
            )

            connectionCard

            Spacer(minLength: 0)

            #if DEBUG
            diagnosticsDisclosure
            #endif
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("loudness_airpods_step")
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                connectionIndicator

                VStack(alignment: .leading, spacing: 5) {
                    Text(connectionTitle)
                        .font(.headline)
                        .foregroundStyle(connectionColor)

                    Text(connectionDetail)
                        .font(.callout)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("loudness_airpods_status_label")

            if assessment.isCompatibleBluetoothPlaybackRoute,
               let portName = assessment.portName {
                Label(portName, systemImage: "wave.3.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LoudnessMatchModalColors.text)
                    .textSelection(.enabled)
            }

            if !assessment.isAirPodsProPlaybackRouteCandidate {
                Text("Make sure your AirPods are not connected to another device. If your iPhone does not detect them, take them out and put them back in.")
                    .font(.callout)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: refreshRoute) {
                Label("Check Again", systemImage: "arrow.clockwise")
                    .font(.callout)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LoudnessMatchModalColors.primary)
            .accessibilityHint("Refreshes the connected audio route after returning from Settings.")
            .accessibilityIdentifier("loudness_airpods_check_again")
        }
        .padding(14)
        .background(LoudnessMatchModalColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        if isAirPodsPro2Confirmed {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(LoudnessMatchModalColors.success)
                .accessibilityHidden(true)
        } else if assessment.isAirPodsProPlaybackRouteCandidate {
            Image(systemName: "airpodspro")
                .font(.title2)
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .tint(LoudnessMatchModalColors.primary)
                .accessibilityHidden(true)
        }
    }

    private func airPodGlyph(systemName: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 88, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic)
            Text(label)
                .font(.headline)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        }
    }

    private var connectionTitle: String {
        if isAirPodsPro2Confirmed {
            return "AirPods Pro 2 confirmed"
        }
        if assessment.isAirPodsProPlaybackRouteCandidate {
            return "AirPods connected"
        }
        if isConfirmedAirPodsUsingCallAudio {
            return "AirPods detected"
        }
        return "Waiting for AirPods"
    }

    private var connectionDetail: String {
        if isAirPodsPro2Confirmed {
            return "Ready to continue"
        }
        if assessment.isAirPodsProPlaybackRouteCandidate {
            return "Please confirm these are AirPods Pro 2"
        }
        if isConfirmedAirPodsUsingCallAudio {
            return "Close any other app that is using them for call audio, then check again."
        }
        return "Connect both AirPods to this iPhone."
    }

    private var connectionColor: Color {
        if isAirPodsPro2Confirmed {
            return LoudnessMatchModalColors.success
        }
        if assessment.isAirPodsProPlaybackRouteCandidate {
            return LoudnessMatchModalColors.primary
        }
        return LoudnessMatchModalColors.text
    }

    #if DEBUG
    private var diagnosticsDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                diagnosticRow(
                    "Research confirmation",
                    isAirPodsPro2Confirmed ? "confirmed for current route" : "not confirmed"
                )

                ForEach(assessment.diagnosticItems) { item in
                    diagnosticRow(item.title, item.value)
                }

                #if canImport(UIKit)
                Button {
                    UIPasteboard.general.string = assessment.diagnosticReport
                } label: {
                    Label("Copy diagnostics", systemImage: "doc.on.doc")
                }
                .font(.caption)
                .padding(.top, 4)
                #endif
            }
            .padding(.top, 6)
        } label: {
            Label("AirPods route diagnostics", systemImage: "stethoscope")
                .font(.footnote)
        }
        .font(.caption)
        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        .accessibilityIdentifier("loudness_airpods_diagnostics")
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }
    #endif
}

private struct AirPodsFitStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Spacer(minLength: 0)

            Image(systemName: "ear.and.waveform")
                .font(.system(size: 108, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic, LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Adjust the position and depth of each AirPod until the fit is snug but comfortable.",
                bodyText: "A good fit is required to ensure accurate test results."
            )

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct MaxVolumeGateStepView: View {
    let validation: CalibratedAudioGuardrailValidation
    let primaryActionTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: validation.state == .passed ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 86, weight: .medium))
                    .foregroundStyle(validation.state == .passed ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.primary)
                    .accessibilityHidden(true)

                HStack(spacing: 10) {
                    Image(systemName: validation.state == .passed ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    Text(validation.state == .passed ? "Max Volume Set" : "Set Volume To Maximum")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .foregroundStyle(validation.state == .passed ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.secondaryText)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 16) {
                LoudnessMatchModalTitleBlock(
                    title: "Please use the volume buttons on your iPhone to set the volume to maximum.",
                    bodyText: "\(primaryActionTitle) becomes available after your AirPods route and maximum-volume guardrails pass."
                )

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(validation.state == .passed ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.secondaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("loudness_volume_status_label")
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statusText: String {
        switch validation.state {
        case .notEvaluated:
            return "Checking your current audio route and volume."
        case .passed:
            return "AirPods route, verification, and maximum volume are ready."
        case .failed, .restartRequired:
            return participantFacingGuardrailMessage
        }
    }

    private var participantFacingGuardrailMessage: String {
        guard let error = validation.error else {
            return "The audio route or volume is not ready yet."
        }

        switch error {
        case .unsupportedRoute:
            if let output = validation.metadata.routeDetails?.outputs.first,
               output.portType == .bluetoothHFP,
               HeadphoneRouteAssessor.looksLikeAirPodsPro(output.portName) {
                return "Another app is using your AirPods for call audio. Close Phone, Zoom, or other apps that may be using the headphones, then try again."
            }
            return "Connect your AirPods Pro 2 and keep them selected as the only audio output."
        case .unverifiedHeadphoneProfile:
            return "AirPods Pro 2 verification is required before this research task can start."
        case .invalidVolume:
            return "Use the physical volume buttons to raise output volume to maximum."
        case .routeChanged, .volumeChanged:
            return "Audio route or volume changed. Return to this step and confirm maximum volume again."
        case .unavailableAudioSessionData(let reason):
            return reason
        case .missingCalibrationProfile:
            return "The required AirPods Pro 2 calibration profile is unavailable."
        }
    }
}

private struct TinnitusLocationStepView: View {
    let selectedLaterality: TinnitusLaterality?
    let isSelectionCommitted: Bool
    let isResolvingSelection: Bool
    let selectLaterality: (TinnitusLaterality) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "ear.badge.waveform")
                .font(.system(size: min(max(iconSize, 68), 108), weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic, LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Where do you hear your tinnitus?",
                bodyText: "Choose the option that best matches where the sound is most noticeable right now."
            )
            .layoutPriority(1)

            VStack(spacing: 12) {
                ForEach(TinnitusLaterality.allCases, id: \.self) { laterality in
                    LoudnessMatchLateralityChoiceButton(
                        title: lateralityTitle(laterality),
                        isSelected: selectedLaterality == laterality,
                        isEnabled: !isSelectionCommitted && !isResolvingSelection
                    ) {
                        selectLaterality(laterality)
                    }
                }
            }

            if isResolvingSelection {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading hearing-test threshold...")
                        .font(.callout)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                }
            }
        }
    }

    private func lateralityTitle(_ laterality: TinnitusLaterality) -> String {
        switch laterality {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .bilateral:
            return "Both"
        case .central:
            return "Center"
        case .unclear:
            return "Not Sure"
        }
    }

}

private struct LoudnessMatchLateralityChoiceButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    var minHeight: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.tertiaryText)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(LoudnessMatchModalColors.text)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(isSelected ? LoudnessMatchModalColors.primary.opacity(0.12) : LoudnessMatchModalColors.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.controlStroke, lineWidth: isSelected ? 1.6 : 1)
            }
        }
        .buttonStyle(AppRoundedButtonStyle(cornerRadius: 16))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
