import Foundation

struct ResearchKitAudiometryManifest: Decodable, Equatable {
    struct FileEntry: Decodable, Equatable {
        let name: String
        let sha256: String
    }

    let profileID: String
    let headphoneType: String
    let sourceRepository: String
    let sourceCommit: String
    let sourcePath: String
    let sourceTreeURL: String
    let retrievedAt: String
    let notes: String
    let files: [FileEntry]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case headphoneType = "headphone_type"
        case sourceRepository = "source_repository"
        case sourceCommit = "source_commit"
        case sourcePath = "source_path"
        case sourceTreeURL = "source_tree_url"
        case retrievedAt = "retrieved_at"
        case notes
        case files
    }
}

struct ResearchKitAudiometryTableSet: Equatable {
    let manifest: ResearchKitAudiometryManifest
    let frequencyDBSPL: [Double: Double]
    let volumeCurve: [Double: Double]
    let retsplDBSPL: [Double: Double]
    let retsplDBFS: [Double: Double]

    func frequencyCalibration(at frequencyHz: Double) -> HeadphoneFrequencyCalibration? {
        guard let frequencyDBSPL = value(in: self.frequencyDBSPL, at: frequencyHz),
              let retsplDBSPL = value(in: self.retsplDBSPL, at: frequencyHz) else {
            return nil
        }

        return HeadphoneFrequencyCalibration(
            frequencyHz: frequencyHz,
            frequencyDBSPL: frequencyDBSPL,
            retsplDBSPL: retsplDBSPL,
            retsplDBFS: value(in: retsplDBFS, at: frequencyHz)
        )
    }

    private func value(in table: [Double: Double], at key: Double) -> Double? {
        if let exact = table[key] {
            return exact
        }

        return table.first { candidate, _ in
            abs(candidate - key) < 0.001
        }?.value
    }
}

enum ResearchKitAudiometryTableStore {
    enum TableLoadError: Error, Equatable {
        case missingResource(String)
        case invalidPlist(String)
        case invalidNumber(file: String, key: String, value: String)
    }

    static let airPodsPro2ManifestResourcePath = "ORKAudiometry/AIRPODSPROV2/manifest"

    static let airPodsPro2 = makeEmbeddedAirPodsPro2()

    static func loadAirPodsPro2(bundle: Bundle = Bundle(for: ResearchKitAudiometryResourceBundleToken.self)) throws -> ResearchKitAudiometryTableSet {
        let base = "ORKAudiometry/AIRPODSPROV2"
        return ResearchKitAudiometryTableSet(
            manifest: try loadManifest(named: "manifest", subdirectory: base, bundle: bundle),
            frequencyDBSPL: try loadPlistTable(named: "frequency_dBSPL_AIRPODSPROV2", subdirectory: base, bundle: bundle),
            volumeCurve: try loadPlistTable(named: "volume_curve_AIRPODSPROV2", subdirectory: base, bundle: bundle),
            retsplDBSPL: try loadPlistTable(named: "retspl_AIRPODSPROV2", subdirectory: base, bundle: bundle),
            retsplDBFS: try loadPlistTable(named: "retspl_dBFS_AIRPODSPROV2", subdirectory: base, bundle: bundle)
        )
    }

