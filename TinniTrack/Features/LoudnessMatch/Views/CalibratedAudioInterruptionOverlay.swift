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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let quietRoomLevelRatio {
                        LoudnessMatchNoiseGateMeter(
                            status: .tooLoud,
                            levelRatio: quietRoomLevelRatio,
                            isCompact: true
                        )
                        .padding(.horizontal, 6)
                        .accessibilityHidden(true)
                    } else {
                        Image(systemName: systemName)
                            .font(.system(size: 58, weight: .regular))
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
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    LoudnessMatchModalPrimaryButton(
                        title: actionTitle,
                        isEnabled: true,
                        action: action
                    )
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LoudnessMatchModalColors.background)
                        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
                )
                .padding(.horizontal, 30)
                .padding(.vertical, 32)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            isPopupFocused = true
        }
    }
}
