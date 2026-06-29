import Foundation
import Testing
import UIKit
@testable import TinniTrack

struct ConsentArtifactGeneratorTests {
    @Test
    func signedConsentPdfUsesStructuredDefinitionAndHashes() throws {
        let generator = ConsentArtifactGenerator()
        let signatureData = try Self.signatureImageData()

        let artifact = try generator.generateSignedConsentArtifact(
            definition: StudyConsentCatalog.studyNo1,
            signerGivenName: "Taylor",
            signerFamilyName: "Rivers",
            signedAt: Date(timeIntervalSince1970: 1_750_000_000),
            signatureImageData: signatureData
        )

        #expect(artifact.pdfData.starts(with: Data("%PDF".utf8)))
        #expect(artifact.pdfSHA256Hex.count == 64)
        #expect(artifact.storageBucket == StudyConsentCatalog.consentStorageBucket)
        #expect(artifact.storagePath.isEmpty)
        #expect(generator.sha256Hex(for: signatureData).count == 64)
    }

    private static func signatureImageData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 90))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 90))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(3)
            context.cgContext.move(to: CGPoint(x: 24, y: 60))
            context.cgContext.addCurve(
                to: CGPoint(x: 210, y: 48),
                control1: CGPoint(x: 70, y: 15),
                control2: CGPoint(x: 130, y: 80)
            )
            context.cgContext.strokePath()
        }

        guard let data = image.pngData() else {
            throw ConsentArtifactGeneratorError.invalidSignatureImage
        }
        return data
    }
}
