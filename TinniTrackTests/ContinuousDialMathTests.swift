import Foundation
import CoreGraphics
import Testing
@testable import TinniTrack

struct ContinuousDialMathTests {
    @Test
    func clockwiseDeltaIncreasesValue() {
        let updated = ContinuousDialMath.nextValue(currentValue: 0.5, deltaDegrees: 45)
        #expect(updated > 0.5)
    }

    @Test
    func counterClockwiseDeltaDecreasesValue() {
        let updated = ContinuousDialMath.nextValue(currentValue: 0.5, deltaDegrees: -45)
        #expect(updated < 0.5)
    }

    @Test
    func wrappedDeltaAcrossSeamDoesNotJump() {
        let clockwiseAcrossSeam = ContinuousDialMath.wrappedDeltaDegrees(from: 179, to: -179)
        let counterAcrossSeam = ContinuousDialMath.wrappedDeltaDegrees(from: -179, to: 179)

        #expect(abs(clockwiseAcrossSeam - 2) < 0.000_1)
        #expect(abs(counterAcrossSeam + 2) < 0.000_1)
    }

    @Test
    func maxValueIgnoresClockwiseIncrease() {
        let updated = ContinuousDialMath.nextValue(currentValue: 1.0, deltaDegrees: 30)
        #expect(updated == 1.0)
    }

    @Test
    func maxValueAllowsCounterClockwiseDecrease() {
        let updated = ContinuousDialMath.nextValue(currentValue: 1.0, deltaDegrees: -30)
        #expect(updated < 1.0)
    }

    @Test
    func minValueIgnoresCounterClockwiseDecrease() {
        let updated = ContinuousDialMath.nextValue(currentValue: 0.0, deltaDegrees: -30)
        #expect(updated == 0.0)
    }

    @Test
    func minValueAllowsClockwiseIncrease() {
        let updated = ContinuousDialMath.nextValue(currentValue: 0.0, deltaDegrees: 30)
        #expect(updated > 0.0)
    }

    @Test
    func threeClockwiseTurnsMoveFromMinToMax() {
        let updated = ContinuousDialMath.nextValue(
            currentValue: 0.0,
            deltaDegrees: 360 * ContinuousDialMath.turnsForFullScale
        )
        #expect(abs(updated - 1.0) < 0.000_1)
    }
}
