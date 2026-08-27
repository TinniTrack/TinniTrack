import SwiftUI
import UIKit

enum LoudnessMatchModalStep: Equatable {
    case intro
    case quietRoom
    case correctEar
    case fit
    case maxVolume
    case tinnitusLocation
}

enum LoudnessMatchModalColors {
    static let background = StudyTestColors.background
    static let controlBackground = StudyTestColors.surface
    static let controlStroke = StudyTestColors.separator.opacity(0.38)
    static let buttonStroke = StudyTestColors.separator.opacity(0.20)
    static let primary = StudyTestColors.accent
    static let primaryText = StudyTestColors.onAccent
    static let disabledFill = StudyTestColors.disabledFill
    static let text = StudyTestColors.text
    static let secondaryText = StudyTestColors.secondaryText
    static let tertiaryText = StudyTestColors.tertiaryText
    static let disabledText = StudyTestColors.disabledText
    static let graphic = StudyTestColors.text.opacity(0.84)
    static let meterInactive = Color(uiColor: .systemGray3)
    static let success = StudyTestColors.success
    static let warning = StudyTestColors.warning
}

struct LoudnessMatchModalPrimaryButton: View {
    let title: String
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        StudyTestPrimaryButton(
            title: title,
            isEnabled: isEnabled,
            isLoading: isLoading,
            accessibilityIdentifier: "loudness_modal_primary_button",
            action: action
        )
    }
}

struct LoudnessMatchModalIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 54, height: 54)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .background(LoudnessMatchModalColors.controlBackground)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                }
        }
        .buttonStyle(AppCircleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct LoudnessMatchModalTitleBlock: View {
    let title: String
    var bodyText: String?
    var bodyFont: Font = .title2
    var bodyLineSpacing: CGFloat = 5
    var titleLineLimit: Int? = 4
    var bodyLineLimit: Int? = 6

    var body: some View {
        StudyTestTitleBlock(
            title: title,
            bodyText: bodyText,
            bodyFont: bodyFont,
            bodyLineSpacing: bodyLineSpacing
        )
    }
}
