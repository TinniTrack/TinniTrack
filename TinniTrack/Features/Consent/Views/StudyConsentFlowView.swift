//
//  StudyConsentFlowView.swift
//  TinniTrack
//

import SwiftUI
import UIKit

struct StudyConsentFlowView: View {
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StudyConsentFlowViewModel

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        onCompleted: @escaping () async -> Void
    ) {
        self.onCompleted = onCompleted
        _viewModel = StateObject(wrappedValue: StudyConsentFlowViewModel(
            study: study,
            definition: definition,
            consentService: consentService
        ))
    }

    var body: some View {
        ZStack {
            StudyConsentModalChrome(
                canGoBack: viewModel.state == .reviewingConsent || viewModel.state == .signing,
                goBack: viewModel.goBack,
                close: viewModel.declineOrCancel
            ) {
                content
            }

            if viewModel.state == .finalizing {
                StudyConsentFinalizingView()
            }
        }
        .interactiveDismissDisabled(true)
        .task(id: viewModel.state) {
            switch viewModel.state {
            case .completed:
                await onCompleted()
                dismiss()
            case .dismissed:
                dismiss()
            case .landing, .reviewingConsent, .signing, .finalizing, .failed:
                break
            }
        }
        .alert("Unable to Finish Enrollment", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("Try Again") {
                viewModel.retryAfterFailure()
            }
            Button("Cancel", role: .cancel) {
                viewModel.declineOrCancel()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .landing:
            StudyConsentLandingView(
                definition: viewModel.definition,
                reviewConsent: viewModel.reviewConsent
            )
        case .reviewingConsent:
            StudyConsentReaderView(viewModel: viewModel)
        case .signing:
            StudyConsentSignatureView(viewModel: viewModel)
        case .finalizing:
            StudyConsentSignatureView(viewModel: viewModel)
        case .completed:
            StudyConsentSuccessView()
        case .dismissed, .failed:
            EmptyView()
        }
    }
}

private struct StudyConsentModalChrome<Content: View>: View {
    let canGoBack: Bool
    let goBack: () -> Void
    let close: () -> Void
    let content: Content

    init(
        canGoBack: Bool,
        goBack: @escaping () -> Void,
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.canGoBack = canGoBack
        self.goBack = goBack
        self.close = close
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            LoudnessMatchModalColors.background
                .ignoresSafeArea()

            content
                .padding(.top, 84)

            HStack {
                LoudnessMatchModalIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back",
                    accessibilityIdentifier: "study_consent_back_button",
                    action: goBack
                )
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)

                Spacer()

                LoudnessMatchModalIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "Close",
                    accessibilityIdentifier: "study_consent_close_button",
                    action: close
                )
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
        }
        .foregroundStyle(LoudnessMatchModalColors.text)
    }
}

private struct StudyConsentLandingView: View {
    let definition: StudyConsentDefinition
    let reviewConsent: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(definition.landing.eyebrow)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(LoudnessMatchModalColors.primary)

                    Text(definition.landing.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    Text(definition.landing.subtitle)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                }

                StudyConsentAtAGlanceCard(rows: definition.landing.atAGlanceRows)

                StudyConsentTextSection(
                    title: "What you'll do",
                    bodyText: definition.landing.whatYouWillDo
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("You may be eligible if")
                        .font(.system(size: 16, weight: .bold))

                    ForEach(definition.landing.eligibilityItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(LoudnessMatchModalColors.primary)
                                .clipShape(Circle())

                            Text(item)
                                .font(.system(size: 14))
                                .foregroundStyle(LoudnessMatchModalColors.text)
                        }
                    }
                }

                StudyConsentCallout(
                    systemName: "info.circle",
                    title: definition.landing.beforeEnrollTitle,
                    bodyText: definition.landing.beforeEnrollBody
                )

                LoudnessMatchModalPrimaryButton(title: definition.landing.primaryActionTitle) {
                    reviewConsent()
                }
                .padding(.top, 2)

                Text(definition.landing.footerNote)
                    .font(.footnote)
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("study_consent_landing")
    }
}

