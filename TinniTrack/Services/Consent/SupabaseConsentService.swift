//
//  SupabaseConsentService.swift
//  TinniTrack
//

import Foundation
import Storage
import Supabase

final class SupabaseConsentService: ConsentServiceProtocol {
    private let client: SupabaseClient
    private let deviceMetadataProvider: DeviceMetadataProviding
    private let bundle: Bundle
    private let uuidProvider: () -> UUID
    private let now: () -> Date

    init(
        client: SupabaseClient = supabase,
        deviceMetadataProvider: DeviceMetadataProviding = SystemDeviceMetadataProvider(),
        bundle: Bundle = .main,
        uuidProvider: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.deviceMetadataProvider = deviceMetadataProvider
        self.bundle = bundle
        self.uuidProvider = uuidProvider
        self.now = now
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws {
        guard let definition = StudyConsentCatalog.definition(for: study.slug) else {
            throw ConsentServiceError.missingCatalogDefinition(studySlug: study.slug)
        }

        guard consent.studySlug == definition.studySlug,
              consent.consentVersion == definition.consentVersion,
              study.slug == definition.studySlug else {
            throw ConsentServiceError.studyMismatch
        }

        guard consent.isValidSignedConsent else {
            throw ConsentServiceError.invalidConsentCompletion
        }

        guard let artifact = consent.artifact else {
            throw ConsentServiceError.missingSignedArtifact
        }

        let userID = try await currentUserID()
        let consentID = uuidProvider()
        let storagePath = Self.storagePath(
            userID: userID,
            studyID: study.id,
            consentVersion: consent.consentVersion,
            consentID: consentID
        )

        try await client.storage
            .from(StudyConsentCatalog.consentStorageBucket)
            .upload(
                storagePath,
                data: artifact.pdfData,
                options: FileOptions(
                    cacheControl: "0",
                    contentType: "application/pdf",
                    upsert: false
                )
            )

        let payload = try Self.makeConsentInsertPayload(
            consentID: consentID,
            userID: userID,
            study: study,
            consent: consent,
            storagePath: storagePath,
            appVersion: Self.appVersion(bundle: bundle),
            deviceInfo: deviceMetadataProvider.currentDeviceInfo(),
            fallbackSignedAt: now()
        )

        try await client
            .from("consents")
            .insert(payload)
            .execute()

        try await client
            .rpc(
                "enroll_in_study_after_consent",
                params: EnrollAfterConsentParams(
                    studyID: study.id,
                    consentID: consentID
                )
            )
            .execute()
    }

    private func currentUserID() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw ConsentServiceError.noActiveSession
        }
    }
}

extension SupabaseConsentService {
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
            signedAt: iso8601Formatter.string(from: consent.signedAt ?? fallbackSignedAt),
            signerGivenName: consent.signerGivenName?.trimmingCharacters(in: .whitespacesAndNewlines),
            signerFamilyName: consent.signerFamilyName?.trimmingCharacters(in: .whitespacesAndNewlines),
            consentPDFBucket: StudyConsentCatalog.consentStorageBucket,
            consentPDFPath: storagePath,
            consentPDFSHA256: artifact.pdfSHA256Hex,
            researchKitTaskIdentifier: consent.taskIdentifier,
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

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct ConsentInsertPayload: Encodable, Equatable {
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
    let researchKitTaskIdentifier: String
    let researchKitFinishState: String
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
        case researchKitTaskIdentifier = "researchkit_task_identifier"
        case researchKitFinishState = "researchkit_finish_state"
        case appVersion = "app_version"
        case deviceInfo = "device_info"
    }
}

nonisolated private struct EnrollAfterConsentParams: Encodable, Sendable {
    let studyID: UUID
    let consentID: UUID

    enum CodingKeys: String, CodingKey {
        case studyID = "p_study_id"
        case consentID = "p_consent_id"
    }
}
