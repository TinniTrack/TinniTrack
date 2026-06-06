import Foundation

enum StudyNo1Configuration {
    static let slotHours: [Int] = [9, 13, 17, 21]
    static let windowMinutes: Int = 60
    static let ambientThresholdDB: Double = 45

    static func isSupportedHeadphoneRouteName(_ routeName: String) -> Bool {
        let normalized = routeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("airpods pro")
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