private struct StudyConsentReaderView: View {
    @ObservedObject var viewModel: StudyConsentFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        StudyConsentProgressHeader(
                            stepText: "Step 1 of 2",
                            progress: 0.5,
                            title: "Informed Consent",
                            subtitle: viewModel.definition.landing.title
                        )

                        StudyConsentKeyInfoCard(keyInformation: viewModel.definition.keyInformation)

                        StudyConsentTabs(
                            sections: viewModel.tabSections,
                            selectedSectionID: viewModel.selectedSectionID
                        ) { section in
                            viewModel.selectSection(section)
                            withAnimation(.easeInOut(duration: 0.22)) {
                                proxy.scrollTo(section.id, anchor: .top)
                            }
                        }

                        ForEach(viewModel.visibleSections) { section in
                            StudyConsentSectionView(section: section)
                                .id(section.id)
                        }

                        VStack(spacing: 8) {
                            Image(systemName: viewModel.canContinueToSignature ? "checkmark.lock.open" : "lock")
                            Text(viewModel.canContinueToSignature ? "You can continue" : "Scroll to the end to continue")
                        }
                        .font(.footnote)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .onAppear {
                            viewModel.markConsentScrolledToEnd()
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }

            StudyConsentBottomActionBar(
                secondaryTitle: "I do not agree",
                primaryTitle: "I agree, continue to signature",
                isPrimaryEnabled: viewModel.canContinueToSignature,
                secondaryAction: viewModel.declineOrCancel,
                primaryAction: viewModel.continueToSignature
            )
        }
        .accessibilityIdentifier("study_consent_reader")
    }
}

private struct StudyConsentSignatureView: View {
    @ObservedObject var viewModel: StudyConsentFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StudyConsentProgressHeader(
                    stepText: "Step 2 of 2",
                    progress: 1,
                    title: "Sign Consent",
                    subtitle: "By signing below, you confirm that you reviewed the consent information and choose to participate in Study No. 1: Loudness Match."
                )

                Button {
                    viewModel.isAttestationAccepted.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: viewModel.isAttestationAccepted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(LoudnessMatchModalColors.primary)

                        Text(viewModel.definition.attestation.text)
                            .font(.system(size: 14))
                            .foregroundStyle(LoudnessMatchModalColors.text)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                    }
                }
                .buttonStyle(AppRoundedButtonStyle(cornerRadius: 7))

                StudyConsentTextField(title: "First name", text: $viewModel.firstName, textContentType: .givenName)
                StudyConsentTextField(title: "Last name", text: $viewModel.lastName, textContentType: .familyName)

                StudySignatureCanvasCard(
                    signatureImageData: $viewModel.signatureImageData,
                    clear: viewModel.clearSignature
                )

                StudyConsentMetadataRows(signedAt: Date())

                LoudnessMatchModalPrimaryButton(
                    title: "Sign and Enroll",
                    isEnabled: viewModel.canSignAndEnroll,
                    isLoading: viewModel.state == .finalizing
                ) {
                    Task { await viewModel.signAndEnroll() }
                }
                .padding(.top, 8)

                Button("I do not agree") {
                    viewModel.declineOrCancel()
                }
                .font(.headline)
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("study_consent_signature")
    }
}

private struct StudyConsentProgressHeader: View {
    let stepText: String
    let progress: CGFloat
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stepText)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(LoudnessMatchModalColors.primary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(LoudnessMatchModalColors.primary)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StudyConsentAtAGlanceCard: View {
    let rows: [StudyConsentAtAGlanceRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("At a glance")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 14) {
                    Image(systemName: row.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LoudnessMatchModalColors.primary)
                        .frame(width: 26)

                    Text(row.label)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 112, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(row.value)
                        .font(.system(size: 14))
                        .foregroundStyle(LoudnessMatchModalColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 54)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
        }
    }
}

private struct StudyConsentTextSection: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Text(bodyText)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        }
    }
}

