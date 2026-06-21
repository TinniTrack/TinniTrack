import SwiftUI

struct LoudnessMatchTaskFlowView: View {
    let scheduledTask: ScheduledTask
    let enrollment: StudyEnrollment
    let studyService: StudyServiceProtocol
    let onSubmitted: () -> Void

    var body: some View {
        ContentUnavailableView(
            "Loudness Match Unavailable",
            systemImage: "waveform",
            description: Text("Calibrated loudness matching is disabled while the calibrated audio pipeline is being rebuilt.")
        )
        .navigationTitle("Loudness Match")
        .navigationBarTitleDisplayMode(.inline)
    }
}
