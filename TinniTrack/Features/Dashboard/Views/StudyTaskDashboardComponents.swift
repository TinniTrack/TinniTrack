import SwiftUI

struct FutureStudyTaskRow: View {
    let task: ScheduledTask
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day \(task.dayIndex + 1), Slot \(task.slotIndex + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(Self.windowFormatter.string(from: task.windowStart) + " - " + Self.timeFormatter.string(from: task.windowEnd))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: onStart) {
                Text("Start Task")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
            .accessibilityIdentifier("study_start_loudness_task_button")

            if !canStart {
                Text(startAvailabilityMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var startAvailabilityMessage: String {
        let now = Date()
        if now < task.windowStart {
            return "Available at \(Self.windowFormatter.string(from: task.windowStart))."
        }

        if now > task.windowEnd {
            return "This task window has ended."
        }

        return "This task is temporarily unavailable."
    }

    private static let windowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct CompletedStudyTaskRow: View {
    let task: ScheduledTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Day \(task.dayIndex + 1), Slot \(task.slotIndex + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let completedAt = task.completedAt {
                Text("Completed \(Self.dateFormatter.string(from: completedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Completed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ReadySyncWarningCard: View {
    let warning: StudyTaskDashboardViewModel.ReadySyncWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var title: String {
        switch warning {
        case .permissionDenied:
            return "Health Access Needed for Sync"
        case .noAudiogramInHealth:
            return "No New Hearing Test Found"
        case .error:
            return "Unable to Sync from Health"
        }
    }

    private var message: String {
        switch warning {
        case .permissionDenied:
            return "Tasks remain available, but we could not read hearing-test data. Re-enable Health access and tap Sync from Health again."
        case .noAudiogramInHealth:
            return "We can access your health data, but we are not seeing a hearing test yet."
        case .error(let message):
            return message
        }
    }
}
