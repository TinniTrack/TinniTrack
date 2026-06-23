import Foundation

struct TinnitusEnvironmentSPLGateConfiguration: Equatable {
    let thresholdDBA: Double
    let requiredContiguousSamples: Int
    let samplingInterval: TimeInterval
    let maximumSamples: Int
    let sensitivityOffsetDB: Double?

    static let studyA = TinnitusEnvironmentSPLGateConfiguration(
        thresholdDBA: 45.0,
        requiredContiguousSamples: 5,
        samplingInterval: 1.0,
        maximumSamples: 12,
        sensitivityOffsetDB: nil
    )
}

struct TinnitusEnvironmentSPLGateResult: Equatable {
    let configuration: TinnitusEnvironmentSPLGateConfiguration
    let samplesDBA: [Double]
    let gateResult: Phase6GateResult

    var passed: Bool {
        gateResult == .passed
    }

    var phase6Context: Phase6EnvironmentSPLContext {
        Phase6EnvironmentSPLContext(
            thresholdDBA: configuration.thresholdDBA,
            requiredContiguousSamples: configuration.requiredContiguousSamples,
            samplingInterval: configuration.samplingInterval,
            sensitivityOffsetDB: configuration.sensitivityOffsetDB,
            samplesDBA: samplesDBA,
            gateResult: gateResult
        )
    }
}

enum TinnitusEnvironmentSPLGateStatus: Equatable {
    case measuring
    case tooLoud
    case passed
}

struct TinnitusEnvironmentSPLGateUpdate: Equatable {
    let samplesDBA: [Double]
    let latestSampleDBA: Double?
    let contiguousPassingSamples: Int
    let status: TinnitusEnvironmentSPLGateStatus
    let result: TinnitusEnvironmentSPLGateResult?

    var passed: Bool {
        result?.passed == true
    }
}

struct TinnitusEnvironmentSPLGateEvaluator {
    func evaluate(
        samplesDBA: [Double],
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyA
    ) -> TinnitusEnvironmentSPLGateResult {
        let finiteSamples = samplesDBA.filter(\.isFinite)
        var contiguous = 0
        var passed = false

        for sample in finiteSamples {
            if sample < configuration.thresholdDBA {
                contiguous += 1
                if contiguous >= configuration.requiredContiguousSamples {
                    passed = true
                    break
                }
            } else {
                contiguous = 0
            }
        }

        return TinnitusEnvironmentSPLGateResult(
            configuration: configuration,
            samplesDBA: finiteSamples,
            gateResult: passed ? .passed : .failed
        )
    }

    func update(
        samplesDBA: [Double],
        configuration: TinnitusEnvironmentSPLGateConfiguration = .studyA
    ) -> TinnitusEnvironmentSPLGateUpdate {
        let finiteSamples = samplesDBA.filter(\.isFinite)
        var contiguous = 0

        for sample in finiteSamples {
            if sample < configuration.thresholdDBA {
                contiguous += 1
            } else {
                contiguous = 0
            }
        }

        let result: TinnitusEnvironmentSPLGateResult?
        let status: TinnitusEnvironmentSPLGateStatus
        if contiguous >= configuration.requiredContiguousSamples {
            result = TinnitusEnvironmentSPLGateResult(
                configuration: configuration,
                samplesDBA: finiteSamples,
                gateResult: .passed
            )
            status = .passed
        } else if let latest = finiteSamples.last, latest >= configuration.thresholdDBA {
            result = nil
            status = .tooLoud
        } else {
            result = nil
            status = .measuring
        }

        return TinnitusEnvironmentSPLGateUpdate(
            samplesDBA: finiteSamples,
            latestSampleDBA: finiteSamples.last,
            contiguousPassingSamples: contiguous,
            status: status,
            result: result
        )
    }
}
