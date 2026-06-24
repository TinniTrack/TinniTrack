import SwiftUI

struct LoudnessMatchNoiseGateView: View {
    let update: TinnitusEnvironmentSPLGateUpdate?
    let showSuggestions: () -> Void

    private var status: TinnitusEnvironmentSPLGateStatus {
        update?.status ?? .measuring
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 0)

            VStack(spacing: 26) {
                LoudnessMatchNoiseGateMeter(
                    status: status,
                    levelRatio: levelRatio,
                    passingProgress: passingProgress,
                    isCompact: false
                )

                HStack(spacing: 10) {
                    statusIcon
                    Text(statusText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("loudness_noise_status_label")
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                LoudnessMatchModalTitleBlock(
                    title: "Find a quiet place where you can focus and take the test.",
                    bodyText: "Too much background noise can cause inaccurate results in your test."
                )

                Button(action: showSuggestions) {
                    Label("Show Suggestions To Reduce Noise", systemImage: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(AppRoundedButtonStyle(cornerRadius: 8))
                .padding(.top, 14)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("loudness_noise_gate_step")
    }

    private var statusIcon: Image {
        switch status {
        case .measuring:
            return Image(systemName: "ellipsis")
        case .tooLoud:
            return Image(systemName: "exclamationmark.circle.fill")
        case .passed:
            return Image(systemName: "checkmark.circle.fill")
        }
    }

    private var statusText: String {
        switch status {
        case .measuring:
            return "In Progress..."
        case .tooLoud:
            return "Too much noise"
        case .passed:
            return "Noise Ok"
        }
    }

    private var statusColor: Color {
        switch status {
        case .measuring:
            return LoudnessMatchModalColors.secondaryText
        case .tooLoud:
            return LoudnessMatchModalColors.warning
        case .passed:
            return LoudnessMatchModalColors.success
        }
    }

    private var levelRatio: Double {
        guard let latestSampleDBA = update?.latestSampleDBA else {
            return 0.66
        }

        return latestSampleDBA / TinnitusEnvironmentSPLGateConfiguration.studyNo1.thresholdDBA
    }

    private var passingProgress: Double {
        guard let update else {
            return 0
        }

        return min(
            1,
            Double(update.contiguousPassingSamples) / Double(TinnitusEnvironmentSPLGateConfiguration.studyNo1.requiredContiguousSamples)
        )
    }
}

struct LoudnessMatchNoiseGateMeter: View {
    let status: TinnitusEnvironmentSPLGateStatus
    let levelRatio: Double
    var passingProgress: Double?
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedIndex = 0

    var body: some View {
        VStack(spacing: isCompact ? 12 : 18) {
            ZStack {
                Circle()
                    .stroke(ringBackgroundColor, lineWidth: ringLineWidth)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: ringSymbolName)
                    .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                    .foregroundStyle(ringColor)
            }
            .frame(width: isCompact ? 44 : 54, height: isCompact ? 44 : 54)
            .animation(.easeInOut(duration: 0.22), value: status)
            .animation(.easeInOut(duration: 0.22), value: ringProgress)

            GeometryReader { proxy in
                let columnCount = columnCount(for: proxy.size.width)
                HStack(alignment: .top, spacing: Self.squareDistance) {
                    ForEach(0..<columnCount, id: \.self) { index in
                        meterColumn(
                            color: columnColor(for: index, columnCount: columnCount),
                            opacity: columnOpacity(for: index),
                            dotSize: Self.squareSize
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear {
                    displayedIndex = targetIndex(columnCount: columnCount)
                }
                .onChange(of: targetIndex(columnCount: columnCount)) { _, _ in
                    if reduceMotion {
                        displayedIndex = targetIndex(columnCount: columnCount)
                    }
                }
                .task(id: animationTaskID(columnCount: columnCount)) {
                    await animateDisplayedIndex(columnCount: columnCount)
                }
            }
            .frame(height: Self.barHeight)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private static let squareSize: CGFloat = 8
    private static let squareDistance: CGFloat = 4
    private static let rowSpacing: CGFloat = 12
    private static let rowCount = 4
    private static let greenLimitRatio = 0.66
    private static let barHeight: CGFloat = 44

    private var clampedLevelRatio: Double {
        min(1.5, max(0, levelRatio))
    }

    private var ringProgress: CGFloat {
        switch status {
        case .passed:
            return 1
        case .tooLoud:
            return 1
        case .measuring:
            return min(0.94, max(0.08, passingProgress ?? 0))
        }
    }

    private var ringSymbolName: String {
        switch status {
        case .measuring:
            return "ellipsis"
        case .tooLoud:
            return "xmark"
        case .passed:
            return "checkmark"
        }
    }

    private var ringColor: Color {
        switch status {
        case .measuring:
            return LoudnessMatchModalColors.primary
        case .tooLoud:
            return LoudnessMatchModalColors.warning
        case .passed:
            return LoudnessMatchModalColors.success
        }
    }

    private var ringBackgroundColor: Color {
        switch status {
        case .tooLoud:
            return LoudnessMatchModalColors.warning.opacity(0.22)
        case .passed:
            return LoudnessMatchModalColors.success.opacity(0.22)
        case .measuring:
            return LoudnessMatchModalColors.meterInactive.opacity(0.34)
        }
    }

    private var ringLineWidth: CGFloat {
        isCompact ? 4 : 5
    }

    private var accessibilityLabel: String {
        switch status {
        case .measuring:
            return "Quiet-room meter measuring"
        case .tooLoud:
            return "Quiet-room meter too loud"
        case .passed:
            return "Quiet-room meter passed"
        }
    }

    private func meterColumn(color: Color, opacity: Double, dotSize: CGFloat) -> some View {
        VStack(spacing: Self.squareDistance) {
            ForEach(0..<Self.rowCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Self.squareDistance, style: .continuous)
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(opacity)
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(16, Int(floor(width / Self.rowSpacing)) + 1)
    }

    private func greenIndexLimit(columnCount: Int) -> Int {
        Int(Double(columnCount) * Self.greenLimitRatio)
    }

    private func normalizedLevelRatio() -> Double {
        if clampedLevelRatio <= 1 {
            return Self.greenLimitRatio * clampedLevelRatio
        }

        let loudRangeProgress = min(1, (clampedLevelRatio - 1) / 0.5)
        return Self.greenLimitRatio + ((1 - Self.greenLimitRatio) * loudRangeProgress)
    }

    private func targetIndex(columnCount: Int) -> Int {
        switch status {
        case .passed:
            return greenIndexLimit(columnCount: columnCount)
        case .tooLoud:
            let minimumLoudIndex = greenIndexLimit(columnCount: columnCount) + 2
            let currentLevelIndex = Int(floor(normalizedLevelRatio() * Double(columnCount))) + 1
            return min(columnCount - 1, max(minimumLoudIndex, currentLevelIndex))
        case .measuring:
            return min(columnCount - 1, max(0, Int(floor(normalizedLevelRatio() * Double(columnCount))) + 1))
        }
    }

    private func animationTaskID(columnCount: Int) -> String {
        "\(columnCount)-\(targetIndex(columnCount: columnCount))-\(status)-\(reduceMotion)"
    }

    @MainActor
    private func animateDisplayedIndex(columnCount: Int) async {
        let target = targetIndex(columnCount: columnCount)
        guard !reduceMotion, status != .passed else {
            displayedIndex = target
            return
        }

        if displayedIndex == 0 {
            displayedIndex = target
        }

        while !Task.isCancelled {
            if displayedIndex > target {
                displayedIndex -= 1
            } else if displayedIndex < target {
                displayedIndex += 1
            } else {
                displayedIndex = min(columnCount - 1, max(0, target + Int.random(in: -1...1)))
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func columnColor(for index: Int, columnCount: Int) -> Color {
        if index <= greenIndexLimit(columnCount: columnCount) {
            return shouldHighlight(index: index) ? LoudnessMatchModalColors.success : LoudnessMatchModalColors.meterInactive
        }

        return shouldHighlight(index: index) ? LoudnessMatchModalColors.warning : LoudnessMatchModalColors.meterInactive
    }

    private func columnOpacity(for index: Int) -> Double {
        if index < displayedIndex {
            return 1
        }

        let distance = index - displayedIndex
        if distance < 3 {
            return max(0.22, 0.5 - (0.1 * Double(distance)))
        }

        return 1
    }

    private func shouldHighlight(index: Int) -> Bool {
        index < displayedIndex || index - displayedIndex < 3
    }
}

struct LoudnessMatchNoiseSuggestionsView: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    LoudnessMatchModalIconButton(
                        systemName: "checkmark",
                        accessibilityLabel: "Done",
                        accessibilityIdentifier: "loudness_noise_suggestions_done_button",
                        action: dismiss
                    )
                    .background(LoudnessMatchModalColors.primary, in: Circle())
                }
                .padding(.horizontal, 34)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 26) {
                    Spacer(minLength: 0)

                    LoudnessMatchModalTitleBlock(
                        title: "Suggestions to Reduce Background Noise",
                        bodyText: "Background noise can make it too hard to hear the tones in the test."
                    )

                    suggestionRow(systemName: "sofa.fill", text: "Try moving to a room or location that's typically more quiet.")
                    suggestionRow(systemName: "fan.slash.fill", text: "Close windows and turn off fans or air conditioning.")
                    suggestionRow(systemName: "moon.stars.fill", text: "Try again later when your space might be more quiet or calm.")

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 34)
                .padding(.top, 42)
                .padding(.bottom, 34)
            }
        }
    }

    private func suggestionRow(systemName: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 22) {
            Image(systemName: systemName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(width: 48)

            Text(text)
                .font(.title3)
                .foregroundStyle(LoudnessMatchModalColors.text)
                .lineSpacing(4)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
    }
}
