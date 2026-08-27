//
//  ConsentPersistenceRemote.swift
//  TinniTrack
//

import Foundation
import Storage
import Supabase

protocol ConsentPersistenceRemote {
    func currentUserID() async throws -> UUID

    func existingConsent(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) async throws -> ExistingConsentRow?

    func uploadPDF(storagePath: String, data: Data) async throws
    func downloadPDF(storagePath: String) async throws -> Data
    func insertConsent(_ payload: ConsentInsertPayload) async throws
    func enroll(studyID: UUID, consentID: UUID) async throws
}

final class SupabaseConsentPersistenceRemote: ConsentPersistenceRemote {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch AuthError.sessionMissing {
            throw ConsentServiceError.noActiveSession
        }
    }

    func existingConsent(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) async throws -> ExistingConsentRow? {
        let rows: [ExistingConsentRow] = try await client
            .from("consents")
            .select(
                "id,user_id,study_id,consent_version,consent_pdf_bucket,consent_pdf_path,consent_pdf_sha256,consent_content_sha256,signature_image_sha256,collection_method,attestation_text,attestation_version"
            )
            .eq("user_id", value: userID.uuidString)
            .eq("study_id", value: studyID.uuidString)
            .eq("consent_version", value: consentVersion)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func uploadPDF(storagePath: String, data: Data) async throws {
        try await client.storage
            .from(StudyConsentCatalog.consentStorageBucket)
            .upload(
                storagePath,
                data: data,
                options: FileOptions(
                    cacheControl: "0",
                    contentType: "application/pdf",
                    upsert: false
                )
            )
    }

    func downloadPDF(storagePath: String) async throws -> Data {
        try await client.storage
            .from(StudyConsentCatalog.consentStorageBucket)
            .download(path: storagePath)
    }

    func insertConsent(_ payload: ConsentInsertPayload) async throws {
        try await client
            .from("consents")
            .insert(payload)
            .execute()
    }

    func enroll(studyID: UUID, consentID: UUID) async throws {
        try await client
            .rpc(
                "enroll_in_study_after_consent",
                params: EnrollAfterConsentParams(
                    studyID: studyID,
                    consentID: consentID
                )
            )
            .execute()
    }
}
