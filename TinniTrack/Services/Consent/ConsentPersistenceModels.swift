//
//  ConsentPersistenceModels.swift
//  TinniTrack
//

import Foundation

nonisolated struct ExistingConsentRow: Decodable, Sendable {
    let id: UUID
    let userID: UUID
    let studyID: UUID
    let consentVersion: String
    let consentPDFBucket: String
    let consentPDFPath: String
    let consentPDFSHA256: String
    let consentContentSHA256: String
    let signatureImageSHA256: String
    let collectionMethod: String
    let attestationText: String
    let attestationVersion: String

    func matches(
        _ consent: StudyConsentCompletion,
        key: PendingConsentKey,
        storagePath: String
    ) -> Bool {
        id == key.attemptID
            && userID == key.userID
            && studyID == key.studyID
            && consentVersion == key.consentVersion
            && consentPDFBucket == StudyConsentCatalog.consentStorageBucket
            && consentPDFPath == storagePath
            && consentPDFSHA256 == consent.artifact?.pdfSHA256Hex
            && consentContentSHA256 == consent.consentContentSHA256Hex
            && signatureImageSHA256 == consent.signatureImageSHA256Hex
            && collectionMethod == consent.collectionMethod
            && attestationText == consent.attestationText
            && attestationVersion == consent.attestationVersion
    }

    func matchesCatalog(
        key: PendingConsentKey,
        storagePath: String,
        definition: StudyConsentDefinition
    ) -> Bool {
        id == key.attemptID
            && userID == key.userID
            && studyID == key.studyID
            && consentVersion == key.consentVersion
            && consentVersion == definition.consentVersion
            && consentPDFBucket == StudyConsentCatalog.consentStorageBucket
            && consentPDFPath == storagePath
            && consentPDFSHA256.isSHA256Hex
            && consentContentSHA256 == definition.contentSHA256Hex
            && signatureImageSHA256.isSHA256Hex
            && collectionMethod == StudyConsentCatalog.nativeCollectionMethod
            && attestationText == definition.attestation.text
            && attestationVersion == definition.attestation.version
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case studyID = "study_id"
        case consentVersion = "consent_version"
        case consentPDFBucket = "consent_pdf_bucket"
        case consentPDFPath = "consent_pdf_path"
        case consentPDFSHA256 = "consent_pdf_sha256"
        case consentContentSHA256 = "consent_content_sha256"
        case signatureImageSHA256 = "signature_image_sha256"
        case collectionMethod = "collection_method"
        case attestationText = "attestation_text"
        case attestationVersion = "attestation_version"
    }
}

nonisolated private extension String {
    var isSHA256Hex: Bool {
        count == 64 && utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

nonisolated struct ConsentInsertPayload: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let studyID: UUID
    let consentVersion: String
    let signedAt: String
    let signerGivenName: String?
    let signerFamilyName: String?
    let consentPDFBucket: String
    let consentPDFPath: String
    let consentPDFSHA256: String
    let consentContentSHA256: String
    let signatureImageSHA256: String?
    let collectionMethod: String
    let attestationText: String
    let attestationVersion: String
    let researchKitTaskIdentifier: String?
    let researchKitFinishState: String?
    let appVersion: String?
    let deviceInfo: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case studyID = "study_id"
        case consentVersion = "consent_version"
        case signedAt = "signed_at"
        case signerGivenName = "signer_given_name"
        case signerFamilyName = "signer_family_name"
        case consentPDFBucket = "consent_pdf_bucket"
        case consentPDFPath = "consent_pdf_path"
        case consentPDFSHA256 = "consent_pdf_sha256"
        case consentContentSHA256 = "consent_content_sha256"
        case signatureImageSHA256 = "signature_image_sha256"
        case collectionMethod = "collection_method"
        case attestationText = "attestation_text"
        case attestationVersion = "attestation_version"
        case researchKitTaskIdentifier = "researchkit_task_identifier"
        case researchKitFinishState = "researchkit_finish_state"
        case appVersion = "app_version"
        case deviceInfo = "device_info"
    }
}

nonisolated struct EnrollAfterConsentParams: Encodable, Sendable {
    let studyID: UUID
    let consentID: UUID

    enum CodingKeys: String, CodingKey {
        case studyID = "p_study_id"
        case consentID = "p_consent_id"
    }
}