private struct StudyConsentCallout: View {
    let systemName: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LoudnessMatchModalColors.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(bodyText)
                    .font(.system(size: 13))
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(LoudnessMatchModalColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(LoudnessMatchModalColors.primary.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct StudyConsentKeyInfoCard: View {
    let keyInformation: StudyConsentKeyInformation

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(LoudnessMatchModalColors.primary)
                Text(keyInformation.title)
                    .font(.system(size: 15, weight: .bold))
            }

            ForEach(keyInformation.bulletItems, id: \.self) { item in
                consentInfoRow(systemName: "circle.fill", text: item, iconSize: 5)
            }

            ForEach(keyInformation.checkItems, id: \.self) { item in
                consentInfoRow(systemName: "checkmark", text: item, iconSize: 11)
            }
        }
        .padding(12)
        .background(LoudnessMatchModalColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LoudnessMatchModalColors.primary.opacity(0.25), lineWidth: 1)
        }
    }

    private func consentInfoRow(systemName: String, text: String, iconSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(width: 13, height: 18)

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundStyle(LoudnessMatchModalColors.text)
        }
    }
}

private struct StudyConsentTabs: View {
    let sections: [StudyConsentSection]
    let selectedSectionID: String
    let select: (StudyConsentSection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(sections) { section in
                    Button {
                        select(section)
                    } label: {
                        Text(section.tabTitle ?? section.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedSectionID == section.id ? .white : LoudnessMatchModalColors.text)
                            .background(selectedSectionID == section.id ? LoudnessMatchModalColors.primary : Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                            }
                    }
                    .buttonStyle(AppRoundedButtonStyle(cornerRadius: 6))
                }
            }
        }
    }
}

private struct StudyConsentSectionView: View {
    let section: StudyConsentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 16, weight: .bold))

            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                StudyConsentBlockView(block: block)
            }
        }
    }
}

private struct StudyConsentBlockView: View {
    let block: StudyConsentContentBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(LoudnessMatchModalColors.primary)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                    }
                }
            }
        case .numberedActivities(let activities):
            VStack(alignment: .leading, spacing: 18) {
                ForEach(activities, id: \.index) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(activity.index)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LoudnessMatchModalColors.primary)
                            .frame(width: 21, height: 21)
                            .background(LoudnessMatchModalColors.primary.opacity(0.16))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(activity.title)
                                .font(.system(size: 14, weight: .bold))
                            Text(activity.body)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .foregroundStyle(LoudnessMatchModalColors.text)
                        }
                    }
                }
            }
        case .scheduleChips(let times):
            HStack(spacing: 10) {
                ForEach(times, id: \.self) { time in
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LoudnessMatchModalColors.primary)
                        Text(time)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                    }
                }
            }
        case .callout(let title, let body):
            StudyConsentCallout(systemName: "info.circle", title: title, bodyText: body)
        case .contacts(let contacts):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(contacts, id: \.email) { contact in
                    Text(contact.displayText)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                }
            }
        }
    }
}

private struct StudyConsentBottomActionBar: View {
    let secondaryTitle: String
    let primaryTitle: String
    let isPrimaryEnabled: Bool
    let secondaryAction: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(secondaryTitle, action: secondaryAction)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LoudnessMatchModalColors.primary)
                .frame(width: 92)

            LoudnessMatchModalPrimaryButton(
                title: primaryTitle,
                isEnabled: isPrimaryEnabled,
                action: primaryAction
            )
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct StudyConsentTextField: View {
    let title: String
    @Binding var text: String
    let textContentType: UITextContentType

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)

            TextField(title, text: $text)
                .textContentType(textContentType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.system(size: 17))
                .padding(.horizontal, 13)
                .frame(height: 45)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                }
        }
    }
}

