import Foundation

enum StudyNo1Configuration {
    static let slotHours: [Int] = [9, 13, 17, 21]
    static let windowMinutes: Int = 60
    static let ambientThresholdDB: Double = 45
    static let toneFrequencyHz: Double = 1_000
    static let outputVolumeChangeTolerance: Double = 0.005

    static func isSupportedHeadphoneRouteName(_ routeName: String) -> Bool {
        let normalized = routeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("airpods pro") else { return false }

        let secondGenerationMarkers = [
            "airpods pro 2",
            "airpods pro (2",
            "2nd generation",
            "second generation"
        ]
        let thirdGenerationMarkers = [
            "airpods pro 3",
            "airpods pro (3",
            "3rd generation",
            "third generation"
        ]

        return (secondGenerationMarkers + thirdGenerationMarkers).contains { normalized.contains($0) }
    }

    static func firstScheduleLocalDate(
        now: Date,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var localizedCalendar = calendar
        localizedCalendar.timeZone = timeZone

        let localHour = localizedCalendar.component(.hour, from: now)
        let localMinute = localizedCalendar.component(.minute, from: now)
        let startDayOffset = (localHour > 9 || (localHour == 9 && localMinute > 0)) ? 1 : 0

        let localStartOfDay = localizedCalendar.startOfDay(for: now)
        return localizedCalendar.date(byAdding: .day, value: startDayOffset, to: localStartOfDay) ?? localStartOfDay
    }
}
