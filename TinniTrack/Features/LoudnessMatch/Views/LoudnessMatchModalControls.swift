import SwiftUI

enum LoudnessMatchModalStep: Equatable {
    case intro
    case quietRoom
    case correctEar
    case fit
    case maxVolume
    case activeTest
}

enum LoudnessMatchModalColors {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let controlBackground = Color.white.opacity(0.06)
    static let controlStroke = Color.white.opacity(0.10)
    static let primary = Color(red: 0.02, green: 0.58, blue: 1.0)
    static let primaryText = Color.white
    static let disabledFill = Color.white.opacity(0.16)
    static let disabledText = Color.white.opacity(0.34)
    static let secondaryText = Color.white.opacity(0.56)
    static let tertiaryText = Color.white.opacity(0.38)
    static let success = Color(red: 0.16, green: 0.84, blue: 0.34)
    static let warning = Color(red: 1.0, green: 0.56, blue: 0.16)
}

struct LoudnessMatchModalPrimaryButton: View {
    let title: String
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(isEnabled ? LoudnessMatchModalColors.primaryText : LoudnessMatchModalColors.disabledText)
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .background(isEnabled ? LoudnessMatchModalColors.primary : LoudnessMatchModalColors.disabledFill)
        .foregroundStyle(isEnabled ? LoudnessMatchModalColors.primaryText : LoudnessMatchModalColors.disabledText)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(isEnabled ? 0.18 : 0.10), lineWidth: 1)
        }
        .accessibilityIdentifier("loudness_modal_primary_button")
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(LoudnessMatchModalColors.controlBackground)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct LoudnessMatchModalContentLayout<Content: View, Footer: View>: View {
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.top, 104)
                    .padding(.bottom, 24)
            }

            footer
                .padding(.horizontal, 34)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
    }
}

struct LoudnessMatchModalTitleBlock: View {
    let title: String
    var bodyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let bodyText {
                Text(bodyText)
                    .font(.title2)
                    .lineSpacing(5)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
