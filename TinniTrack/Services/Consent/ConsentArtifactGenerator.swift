//
//  ConsentArtifactGenerator.swift
//  TinniTrack
//

import CryptoKit
import Foundation
import UIKit

protocol ConsentArtifactGenerating {
    func generateSignedConsentArtifact(
        definition: StudyConsentDefinition,
        signerGivenName: String,
        signerFamilyName: String,
        signedAt: Date,
        signatureImageData: Data
    ) throws -> StudyConsentArtifact

    func sha256Hex(for data: Data) -> String
}

enum ConsentArtifactGeneratorError: LocalizedError, Equatable {
    case invalidSignatureImage

    var errorDescription: String? {
        switch self {
        case .invalidSignatureImage:
            return "Signature image could not be rendered."
        }
    }
}

struct ConsentArtifactGenerator: ConsentArtifactGenerating {
    nonisolated init() {}

    func generateSignedConsentArtifact(
        definition: StudyConsentDefinition,
        signerGivenName: String,
        signerFamilyName: String,
        signedAt: Date,
        signatureImageData: Data
    ) throws -> StudyConsentArtifact {
        guard let signatureImage = UIImage(data: signatureImageData) else {
            throw ConsentArtifactGeneratorError.invalidSignatureImage
        }

        let pdfData = makePDFData(
            definition: definition,
            signerGivenName: signerGivenName,
            signerFamilyName: signerFamilyName,
            signedAt: signedAt,
            signatureImage: signatureImage,
            signatureImageSHA256Hex: sha256Hex(for: signatureImageData)
        )

        return StudyConsentArtifact(
            pdfData: pdfData,
            pdfSHA256Hex: sha256Hex(for: pdfData),
            storageBucket: StudyConsentCatalog.consentStorageBucket,
            storagePath: ""
        )
    }

    func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func makePDFData(
        definition: StudyConsentDefinition,
        signerGivenName: String,
        signerFamilyName: String,
        signedAt: Date,
        signatureImage: UIImage,
        signatureImageSHA256Hex: String
    ) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 54
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let dateText = Self.signedDateFormatter.string(from: signedAt)

        return renderer.pdfData { context in
            var cursor = PDFCursor(
                pageSize: pageSize,
                margin: margin,
                startNewPage: { context.beginPage() }
            )
            cursor.beginPage()
            cursor.drawTitle(definition.documentTitle)
            cursor.drawMetadata("Study Title: Loudness Match")
            cursor.drawMetadata(definition.principalInvestigator.displayText)
            cursor.drawMetadata("Consent Version: \(definition.consentVersion)")
            cursor.drawMetadata("Content SHA-256: \(definition.contentSHA256Hex)")

            cursor.drawSectionTitle(definition.keyInformation.title)
            for item in definition.keyInformation.bulletItems + definition.keyInformation.checkItems {
                cursor.drawBullet(item)
            }

            for section in definition.sections {
                cursor.drawSectionTitle(section.title)
                for block in section.blocks {
                    cursor.drawBlock(block)
                }
            }

            cursor.drawSectionTitle("Signed consent")
            cursor.drawParagraph(definition.attestation.text)
            cursor.drawMetadata("Participant: \(signerGivenName) \(signerFamilyName)")
            cursor.drawMetadata("Signed: \(dateText)")
            cursor.drawMetadata("Signature Image SHA-256: \(signatureImageSHA256Hex)")
            cursor.drawSignature(signatureImage)
        }
    }

    private static let signedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct PDFCursor {
    let pageSize: CGSize
    let margin: CGFloat
    let startNewPage: () -> Void
    var y: CGFloat

    init(pageSize: CGSize, margin: CGFloat, startNewPage: @escaping () -> Void) {
        self.pageSize = pageSize
        self.margin = margin
        self.startNewPage = startNewPage
        self.y = margin
    }

    mutating func beginPage() {
        startNewPage()
        y = margin
    }

    mutating func ensureSpace(_ height: CGFloat) {
        if y + height > pageSize.height - margin {
            startNewPage()
            y = margin
        }
    }

    mutating func drawTitle(_ text: String) {
        drawText(text, font: .boldSystemFont(ofSize: 21), color: .label, spacingAfter: 14)
    }

    mutating func drawSectionTitle(_ text: String) {
        y += 10
        drawText(text, font: .boldSystemFont(ofSize: 15), color: .label, spacingAfter: 8)
    }

    mutating func drawMetadata(_ text: String) {
        drawText(text, font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 7)
    }

    mutating func drawParagraph(_ text: String) {
        drawText(text, font: .systemFont(ofSize: 11), color: .label, spacingAfter: 8)
    }

    mutating func drawBullet(_ text: String) {
        drawText("- \(text)", font: .systemFont(ofSize: 11), color: .label, indent: 14, spacingAfter: 5)
    }

    mutating func drawBlock(_ block: StudyConsentContentBlock) {
        switch block {
        case .paragraph(let text):
            drawParagraph(text)
        case .bullets(let items):
            for item in items {
                drawBullet(item)
            }
        case .numberedActivities(let activities):
            for activity in activities {
                drawText(
                    "\(activity.index). \(activity.title)",
                    font: .boldSystemFont(ofSize: 11),
                    color: .label,
                    spacingAfter: 4
                )
                drawParagraph(activity.body)
                for item in activity.bullets {
                    drawBullet(item)
                }
            }
        case .scheduleChips(let times):
            drawText("Schedule: \(times.joined(separator: "  "))", font: .boldSystemFont(ofSize: 11), color: .label, spacingAfter: 8)
        case .callout(let title, let body):
            drawText(title, font: .boldSystemFont(ofSize: 11), color: .label, spacingAfter: 3)
            drawParagraph(body)
        case .contacts(let contacts):
            for contact in contacts {
                drawParagraph(contact.displayText)
            }
        }
    }

    mutating func drawSignature(_ image: UIImage) {
        let width = pageSize.width - margin * 2
        let height: CGFloat = 98
        ensureSpace(height + 18)
        let rect = CGRect(x: margin, y: y, width: width, height: height)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        UIColor.separator.setStroke()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).stroke()

        let imageRect = CGRect(x: rect.minX + 16, y: rect.minY + 10, width: rect.width - 32, height: rect.height - 24)
        image.draw(in: imageRect)
        y += height + 18
    }

    private mutating func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        indent: CGFloat = 0,
        spacingAfter: CGFloat
    ) {
        let width = pageSize.width - margin * 2 - indent
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(bounding.height)
        ensureSpace(height + spacingAfter)
        attributed.draw(in: CGRect(x: margin + indent, y: y, width: width, height: height))
        y += height + spacingAfter
    }
}
