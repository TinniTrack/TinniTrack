import Foundation

enum AcousticValidationRecordExportError: Error, Equatable {
    case invalidUTF8
}

struct AcousticValidationRecordPackage: Codable, Equatable {
    let record: AcousticValidationRunRecord
    let evaluation: AcousticValidationEvaluation
    let exportedAt: Date
}

struct AcousticValidationRecordExporter {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateProvider: () -> Date

    init(
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.encoder = encoder ?? Self.makeEncoder()
        self.decoder = decoder ?? Self.makeDecoder()
        self.dateProvider = dateProvider
    }

    func package(
        record: AcousticValidationRunRecord,
        evaluation: AcousticValidationEvaluation
    ) -> AcousticValidationRecordPackage {
        AcousticValidationRecordPackage(
            record: record,
            evaluation: evaluation,
            exportedAt: dateProvider()
        )
    }

    func exportData(
        record: AcousticValidationRunRecord,
        evaluation: AcousticValidationEvaluation
    ) throws -> Data {
        try encoder.encode(package(record: record, evaluation: evaluation))
    }

    func exportJSONString(
        record: AcousticValidationRunRecord,
        evaluation: AcousticValidationEvaluation
    ) throws -> String {
        let data = try exportData(record: record, evaluation: evaluation)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AcousticValidationRecordExportError.invalidUTF8
        }
        return string
    }

    func decodePackage(from data: Data) throws -> AcousticValidationRecordPackage {
        try decoder.decode(AcousticValidationRecordPackage.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
