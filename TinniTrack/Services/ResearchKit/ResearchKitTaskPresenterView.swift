import SwiftUI
import UIKit

@MainActor
struct ResearchKitTaskPresenterView: UIViewControllerRepresentable {
    let request: ResearchKitTaskRequest
    let adapter: ResearchStudyTaskAdapting
    let completion: (ResearchKitTaskResultSummary) -> Void

    init(
        request: ResearchKitTaskRequest,
        adapter: ResearchStudyTaskAdapting,
        completion: @escaping (ResearchKitTaskResultSummary) -> Void
    ) {
        self.request = request
        self.adapter = adapter
        self.completion = completion
    }

    func makeUIViewController(context: Context) -> UIViewController {
        adapter.makeTaskViewController(for: request, completion: completion)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
