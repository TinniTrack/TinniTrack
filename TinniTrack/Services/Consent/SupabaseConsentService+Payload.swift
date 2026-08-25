//
//  SupabaseConsentService+Payload.swift
//  TinniTrack
//

import CryptoKit
import Foundation

extension SupabaseConsentService {
    static func validatedArtifact(
        for consent: StudyConsentCompletion,
        study: Study,
        definition: StudyConsentDefinition
    ) throws -> StudyConsentArtifact {
        guard consent.studySlug == definition.studySlug,
              consent.consentVersion == definition.consentVersion,
              study.slug == definition.studySlug else {
            throw ConsentServiceError.studyMismatch
        }

        guard consent.isValidSignedConsent,
              consent.consentContentSHA256Hex == definition.contentSHA256Hex,
              consent.attestationText == definition.attestation.text,
              consent.attestationVersion == definition.attestation.version else {
            throw ConsentServiceError.invalidConsentCompletion
        }

        guard let artifact = consent.artifact else {
            throw ConsentServiceError.missingSignedArtifact
        }
        guard artifact.storageBucket == StudyConsentCatalog.consentStorageBucket,
              sha256Hex(for: artifact.pdfData) == artifact.pdfSHA256Hex else {
            throw ConsentServiceError.invalidConsentCompletion
        }
        return artifact
    }

    /// A deterministic UUIDv8 makes every retry for one user/study/version use
    /// the same immutable Storage path without exposing additional user data.
    static func consentID(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) -> UUID {
        PendingConsentKey(
            userID: userID,
            studyID: studyID,
            consentVersion: consentVersion
        ).attemptID
    }

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func storagePath(
        userID: UUID,
        studyID: UUID,
        consentVersion: String,
        consentID: UUID
    ) -> String {
        [
            userID.uuidString.lowercased(),
            studyID.uuidString.lowercased(),
            consentVersion,
            "\(consentID.uuidString.lowercased()).pdf"
        ].joined(separator: "/")
    }

    static func makeConsentInsertPayload(
        consentID: UUID,
        userID: UUID,
        study: Study,
        consent: StudyConsentCompletion,
        storagePath: String,
        appVersion: String?,
        deviceInfo: [String: JSONValue],
        fallbackSignedAt: Date
    ) throws -> ConsentInsertPayload {
        guard consent.isValidSignedConsent else {
            throw ConsentServiceError.invalidConsentCompletion
        }
        guard let artifact = consent.artifact else {
            throw ConsentServiceError.missingSignedArtifact
        }

        return ConsentInsertPayload(
            id: consentID,
            userID: userID,
            studyID: study.id,
            consentVersion: consent.consentVersion,
            signedAt: iso8601String(from: consent.signedAt ?? fallbackSignedAt),
            signerGivenName: consent.signerGivenName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            signerFamilyName: consent.signerFamilyName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            consentPDFBucket: StudyConsentCatalog.consentStorageBucket,
            consentPDFPath: storagePath,
            consentPDFSHA256: artifact.pdfSHA256Hex,
            consentContentSHA256: consent.consentContentSHA256Hex,
            signatureImageSHA256: consent.signatureImageSHA256Hex,
            collectionMethod: consent.collectionMethod,
            attestationText: consent.attestationText,
            attestationVersion: consent.attestationVersion,
            researchKitTaskIdentifier: consent.researchKitFinishState == nil
                ? nil
                : consent.taskIdentifier,
            researchKitFinishState: consent.researchKitFinishState,
            appVersion: appVersion,
            deviceInfo: deviceInfo.isEmpty ? nil : deviceInfo
        )
    }

    static func appVersion(bundle: Bundle) -> String? {
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (bundle.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        case (nil, nil):
            return nil
        }
    }

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
