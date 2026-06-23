import SwiftUI

struct LoudnessMatchPreparationStepView: View {
    let step: LoudnessMatchModalStep
    @ObservedObject var viewModel: LoudnessMatchTaskFlowViewModel
    let showNoiseSuggestions: () -> Void

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
            AirPodsCorrectEarStepView(assessment: viewModel.headphoneRouteAssessment)
        case .fit:
            AirPodsFitStepView()
        case .maxVolume:
            MaxVolumeGateStepView(validation: viewModel.currentGuardrailValidation)
                .accessibilityIdentifier("loudness_volume_gate_step")
        case .activeTest:
            EmptyView()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Spacer(minLength: 0)

            HStack(spacing: 52) {
                airPodGlyph(label: "L")
                airPodGlyph(label: "R")
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            LoudnessMatchModalTitleBlock(
                title: "Place your AirPods in the correct ear.",
                bodyText: "Having your right AirPod in your right ear and left in your left ear can help with test quality.\n\nIf you wear hearing aids, be sure to remove them first."
            )

            Text(statusText)
                .font(.callout)
                .foregroundStyle(assessment.passesAirPodsPro2Heuristic ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.secondaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("loudness_airpods_status_label")

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("loudness_airpods_step")
    }

    private func airPodGlyph(label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(.system(size: 94, weight: .regular))
                .foregroundStyle(LoudnessMatchModalColors.graphic)
            Text(label)
                .font(.headline)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        }
    }

    private var statusText: String {
        if assessment.passesAirPodsPro2Heuristic {
            return "AirPods Pro 2 playback route detected."
        }

        switch assessment.primaryIssue {
        case .noOutput, .builtInOutput, .bluetoothHeadsetProfile, .bluetoothLowEnergyRoute, .unknownRoute, nil:
            return "Waiting for your AirPods Pro 2 playback route."
        case .multipleOutputs, .unsupportedWiredOrExternalRoute, .unsupportedBluetoothPlaybackDevice, .outputVolumeUnavailable:
            return "The current audio output is not eligible for this study."
        }
    }
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
                    bodyText: "Start Test becomes available after your AirPods route and maximum-volume guardrails pass."
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
