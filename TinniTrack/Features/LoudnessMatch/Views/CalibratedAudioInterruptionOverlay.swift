import SwiftUI

struct CalibratedAudioInterruptionOverlay: View {
    let systemName: String
    let title: String
    let bodyText: String
    let accessibilityIdentifier: String
    var quietRoomLevelRatio: Double?
    let actionTitle: String
    let action: () -> Void

    @AccessibilityFocusState private var isPopupFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 24)
                        popupCard
                        Spacer(minLength: 24)
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            isPopupFocused = true
        }
    }

    private var popupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let quietRoomLevelRatio {
                LoudnessMatchNoiseGateMeter(
                    status: .interruptedByLoudness,
                    levelRatio: quietRoomLevelRatio,
                    isCompact: true
                )
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(LoudnessMatchModalColors.primary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isPopupFocused)

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            LoudnessMatchModalPrimaryButton(
                title: actionTitle,
                isEnabled: true,
                action: action
            )
        }
        .padding(24)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StudyTestColors.separator.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 12)
    }
}
