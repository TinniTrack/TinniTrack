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
        #expect(StudyNo1Configuration.toneFrequencyHz == 1_000)
    }

    @Test
    func routeGateAllowsOnlyExplicitAirPodsProTwoAndThreeRoutes() {
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods Pro 2"))
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods Pro (2nd generation)"))
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods Pro 3"))
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods Pro (third generation)"))

        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods Pro") == false)
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("AirPods") == false)
        #expect(StudyNo1Configuration.isSupportedHeadphoneRouteName("iPhone") == false)
    }

    @Test
    func protocolMetadataKeepsPrototypeValidityExplicit() {
        let protocolDefinition = StudyProtocolCatalog.studyNo1

        #expect(protocolDefinition.version == "lm_v1")
        #expect(protocolDefinition.tasks.first?.stimulus?.frequencyHz == 1_000)
        #expect(protocolDefinition.tasks.first?.measurementUnit == .normalizedAmplitude)
        #expect(protocolDefinition.tasks.first?.outputDeviceRequirement.allowedDevices.map(\.displayName) == ["AirPods Pro 2", "AirPods Pro 3"])
        #expect(protocolDefinition.calibrationProfile.validationStatus == .unvalidatedPrototype)
        #expect(protocolDefinition.resultPayload.resultUnits == [.normalizedAmplitude, .estimatedDBA])
    }
}
