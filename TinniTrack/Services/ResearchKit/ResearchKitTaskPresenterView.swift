import SwiftUI
import UIKit

@MainActor
struct ResearchKitTaskPresenterView: UIViewControllerRepresentable {
    let request: ResearchKitTaskRequest
    private let adapter: ResearchStudyTaskAdapting?
    let completion: (ResearchKitTaskResultSummary) -> Void

    init(
        request: ResearchKitTaskRequest,
        adapter: ResearchStudyTaskAdapting? = nil,
        completion: @escaping (ResearchKitTaskResultSummary) -> Void
    ) {
        self.request = request
        self.adapter = adapter
        self.completion = completion
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            adapter: adapter ?? ResearchKitStudyTaskAdapter(),
            completion: completion
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.adapter.makeTaskViewController(for: request) { [weak coordinator = context.coordinator] summary in
            coordinator?.completion(summary)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.completion = completion
    }

    final class Coordinator {
        let adapter: ResearchStudyTaskAdapting
        var completion: (ResearchKitTaskResultSummary) -> Void

        init(
            adapter: ResearchStudyTaskAdapting,
            completion: @escaping (ResearchKitTaskResultSummary) -> Void
        ) {
            self.adapter = adapter
            self.completion = completion
        }
    }
}
