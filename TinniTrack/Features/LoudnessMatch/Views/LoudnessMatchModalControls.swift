import SwiftUI
import UIKit

enum LoudnessMatchModalStep: Equatable {
    case intro
    case quietRoom
    case correctEar
    case fit
    case maxVolume
    case activeTest
}

enum LoudnessMatchModalColors {
    static let background = dynamic(
        light: .systemBackground,
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let controlBackground = dynamic(
        light: .secondarySystemBackground,
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let controlStroke = dynamic(
        light: UIColor.separator.withAlphaComponent(0.36),
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    static let buttonStroke = dynamic(
        light: UIColor.separator.withAlphaComponent(0.24),
        dark: UIColor.white.withAlphaComponent(0.18)
    )
    static let primary = Color(red: 0.02, green: 0.58, blue: 1.0)
    static let primaryText = Color.white
    static let disabledFill = dynamic(
        light: .systemGray5,
        dark: UIColor.white.withAlphaComponent(0.16)
    )
    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let disabledText = Color(uiColor: .tertiaryLabel)
    static let graphic = dynamic(
        light: UIColor.label.withAlphaComponent(0.82),
        dark: UIColor.white.withAlphaComponent(0.90)
    )
    static let meterInactive = dynamic(
        light: .systemGray3,
        dark: UIColor.white.withAlphaComponent(0.36)
    )
    static let success = Color(red: 0.16, green: 0.84, blue: 0.34)
    static let warning = Color(red: 1.0, green: 0.56, blue: 0.16)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
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
                .stroke(LoudnessMatchModalColors.buttonStroke, lineWidth: 1)
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
        .foregroundStyle(LoudnessMatchModalColors.text)
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
        GeometryReader { proxy in
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .scaleEffect(contentScale(for: proxy.size.height), anchor: .top)
                    .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                    .padding(.top, topPadding(for: proxy.size.height))
                    .padding(.bottom, 10)

                footer
                    .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                    .padding(.top, 8)
                    .padding(.bottom, bottomPadding(for: proxy.safeAreaInsets.bottom))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        width < 390 ? 26 : 34
    }

    private func topPadding(for height: CGFloat) -> CGFloat {
        height < 700 ? 82 : 104
    }

    private func bottomPadding(for safeAreaBottom: CGFloat) -> CGFloat {
        max(14, safeAreaBottom + 6)
    }

    private func contentScale(for height: CGFloat) -> CGFloat {
        if height < 640 { return 0.86 }
        if height < 720 { return 0.93 }
        return 1.0
    }
}

struct LoudnessMatchModalTitleBlock: View {
    let title: String
    var bodyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(LoudnessMatchModalColors.text)
                .lineLimit(4)
                .minimumScaleFactor(0.82)

            if let bodyText {
                Text(bodyText)
                    .font(.title2)
                    .lineSpacing(5)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .lineLimit(6)
                    .minimumScaleFactor(0.82)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
