import SwiftUI

struct ContinuousDialMath {
    static let turnsForFullScale: Double = 3
    static let degreesForFullScale: Double = 360 * turnsForFullScale

    static func angle(for location: CGPoint, center: CGPoint) -> Double {
        let deltaX = location.x - center.x
        let deltaY = location.y - center.y
        var degrees = atan2(deltaY, deltaX) * 180 / .pi + 90
        if degrees < -180 {
            degrees += 360
        }
        if degrees > 180 {
            degrees -= 360
        }
        return degrees
    }

    static func wrappedDeltaDegrees(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 {
            delta -= 360
        }
        if delta < -180 {
            delta += 360
        }
        return delta
    }

    static func nextValue(currentValue: Double, deltaDegrees: Double) -> Double {
        let clampedCurrent = min(max(currentValue, 0), 1)
        let deltaValue = deltaDegrees / degreesForFullScale

        if clampedCurrent >= 1 && deltaValue > 0 {
            return 1
        }
        if clampedCurrent <= 0 && deltaValue < 0 {
            return 0
        }

        return min(max(clampedCurrent + deltaValue, 0), 1)
    }

    static func markerRotationDegrees(for value: Double) -> Double {
        min(max(value, 0), 1) * degreesForFullScale
    }
}

struct CircularDial: View {
    @Binding var value: Double
    let isEnabled: Bool

    @State private var lastAngleDegrees: Double?

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size * 0.36
            let ringWidth: CGFloat = 16
            let markerLength = radius * 0.36

            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: ringWidth)
                    .frame(width: radius * 2, height: radius * 2)

                Capsule()
                    .fill(isEnabled ? Color.blue : Color.gray.opacity(0.7))
                    .frame(width: 8, height: markerLength)
                    .offset(y: -(radius - ringWidth))
                    .rotationEffect(.degrees(ContinuousDialMath.markerRotationDegrees(for: value)))

                Circle()
                    .fill(isEnabled ? Color.white : Color(uiColor: .systemGray5))
                    .frame(width: radius * 1.3, height: radius * 1.3)

                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .fill(isEnabled ? Color.blue : Color.gray)
                    .frame(width: 18, height: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        guard isEnabled else { return }

                        let center = CGPoint(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                        let currentAngle = ContinuousDialMath.angle(
                            for: gestureValue.location,
                            center: center
                        )

                        guard let lastAngleDegrees else {
                            self.lastAngleDegrees = currentAngle
                            return
                        }

                        let deltaDegrees = ContinuousDialMath.wrappedDeltaDegrees(
                            from: lastAngleDegrees,
                            to: currentAngle
                        )
                        value = ContinuousDialMath.nextValue(
                            currentValue: value,
                            deltaDegrees: deltaDegrees
                        )
                        self.lastAngleDegrees = currentAngle
                    }
                    .onEnded { _ in
                        lastAngleDegrees = nil
                    }
            )
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    lastAngleDegrees = nil
                }
            }
        }
    }
}
