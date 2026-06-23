import Foundation

enum TinnitusThresholdResponse: String, Equatable {
    case heard
    case notHeard
}

struct TinnitusThresholdPresentation: Equatable {
    let index: Int
    let levelDBHL: Double
    let response: TinnitusThresholdResponse?
}

struct TinnitusThresholdStaircaseConfiguration: Equatable {
    let frequencyHz: Double
    let initialLevelDBHL: Double
    let minimumLevelDBHL: Double
    let maximumLevelDBHL: Double
    let stepDownDB: Double
    let stepUpDB: Double
    let requiredAscendingHitsAtLevel: Int

    static let studyAOneKilohertz = TinnitusThresholdStaircaseConfiguration(
        frequencyHz: 1_000,
        initialLevelDBHL: 30.0,
        minimumLevelDBHL: -10.0,
        maximumLevelDBHL: 100.0,
        stepDownDB: 10.0,
        stepUpDB: 5.0,
        requiredAscendingHitsAtLevel: 2
    )
}

struct TinnitusThresholdStaircase: Equatable {
    private(set) var configuration: TinnitusThresholdStaircaseConfiguration
    private(set) var currentLevelDBHL: Double
    private(set) var presentations: [TinnitusThresholdPresentation] = []
    private(set) var measuredThresholdDBHL: Double?

    private var hasMissedBelowCandidate = false
    private var ascendingHitCountsByLevel: [Double: Int] = [:]

    init(configuration: TinnitusThresholdStaircaseConfiguration = .studyAOneKilohertz) {
        self.configuration = configuration
        currentLevelDBHL = Self.clamp(
            configuration.initialLevelDBHL,
            minimum: configuration.minimumLevelDBHL,
            maximum: configuration.maximumLevelDBHL
        )
    }

    var isComplete: Bool {
        measuredThresholdDBHL != nil
    }

    mutating func recordResponse(_ response: TinnitusThresholdResponse) {
        guard measuredThresholdDBHL == nil else {
            return
        }

        presentations.append(TinnitusThresholdPresentation(
            index: presentations.count + 1,
            levelDBHL: currentLevelDBHL,
            response: response
        ))

        switch response {
        case .heard:
            if hasMissedBelowCandidate {
                let hits = (ascendingHitCountsByLevel[currentLevelDBHL] ?? 0) + 1
                ascendingHitCountsByLevel[currentLevelDBHL] = hits
                if hits >= configuration.requiredAscendingHitsAtLevel {
                    measuredThresholdDBHL = currentLevelDBHL
                    return
                }
            }
            currentLevelDBHL = Self.clamp(
                currentLevelDBHL - configuration.stepDownDB,
                minimum: configuration.minimumLevelDBHL,
                maximum: configuration.maximumLevelDBHL
            )

        case .notHeard:
            hasMissedBelowCandidate = true
            currentLevelDBHL = Self.clamp(
                currentLevelDBHL + configuration.stepUpDB,
                minimum: configuration.minimumLevelDBHL,
                maximum: configuration.maximumLevelDBHL
            )
        }
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}
