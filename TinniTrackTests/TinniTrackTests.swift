//
//  TinniTrackTests.swift
//  TinniTrackTests
//
//  Created by Basil Shevtsov on 12/4/25.
//

import Foundation
import Testing
@testable import TinniTrack

struct TinniTrackTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test
    func profileAgeIsDerivedFromDateOfBirth() {
        let calendar = Calendar(identifier: .gregorian)
        let dateOfBirth = calendar.date(from: DateComponents(year: 1990, month: 6, day: 14))!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let profile = Profile(
            id: UUID(),
            participantID: 1001,
            firstName: "Taylor",
            lastName: "Rivers",
            dateOfBirth: dateOfBirth,
            timezone: nil,
            createdAt: nil,
            onboardingCompletedAt: Date()
        )

        #expect(profile.age(asOf: asOf, calendar: calendar) == 35)
    }

}