    private static func loadManifest(named name: String, subdirectory: String, bundle: Bundle) throws -> ResearchKitAudiometryManifest {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            throw TableLoadError.missingResource("\(subdirectory)/\(name).json")
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ResearchKitAudiometryManifest.self, from: data)
    }

    private static func loadPlistTable(
        named name: String,
        subdirectory: String,
        bundle: Bundle
    ) throws -> [Double: Double] {
        guard let url = bundle.url(forResource: name, withExtension: "plist", subdirectory: subdirectory) else {
            throw TableLoadError.missingResource("\(subdirectory)/\(name).plist")
        }

        let data = try Data(contentsOf: url)
        guard let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            throw TableLoadError.invalidPlist("\(subdirectory)/\(name).plist")
        }

        return try raw.reduce(into: [Double: Double]()) { result, pair in
            guard let key = Double(pair.key), let value = Double(pair.value) else {
                throw TableLoadError.invalidNumber(file: name, key: pair.key, value: pair.value)
            }
            result[key] = value
        }
    }

    // Compiled mirror of the vendored plist files so calibration stays available in app and
    // test bundles even if Xcode resource-copy settings change.
    private static func makeEmbeddedAirPodsPro2() -> ResearchKitAudiometryTableSet {
        ResearchKitAudiometryTableSet(
            manifest: ResearchKitAudiometryManifest(
                profileID: "ork-airpods-pro-2-1khz-v1",
                headphoneType: "AIRPODSPROV2",
                sourceRepository: "https://github.com/ResearchKit/ResearchKit",
                sourceCommit: "daba8c9f103477bd0279cc52a924a85b480df601",
                sourcePath: "ResearchKitActiveTask/dBHL Tone Audiometry/ORKAudiometry",
                sourceTreeURL: "https://github.com/ResearchKit/ResearchKit/tree/daba8c9f103477bd0279cc52a924a85b480df601/ResearchKitActiveTask/dBHL%20Tone%20Audiometry/ORKAudiometry",
                retrievedAt: "2026-06-15",
                notes: "Pinned local copies of official ResearchKit ORKAudiometry AirPods Pro 2 tables used for Study No. 1 1,000 Hz loudness-match derivations.",
                files: [
                    .init(name: "frequency_dBSPL_AIRPODSPROV2.plist", sha256: "3ffef0599ef4307def00636be337ac08a5511b183357ad692eb111c2f0ee5c0b"),
                    .init(name: "volume_curve_AIRPODSPROV2.plist", sha256: "2acbc3ef3e4f4ea3bde15c2a757262c4261b6a1234a3752bd118173f4ec0fb1b"),
                    .init(name: "retspl_AIRPODSPROV2.plist", sha256: "75d47cf85b72f1b0efb95cf570f5a954733cb5e6c975848d3fa17e075eb4b4d2"),
                    .init(name: "retspl_dBFS_AIRPODSPROV2.plist", sha256: "979ac2cc96afcdd1159e98549b4f4717bd0e1feaddc3cdc0994c5ed733c7240f")
                ]
            ),
            frequencyDBSPL: [
                125: 84.05,
                250: 83.16,
                500: 84.13,
                750: 83.95,
                1_000: 83.67,
                1_500: 84.79,
                2_000: 86.52,
                3_000: 89.24,
                4_000: 86.64,
                6_000: 86.50,
                8_000: 90.11
            ],
            volumeCurve: [
                0.0625: -65.5,
                0.125: -58.5,
                0.1875: -52.5,
                0.25: -47,
                0.3125: -42,
                0.375: -37.5,
                0.4375: -33,
                0.5: -29,
                0.5625: -25,
                0.625: -21,
                0.6875: -17,
                0.75: -13.5,
                0.8125: -10,
                0.875: -6.5,
                0.9375: -3,
                1: 0
            ],
            retsplDBSPL: [
                125: 34.04,
                250: 23.52,
                500: 12.99,
                750: 11.13,
                1_000: 9.27,
                1_500: 11.69,
                2_000: 14.11,
                3_000: 13.42,
                4_000: 12.72,
                6_000: 14.62,
                8_000: 16.51
            ],
            retsplDBFS: [
                250: -85,
                306.0092: -87.4644,
                364.2145: -90.0254,
                425.0334: -92.7014,
                488.9024: -95.5117,
                500: -96,
                556.2799: -96.1125,
                627.6493: -96.2552,
                703.5228: -96.4070,
                784.4448: -96.5688,
                870.9962: -96.7419,
                963.7980: -96.9275,
                1_000: -97,
                1_063.5161: -96.8729,
                1_170.8662: -96.6582,
                1_286.6186: -96.4267,
                1_411.6040: -96.1767,
                1_546.7192: -95.9065,
                1_692.9339: -95.6141,
                1_851.2974: -95.2974,
                2_000: -95,
                2_022.9461: -95.0688,
                2_209.1117: -95.6273,
                2_411.1302: -96.2333,
                2_630.4514: -96.8913,
                2_868.6490: -97.6059,
                3_127.4325: -97.6177,
                3_408.6590: -96.7740,
                3_714.3464: -95.8569,
                4_000: -95,
                4_046.6886: -94.9066,
                4_408.0704: -94.1838,
                4_801.0852: -93.3978,
                5_228.5533: -92.5428,
                5_693.5422: -91.6129,
                6_000: -91,
                6_199.3889: -90.8006,
                6_749.7233: -90.2502,
                7_348.4947: -89.6515,
                8_000: -89
            ]
        )
    }
}

private final class ResearchKitAudiometryResourceBundleToken {}
