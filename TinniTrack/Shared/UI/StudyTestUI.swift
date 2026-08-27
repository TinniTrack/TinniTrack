import SwiftUI
import UIKit

/// Semantic, appearance-aware colors shared by active study tests.
enum StudyTestColors {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let elevatedSurface = Color(uiColor: .tertiarySystemBackground)
    static let separator = Color(uiColor: .separator)

    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)

    static let accent = Color(uiColor: .systemBlue)
    static let onAccent = Color.white
    static let accentSurface = Color(uiColor: .systemBlue).opacity(0.12)

    static let disabledFill = Color(uiColor: .systemGray5)
    static let disabledText = Color(uiColor: .tertiaryLabel)
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
}

/// Layout values shared by the orientation and recurring study-test flows.
enum StudyTestLayout {
    static let regularHorizontalGutter: CGFloat = 34
    static let compactHorizontalGutter: CGFloat = 26
    static let accessibilityHorizontalGutter: CGFloat = 20
    static let pageVerticalPadding: CGFloat = 24
    static let maximumContentWidth: CGFloat = 680

    static func horizontalGutter(
        for availableWidth: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return availableWidth < 390
                ? accessibilityHorizontalGutter
                : compactHorizontalGutter
        }

        return availableWidth < 390
            ? compactHorizontalGutter
            : regularHorizontalGutter
    }
}

struct StudyTestPageAction {
    let title: String
    var isEnabled: Bool
    var isLoading: Bool
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
}

struct StudyTestCloseAction {
    var systemImage: String
    var accessibilityLabel: String
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    init(
        systemImage: String = "xmark",
        accessibilityLabel: String = "Close",
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
}

/// A single reflowing page shell for orientation and standalone study tests.
///
/// Content always scrolls when it grows. The optional primary action remains
/// above the safe area without obscuring the scrollable content.
struct StudyTestPage<Content: View>: View {
    let navigationTitle: String
    let closeAction: StudyTestCloseAction?
    let primaryAction: StudyTestPageAction?
    let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var primaryActionBarHeight: CGFloat = 0

    init(
        navigationTitle: String,
        closeAction: StudyTestCloseAction? = nil,
        primaryAction: StudyTestPageAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.navigationTitle = navigationTitle
        self.closeAction = closeAction
        self.primaryAction = primaryAction
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalGutter = StudyTestLayout.horizontalGutter(
                for: proxy.size.width,
                dynamicTypeSize: dynamicTypeSize
            )
            let reservedActionBarHeight = primaryAction == nil
                ? 0
                : primaryActionBarHeight
            let minimumContentHeight = max(
                0,
                proxy.size.height
                    - reservedActionBarHeight
                    - proxy.safeAreaInsets.top
                    - proxy.safeAreaInsets.bottom
                    - StudyTestLayout.pageVerticalPadding * 2
            )

            ScrollView {
                content
                    .frame(
                        maxWidth: StudyTestLayout.maximumContentWidth,
                        alignment: .topLeading
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(
                        minHeight: minimumContentHeight,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, horizontalGutter)
                    .padding(.vertical, StudyTestLayout.pageVerticalPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let primaryAction {
                    primaryActionBar(
                        primaryAction,
                        horizontalGutter: horizontalGutter
                    )
                    .background {
                        GeometryReader { actionBarProxy in
                            Color.clear.preference(
                                key: StudyTestPrimaryActionBarHeightKey.self,
                                value: actionBarProxy.size.height
                            )
                        }
                    }
                }
            }
            .onPreferenceChange(StudyTestPrimaryActionBarHeightKey.self) {
                primaryActionBarHeight = $0
            }
        }
        .background(StudyTestColors.background)
        .foregroundStyle(StudyTestColors.text)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let closeAction {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton(closeAction)
                }
            }
        }
        .tint(StudyTestColors.accent)
    }

