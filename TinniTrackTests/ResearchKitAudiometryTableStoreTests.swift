import Foundation
import Testing
@testable import TinniTrack

struct ResearchKitAudiometryTableStoreTests {
    @Test
    func compiledAirPodsPro2TablesMirrorPinnedResearchKitValuesAndManifest() throws {
        let tableSet = ResearchKitAudiometryTableStore.airPodsPro2
        let calibration = try #require(tableSet.frequencyCalibration(at: 1_000))

        #expect(tableSet.manifest.profileID == "ork-airpods-pro-2-1khz-v1")
        #expect(tableSet.manifest.headphoneType == "AIRPODSPROV2")
        #expect(tableSet.manifest.sourceCommit == "daba8c9f103477bd0279cc52a924a85b480df601")
        #expect(tableSet.manifest.retrievedAt == "2026-06-15")
        #expect(tableSet.manifest.files.count == 4)
        #expect(tableSet.manifest.files.contains(.init(
            name: "frequency_dBSPL_AIRPODSPROV2.plist",
            sha256: "3ffef0599ef4307def00636be337ac08a5511b183357ad692eb111c2f0ee5c0b"
        )))
        #expect(tableSet.manifest.files.contains(.init(
            name: "retspl_dBFS_AIRPODSPROV2.plist",
            sha256: "979ac2cc96afcdd1159e98549b4f4717bd0e1feaddc3cdc0994c5ed733c7240f"
        )))
        #expect(tableSet.frequencyDBSPL.count == 11)
        #expect(tableSet.retsplDBSPL.count == 11)
        #expect(tableSet.volumeCurve.count == 16)
        #expect(tableSet.retsplDBFS.count == 40)
        #expect(calibration.frequencyDBSPL == 83.67)
        #expect(calibration.retsplDBSPL == 9.27)
        #expect(calibration.retsplDBFS == -97)
        #expect(tableSet.volumeCurve[0.5] == -29)
    }

    @Test
    func calibrationProfileUsesVendoredTableSet() {
        let profile = CalibrationProfileCatalog.airPodsPro2OneKilohertz

        #expect(profile.version == "researchkit-daba8c9-2026-06-15")
        #expect(profile.sourceTableVersion == "ResearchKit/ResearchKit commit daba8c9f103477bd0279cc52a924a85b480df601, retrieved 2026-06-15")
        #expect(profile.sourceProvenance.contains("frequency_dBSPL_AIRPODSPROV2.plist"))
        #expect(profile.frequencyCalibration?.frequencyDBSPL == ResearchKitAudiometryTableStore.airPodsPro2.frequencyDBSPL[1_000])
        #expect(profile.frequencyCalibration?.retsplDBSPL == ResearchKitAudiometryTableStore.airPodsPro2.retsplDBSPL[1_000])
        #expect(profile.volumeCurve == ResearchKitAudiometryTableStore.airPodsPro2.volumeCurve)
    }
}
