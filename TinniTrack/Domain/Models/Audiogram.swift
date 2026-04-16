//
//  Audiogram.swift
//  TinniTrack
//

import Foundation

struct AudiogramRecord: Identifiable, Equatable {
    let id: UUID
    let measuredAt: Date
    let source: String
    let headphoneName: String?
    let healthKitSampleUUID: UUID?
    let points: [AudiogramPoint]
}

struct AudiogramPoint: Codable, Equatable {
    let frequencyHz: Double
    let leftEarDBHL: Double?
    let rightEarDBHL: Double?
    let tests: [AudiogramSensitivityTest]

    enum CodingKeys: String, CodingKey {
        case frequencyHz = "frequency_hz"
        case leftEarDBHL = "left_db_hl"
        case rightEarDBHL = "right_db_hl"
        case tests
    }
}

struct AudiogramSensitivityTest: Codable, Equatable {
    enum Side: String, Codable, Equatable {
        case left
        case right
        case unknown
    }

    let side: Side
    let conduction: String?
    let masked: Bool?
    let sensitivityDBHL: Double

    enum CodingKeys: String, CodingKey {
        case side
        case conduction
        case masked
        case sensitivityDBHL = "sensitivity_db_hl"
    }
}

enum AudiogramPrerequisiteState: Equatable {
    case met(latestMeasuredAt: Date?)
    case needsPermission
    case permissionDenied
    case noAudiogramInHealth
    case error(message: String)
}

enum AudiogramImportResult: Equatable {
    case imported(newRecords: Int, latestMeasuredAt: Date?)
    case noNewRecords(latestMeasuredAt: Date?)
    case noAudiogramInHealth
}
