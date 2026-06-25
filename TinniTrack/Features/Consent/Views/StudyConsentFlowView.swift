//
//  StudyConsentFlowView.swift
//  TinniTrack
//

import SwiftUI

struct StudyConsentFlowView: View {
    let definition: StudyConsentDefinition
    let onCompleted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StudyConsentFlowViewModel

    init(
        study: Study,
        definition: StudyConsentDefinition,
        consentService: ConsentServiceProtocol,
        onCompleted: @escaping () async -> Void
    ) {
        self.definition = definition
        self.onCompleted = onCompleted
        _viewModel = StateObject(wrappedValue: StudyConsentFlowViewModel(
            study: study,
            consentService: consentService
        ))
    }

    var body: some View {
        ZStack {
            ResearchKitTaskPresenterView(request: .studyConsent(definition)) { summary in
                Task {
                    await viewModel.handleResearchKitResult(summary)
                }
            }
            .ignoresSafeArea()

            if viewModel.state == .finalizing {
                StudyConsentFinalizingView()
            }
        }
        .task(id: viewModel.state) {
            switch viewModel.state {
            case .completed:
                await onCompleted()
                dismiss()
            case .dismissed:
                dismiss()
            case .reviewing, .finalizing, .failed:
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
                dismiss()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
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

#if DEBUG
#Preview {
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

private struct PreviewConsentService: ConsentServiceProtocol {
    func finalizeConsentAndEnroll(study: Study, consent: StudyConsentCompletion) async throws {}
}
#endif