private struct StudySignatureCanvasCard: View {
    @Binding var signatureImageData: Data?
    let clear: () -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Draw signature")
                .font(.footnote)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)

            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))

                    Canvas { context, _ in
                        for stroke in strokes + [currentStroke] where stroke.count > 1 {
                            var path = Path()
                            path.move(to: stroke[0])
                            for point in stroke.dropFirst() {
                                path.addLine(to: point)
                            }
                            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        }

                        var baseline = Path()
                        baseline.move(to: CGPoint(x: 14, y: proxy.size.height - 44))
                        baseline.addLine(to: CGPoint(x: proxy.size.width - 14, y: proxy.size.height - 44))
                        context.stroke(baseline, with: .color(Color(uiColor: .systemGray3)), lineWidth: 1)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentStroke.append(value.location)
                            }
                            .onEnded { _ in
                                if currentStroke.count > 1 {
                                    strokes.append(currentStroke)
                                }
                                currentStroke = []
                                signatureImageData = Self.render(strokes: strokes, size: proxy.size)
                            }
                    )

                    Button("Clear") {
                        strokes = []
                        currentStroke = []
                        clear()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.primary)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(LoudnessMatchModalColors.controlStroke, lineWidth: 1)
                }
            }
            .frame(height: 122)
        }
    }

    private static func render(strokes: [[CGPoint]], size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(2.2)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)

            for stroke in strokes where stroke.count > 1 {
                context.cgContext.beginPath()
                context.cgContext.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    context.cgContext.addLine(to: point)
                }
                context.cgContext.strokePath()
            }
        }
        return image.pngData()
    }
}

private struct StudyConsentMetadataRows: View {
    let signedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .medium))
                Text("Signed today, \(Self.dateFormatter.string(from: signedAt))")
                    .font(.system(size: 14))
            }

            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(Circle())
                Text("A signed consent copy will be saved securely.")
                    .font(.system(size: 14))
                    .foregroundStyle(LoudnessMatchModalColors.secondaryText)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct StudyConsentFinalizingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Finalizing Enrollment")
                    .font(.headline)
                Text("Saving your signed consent securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 18)
        }
    }
}

private struct StudyConsentSuccessView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(LoudnessMatchModalColors.success)
            Text("Enrollment Complete")
                .font(.title2.bold())
            Text("Your signed consent was saved securely.")
                .font(.subheadline)
                .foregroundStyle(LoudnessMatchModalColors.secondaryText)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Landing") {
    StudyConsentFlowPreview()
}

#Preview("Reader") {
    StudyConsentReaderView(viewModel: StudyConsentFlowPreviewModel.makeReader())
}

#Preview("Signature") {
    StudyConsentSignatureView(viewModel: StudyConsentFlowPreviewModel.makeSignature())
}

private struct StudyConsentFlowPreview: View {
    var body: some View {
        StudyConsentFlowView(
            study: Study(
                id: UUID(),
                slug: "study-no-1",
                title: "Study No. 1",
                description: "Baseline tinnitus study",
                status: .recruiting,
                createdAt: nil
            ),
            definition: StudyConsentCatalog.studyNo1,
            consentService: PreviewConsentService(),
            onCompleted: {}
        )
    }
}

@MainActor
private enum StudyConsentFlowPreviewModel {
    static func makeReader() -> StudyConsentFlowViewModel {
        let model = base()
        model.reviewConsent()
        return model
    }

    static func makeSignature() -> StudyConsentFlowViewModel {
        let model = base()
        model.reviewConsent()
        model.markConsentScrolledToEnd()
        model.continueToSignature()
        model.firstName = "Alex"
        model.lastName = "Morgan"
        return model
    }

    private static func base() -> StudyConsentFlowViewModel {
        StudyConsentFlowViewModel(
            study: Study(
                id: UUID(),
                slug: "study-no-1",
                title: "Study No. 1",
                description: "Baseline tinnitus study",
                status: .recruiting,
                createdAt: nil
            ),
            definition: StudyConsentCatalog.studyNo1,
            consentService: PreviewConsentService()
        )
    }
}

private struct PreviewConsentService: ConsentServiceProtocol {
    func finalizeConsentAndEnroll(study: Study, consent: StudyConsentCompletion) async throws {}
}
#endif
