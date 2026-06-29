import Foundation

enum StudyNo1Configuration {
    static let slotHours: [Int] = [8, 12, 16, 20]
    static let windowMinutes: Int = 60
    static let ambientThresholdDB: Double = 45

    static func firstScheduleLocalDate(
        now: Date,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var localizedCalendar = calendar
        localizedCalendar.timeZone = timeZone

        let localHour = localizedCalendar.component(.hour, from: now)
        let localMinute = localizedCalendar.component(.minute, from: now)
        let firstSlotHour = slotHours.first ?? 8
        let startDayOffset = (localHour > firstSlotHour || (localHour == firstSlotHour && localMinute > 0)) ? 1 : 0

        let localStartOfDay = localizedCalendar.startOfDay(for: now)
        return localizedCalendar.date(byAdding: .day, value: startDayOffset, to: localStartOfDay) ?? localStartOfDay
    }
}
