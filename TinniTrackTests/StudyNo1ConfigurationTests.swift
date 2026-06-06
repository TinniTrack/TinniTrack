import Foundation
import Testing
@testable import TinniTrack

struct StudyNo1ConfigurationTests {
    @Test
    func firstScheduleLocalDateUsesSameDayBeforeNineAM() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 8, minute: 30))!
        let startDate = StudyNo1Configuration.firstScheduleLocalDate(now: now, timeZone: tz, calendar: calendar)

        let expected = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 0))!
        #expect(startDate == expected)
    }

    @Test
    func firstScheduleLocalDateUsesNextDayAfterNineAM() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 9, minute: 1))!
        let startDate = StudyNo1Configuration.firstScheduleLocalDate(now: now, timeZone: tz, calendar: calendar)

        let expected = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 0, minute: 0))!
        #expect(startDate == expected)
    }

    @Test
    func taskConstantsMatchV1Protocol() {
        #expect(StudyNo1Configuration.slotHours == [9, 13, 17, 21])
        #expect(StudyNo1Configuration.windowMinutes == 60)
        #expect(StudyNo1Configuration.ambientThresholdDB == 45)
    }
}
