//
//  SupabaseConsentService.swift
//  TinniTrack
//

import Foundation
import Supabase

final class SupabaseConsentService: ConsentServiceProtocol {
    private let remote: any ConsentPersistenceRemote
    private let deviceMetadataProvider: DeviceMetadataProviding
    private let pendingConsentStore: any PendingConsentStoring
    private let bundle: Bundle
    private let now: () -> Date

    convenience init(
        client: SupabaseClient = supabase,
        deviceMetadataProvider: DeviceMetadataProviding = SystemDeviceMetadataProvider(),
        pendingConsentStore: any PendingConsentStoring = ProtectedPendingConsentStore.shared,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            remote: SupabaseConsentPersistenceRemote(client: client),
            deviceMetadataProvider: deviceMetadataProvider,
            pendingConsentStore: pendingConsentStore,
            bundle: bundle,
            now: now
        )
    }

    init(
        remote: any ConsentPersistenceRemote,
        deviceMetadataProvider: DeviceMetadataProviding = SystemDeviceMetadataProvider(),
        pendingConsentStore: any PendingConsentStoring = ProtectedPendingConsentStore.shared,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.remote = remote
        self.deviceMetadataProvider = deviceMetadataProvider
        self.pendingConsentStore = pendingConsentStore
        self.bundle = bundle
        self.now = now
    }

    func availableEnrollmentRecovery(
        for study: Study
    ) async throws -> ConsentEnrollmentRecovery? {
        try await recoveryResolution(for: study)?.availability
    }

    func resumeEnrollment(for study: Study) async throws -> StudyEnrollment {
        guard let resolution = try await recoveryResolution(for: study) else {
            throw ConsentServiceError.noRecoverableConsent
        }

        switch resolution {
        case let .pendingUpload(consent):
            return try await finalizeConsentAndEnroll(
                study: study,
                consent: consent
            )
        case let .pendingEnrollment(existingConsent, key, clearLocalEvidence):
            if clearLocalEvidence {
                try await clearPendingConsent(for: key)
            }
            return try await enroll(
                studyID: study.id,
                consentID: existingConsent.id
            )
        }
    }

    func finalizeConsentAndEnroll(
        study: Study,
        consent: StudyConsentCompletion
    ) async throws -> StudyEnrollment {
        guard let definition = StudyConsentCatalog.definition(for: study.slug) else {
            throw ConsentServiceError.missingCatalogDefinition(studySlug: study.slug)
        }

        _ = try Self.validatedArtifact(
            for: consent,
            study: study,
            definition: definition
        )

        let userID = try await remote.currentUserID()
        let pendingKey = PendingConsentKey(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion
        )
        let consentID = pendingKey.attemptID
        let storagePath = Self.storagePath(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion,
            consentID: consentID
        )

        if let existingConsent = try await existingConsent(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion
        ) {
            if let pendingConsent = try await loadPendingConsent(for: pendingKey) {
                _ = try Self.validatedArtifact(
                    for: pendingConsent,
                    study: study,
                    definition: definition
                )
                guard pendingConsent == consent else {
                    throw ConsentServiceError.conflictingPendingArtifact
                }
                guard existingConsent.matches(
                    pendingConsent,
                    key: pendingKey,
                    storagePath: storagePath
                ) else {
                    throw ConsentServiceError.conflictingPendingArtifact
                }
                try await clearPendingConsent(for: pendingKey)
            } else {
                guard existingConsent.matches(
                    consent,
                    key: pendingKey,
                    storagePath: storagePath
                ) else {
                    throw ConsentServiceError.conflictingPendingArtifact
                }
            }
            return try await enroll(
                studyID: study.id,
                consentID: existingConsent.id
            )
        }

        let pendingConsent = try await recoverOrSavePendingConsent(
            consent,
            for: pendingKey
        )
        let artifact = try Self.validatedArtifact(
            for: pendingConsent,
            study: study,
            definition: definition
        )
        do {
            try await remote.uploadPDF(
                storagePath: storagePath,
                data: artifact.pdfData
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch {
            if let recordedConsentID = try await recoverFromUploadFailure(
                error,
                consent: pendingConsent,
                key: pendingKey,
                storagePath: storagePath
            ) {
                try await clearPendingConsent(for: pendingKey)
                return try await enroll(
                    studyID: study.id,
                    consentID: recordedConsentID
                )
            }
        }

        let payload = try Self.makeConsentInsertPayload(
            consentID: consentID,
            userID: userID,
            study: study,
            consent: pendingConsent,
            storagePath: storagePath,
            appVersion: Self.appVersion(bundle: bundle),
            deviceInfo: deviceMetadataProvider.currentDeviceInfo(),
            fallbackSignedAt: now()
        )

        do {
            try await remote.insertConsent(payload)
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch let insertError {
            // The insert may have committed even if its response was lost. A
            // retry should continue with that immutable consent instead of
            // creating another artifact or leaving the participant stranded.
            do {
                if let recordedConsentID = try await recordedConsentID(
                    matching: pendingConsent,
                    key: pendingKey,
                    storagePath: storagePath
                ) {
                    try await clearPendingConsent(for: pendingKey)
                    return try await enroll(
                        studyID: study.id,
                        consentID: recordedConsentID
                    )
                }
            } catch let recoveryError as ConsentServiceError {
                throw recoveryError
            } catch {
                throw insertError
            }
            throw insertError
        }

        guard let confirmedConsentID = try await recordedConsentID(
            matching: pendingConsent,
            key: pendingKey,
            storagePath: storagePath
        ) else {
            throw ConsentServiceError.consentRecordConfirmationFailed
        }
        try await clearPendingConsent(for: pendingKey)
        return try await enroll(studyID: study.id, consentID: confirmedConsentID)
    }

    private func recoverOrSavePendingConsent(
        _ proposedConsent: StudyConsentCompletion,
        for key: PendingConsentKey
    ) async throws -> StudyConsentCompletion {
        do {
            return try await pendingConsentStore.recoverOrSave(
                proposedConsent,
                for: key
            )
        } catch PendingConsentStoreError.conflictingRecord {
            throw ConsentServiceError.conflictingPendingArtifact
        } catch {
            throw ConsentServiceError.pendingArtifactPersistenceFailed
        }
    }

    private func recoveryResolution(
        for study: Study
    ) async throws -> ConsentRecoveryResolution? {
        guard let definition = StudyConsentCatalog.definition(for: study.slug) else {
            throw ConsentServiceError.missingCatalogDefinition(studySlug: study.slug)
        }

        let userID = try await remote.currentUserID()
        let key = PendingConsentKey(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion
        )
        let storagePath = Self.storagePath(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion,
            consentID: key.attemptID
        )
        let pendingConsent = try await loadPendingConsent(for: key)
        if let pendingConsent {
            _ = try Self.validatedArtifact(
                for: pendingConsent,
                study: study,
                definition: definition
            )
        }
        let existingConsent = try await existingConsent(
            userID: userID,
            studyID: study.id,
            consentVersion: definition.consentVersion
        )

        switch (pendingConsent, existingConsent) {
        case let (pendingConsent?, existingConsent?):
            guard existingConsent.matches(
                pendingConsent,
                key: key,
                storagePath: storagePath
            ) else {
                throw ConsentServiceError.conflictingPendingArtifact
            }
            return .pendingEnrollment(
                existingConsent: existingConsent,
                key: key,
                clearLocalEvidence: true
            )
        case let (pendingConsent?, nil):
            return .pendingUpload(consent: pendingConsent)
        case let (nil, existingConsent?):
            guard existingConsent.matchesCatalog(
                key: key,
                storagePath: storagePath,
                definition: definition
            ) else {
                throw ConsentServiceError.conflictingPendingArtifact
            }
            return .pendingEnrollment(
                existingConsent: existingConsent,
                key: key,
                clearLocalEvidence: false
            )
        case (nil, nil):
            return nil
        }
    }

    private func loadPendingConsent(
        for key: PendingConsentKey
    ) async throws -> StudyConsentCompletion? {
        do {
            return try await pendingConsentStore.load(for: key)
        } catch {
            throw ConsentServiceError.pendingArtifactPersistenceFailed
        }
    }

    private func clearPendingConsent(for key: PendingConsentKey) async throws {
        do {
            try await pendingConsentStore.clear(for: key)
        } catch {
            throw ConsentServiceError.pendingArtifactPersistenceFailed
        }
    }

    private func existingConsent(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) async throws -> ExistingConsentRow? {
        try await remote.existingConsent(
            userID: userID,
            studyID: studyID,
            consentVersion: consentVersion
        )
    }

    private func recordedConsentID(
        matching consent: StudyConsentCompletion,
        key: PendingConsentKey,
        storagePath: String
    ) async throws -> UUID? {
        guard let recordedConsent = try await existingConsent(
            userID: key.userID,
            studyID: key.studyID,
            consentVersion: key.consentVersion
        ) else {
            return nil
        }
        guard recordedConsent.matches(
            consent,
            key: key,
            storagePath: storagePath
        ) else {
            throw ConsentServiceError.conflictingPendingArtifact
        }
        return recordedConsent.id
    }

    /// Recovers a committed-but-lost upload without overwriting or deleting
    /// consent evidence. A nil result means the stable path already contains
    /// this exact PDF and the caller can continue with the consent insert.
    private func recoverFromUploadFailure(
        _ uploadError: Error,
        consent: StudyConsentCompletion,
        key: PendingConsentKey,
        storagePath: String
    ) async throws -> UUID? {
        if let recordedConsentID = try await recordedConsentID(
            matching: consent,
            key: key,
            storagePath: storagePath
        ) {
            return recordedConsentID
        }

        let storedPDF: Data
        do {
            storedPDF = try await remote.downloadPDF(storagePath: storagePath)
        } catch {
            throw uploadError
        }

        guard let artifact = consent.artifact,
              Self.sha256Hex(for: storedPDF) == artifact.pdfSHA256Hex else {
            // The insert may have won concurrently between the first query and
            // the Storage download. Re-query before reporting a true conflict.
            if let recordedConsentID = try await recordedConsentID(
                matching: consent,
                key: key,
                storagePath: storagePath
            ) {
                return recordedConsentID
            }
            throw ConsentServiceError.conflictingPendingArtifact
        }
        return nil
    }

    private func enroll(studyID: UUID, consentID: UUID) async throws -> StudyEnrollment {
        try await remote.enroll(studyID: studyID, consentID: consentID)
    }
}

nonisolated private enum ConsentRecoveryResolution: Sendable {
    case pendingUpload(consent: StudyConsentCompletion)
    case pendingEnrollment(
        existingConsent: ExistingConsentRow,
        key: PendingConsentKey,
        clearLocalEvidence: Bool
    )

    var availability: ConsentEnrollmentRecovery {
        switch self {
        case .pendingUpload:
            return .pendingUpload
        case .pendingEnrollment:
            return .pendingEnrollment
        }
    }
}