    private func primaryActionBar(
        _ action: StudyTestPageAction,
        horizontalGutter: CGFloat
    ) -> some View {
        StudyTestPrimaryButton(
            title: action.title,
            isEnabled: action.isEnabled,
            isLoading: action.isLoading,
            accessibilityLabel: action.accessibilityLabel,
            accessibilityHint: action.accessibilityHint,
            accessibilityIdentifier: action.accessibilityIdentifier,
            action: action.action
        )
        .frame(maxWidth: StudyTestLayout.maximumContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalGutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(StudyTestColors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StudyTestColors.separator.opacity(0.22))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    private func closeButton(_ closeAction: StudyTestCloseAction) -> some View {
        Button(action: closeAction.action) {
            Image(systemName: closeAction.systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(StudyTestPressButtonStyle())
        .accessibilityLabel(Text(closeAction.accessibilityLabel))
        .studyTestAccessibilityHint(closeAction.accessibilityHint)
        .studyTestAccessibilityIdentifier(closeAction.accessibilityIdentifier)
    }
}

private struct StudyTestPrimaryActionBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct StudyTestTitleBlock: View {
    let title: String
    var bodyText: String?
    var bodyFont: Font = .title2
    var bodyLineSpacing: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(StudyTestColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let bodyText {
                Text(bodyText)
                    .font(bodyFont)
                    .lineSpacing(bodyLineSpacing)
                    .foregroundStyle(StudyTestColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
}

/// Compact linear progress that can display a fraction or discrete steps.
struct StudyTestProgress: View {
    let progress: Double
    let title: String?
    let valueText: String
    let accessibilityLabel: String
    let accessibilityValue: String

    init(
        progress: Double,
        title: String? = nil,
        valueText: String? = nil,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil
    ) {
        let normalizedProgress = min(max(progress, 0), 1)
        let percentage = Int((normalizedProgress * 100).rounded())

        self.progress = normalizedProgress
        self.title = title
        self.valueText = valueText ?? "\(percentage)%"
        self.accessibilityLabel = accessibilityLabel ?? title ?? "Test progress"
        self.accessibilityValue = accessibilityValue ?? "\(percentage) percent"
    }

    init(
        currentStep: Int,
        totalSteps: Int,
        title: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        let safeTotal = max(totalSteps, 1)
        let boundedStep = min(max(currentStep, 0), safeTotal)

        self.progress = Double(boundedStep) / Double(safeTotal)
        self.title = title
        self.valueText = "\(boundedStep) of \(safeTotal)"
        self.accessibilityLabel = accessibilityLabel ?? title ?? "Test progress"
        self.accessibilityValue = "Step \(boundedStep) of \(safeTotal)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    progressTitle
                    Spacer(minLength: 12)
                    progressValue
                }

                VStack(alignment: .leading, spacing: 2) {
                    progressTitle
                    progressValue
                }
            }

            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
                .tint(StudyTestColors.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }

    @ViewBuilder
    private var progressTitle: some View {
        if let title {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudyTestColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressValue: some View {
        Text(valueText)
            .font(.subheadline)
            .fontWeight(.medium)
            .monospacedDigit()
            .foregroundStyle(StudyTestColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StudyTestPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(
                            isEnabled
                                ? StudyTestColors.onAccent
                                : StudyTestColors.disabledText
                        )
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            .foregroundStyle(
                isEnabled
                    ? StudyTestColors.onAccent
                    : StudyTestColors.disabledText
            )
            .background(
                isEnabled
                    ? StudyTestColors.accent
                    : StudyTestColors.disabledFill,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(StudyTestColors.separator.opacity(0.20), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(StudyTestPressButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(accessibilityLabel ?? title))
        .studyTestAccessibilityValue(isLoading ? "In progress" : nil)
        .studyTestAccessibilityHint(accessibilityHint)
        .studyTestAccessibilityIdentifier(accessibilityIdentifier)
    }
}

/// A quieter capsule action for retries, alternate paths, and confirmations.
struct StudyTestSecondaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .tint(StudyTestColors.secondaryText)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .foregroundStyle(
                isEnabled
                    ? StudyTestColors.text
                    : StudyTestColors.disabledText
            )
            .background(StudyTestColors.surface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(StudyTestColors.separator.opacity(0.38), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(StudyTestPressButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(accessibilityLabel ?? title))
        .studyTestAccessibilityValue(isLoading ? "In progress" : nil)
        .studyTestAccessibilityHint(accessibilityHint)
        .studyTestAccessibilityIdentifier(accessibilityIdentifier)
    }
}

/// A full-width control surface for level changes and other test decisions.
struct StudyTestControlButton: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var isEnabled: Bool = true
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(
                            isEnabled
                                ? StudyTestColors.accent
                                : StudyTestColors.disabledText
                        )
                        .frame(width: 38, height: 38)
                        .background(StudyTestColors.accentSurface, in: Circle())
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(
                            isEnabled
                                ? StudyTestColors.text
                                : StudyTestColors.disabledText
                        )

                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(
                                isEnabled
                                    ? StudyTestColors.secondaryText
                                    : StudyTestColors.disabledText
                            )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(StudyTestColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(StudyTestColors.separator.opacity(0.38), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(StudyTestPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? title))
        .studyTestAccessibilityValue(detail)
        .studyTestAccessibilityHint(accessibilityHint)
        .studyTestAccessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Prominent tone/listen action used by both threshold and loudness tests.
struct StudyTestToneButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool
    var isEnabled: Bool
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 34

    init(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    init(
        isPlaying: Bool,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            title: isPlaying ? "Stop Tone" : "Play Tone",
            systemImage: isPlaying ? "stop.fill" : "play.fill",
            isActive: isPlaying,
            isEnabled: isEnabled,
            accessibilityLabel: isPlaying ? "Stop tone playback" : "Play tone",
            accessibilityHint: isPlaying
                ? "Stops tone playback."
                : "Starts tone playback.",
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: diameter, height: diameter)
                    .background(fillColor, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(strokeColor, lineWidth: 2)
                    }
                    .shadow(
                        color: StudyTestColors.accent.opacity(isActive ? 0.14 : 0.06),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(
                        isEnabled
                            ? StudyTestColors.text
                            : StudyTestColors.disabledText
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 240)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(StudyTestPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? title))
        .studyTestAccessibilityHint(accessibilityHint)
        .studyTestAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var diameter: CGFloat {
        min(max(scaledDiameter, 76), 124)
    }

    private var iconSize: CGFloat {
        min(max(scaledIconSize, 30), 50)
    }

    private var fillColor: Color {
        guard isEnabled else {
            return StudyTestColors.disabledFill
        }
        return isActive ? StudyTestColors.accent : StudyTestColors.background
    }

    private var iconColor: Color {
        guard isEnabled else {
            return StudyTestColors.disabledText
        }
        return isActive ? StudyTestColors.onAccent : StudyTestColors.accent
    }

    private var strokeColor: Color {
        guard isEnabled else {
            return StudyTestColors.separator.opacity(0.24)
        }
        return StudyTestColors.accent.opacity(isActive ? 0.82 : 0.55)
    }
}

/// Press feedback deliberately avoids geometry scaling so large text remains
/// stable and nearby controls do not visually jump.
private struct StudyTestPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private extension View {
    @ViewBuilder
    func studyTestAccessibilityHint(_ hint: String?) -> some View {
        if let hint, !hint.isEmpty {
            accessibilityHint(Text(hint))
        } else {
            self
        }
    }

    @ViewBuilder
    func studyTestAccessibilityValue(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            accessibilityValue(Text(value))
        } else {
            self
        }
    }

    @ViewBuilder
    func studyTestAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier, !identifier.isEmpty {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview("Study test visual system") {
    NavigationStack {
        StudyTestPage(
            navigationTitle: "Orientation",
            closeAction: StudyTestCloseAction(action: {}),
            primaryAction: StudyTestPageAction(title: "Same Loudness", action: {})
        ) {
            VStack(alignment: .leading, spacing: 24) {
                StudyTestProgress(
                    currentStep: 2,
                    totalSteps: 3,
                    title: "Loudness match"
                )

                StudyTestTitleBlock(
                    title: "Match the loudness",
                    bodyText: "Adjust the tone until it sounds as loud as your tinnitus."
                )

                StudyTestToneButton(isPlaying: false, action: {})
                    .frame(maxWidth: .infinity)

                StudyTestControlButton(
                    title: "Louder",
                    detail: "Small adjustment",
                    systemImage: "chevron.up",
                    action: {}
                )

                StudyTestSecondaryButton(
                    title: "I Hear the Tone",
                    systemImage: "ear",
                    action: {}
                )
            }
        }
    }
}
