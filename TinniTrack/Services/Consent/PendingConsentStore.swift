//
//  PendingConsentStore.swift
//  TinniTrack
//

import CryptoKit
import Foundation

nonisolated struct PendingConsentKey: Equatable, Sendable {
    let attemptID: UUID
    let userID: UUID
    let studyID: UUID
    let consentVersion: String

    init(
        userID: UUID,
        studyID: UUID,
        consentVersion: String
    ) {
        self.userID = userID
        self.studyID = studyID
        self.consentVersion = consentVersion

        var seed = Data("tinnitrack-consent-id-v1\0".utf8)
        for component in [
            userID.uuidString.lowercased(),
            studyID.uuidString.lowercased(),
            consentVersion
        ] {
            seed.append(contentsOf: component.utf8)
            seed.append(0)
        }

        var bytes = Array(SHA256.hash(data: seed).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        attemptID = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

nonisolated protocol PendingConsentStoring: Sendable {
    func load(for key: PendingConsentKey) async throws -> StudyConsentCompletion?

    /// Returns the durable completion claimed for this key. An exact retry is
    /// accepted; a different signed completion cannot replace the first one.
    func recoverOrSave(
        _ proposedCompletion: StudyConsentCompletion,
        for key: PendingConsentKey
    ) async throws -> StudyConsentCompletion

    func clear(for key: PendingConsentKey) async throws
}

nonisolated enum PendingConsentStoreError: Error, Equatable {
    case applicationSupportUnavailable
    case conflictingRecord
    case invalidRecord
    case persistenceFailed
}

actor ProtectedPendingConsentStore: PendingConsentStoring {
    static let shared = ProtectedPendingConsentStore()
    nonisolated static let protectedWritingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtection
    ]

    private let baseDirectory: URL?

    init(
        baseDirectory: URL? = nil
    ) {
        self.baseDirectory = baseDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TinniTrack", isDirectory: true)
            .appendingPathComponent("PendingConsents", isDirectory: true)
    }

    func load(for key: PendingConsentKey) async throws -> StudyConsentCompletion? {
        let fileURL = try fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try prepareDirectory()
        try applyProtectionAndBackupExclusion(to: fileURL)
        return try load(from: fileURL, for: key)
    }

    func recoverOrSave(
        _ proposedCompletion: StudyConsentCompletion,
        for key: PendingConsentKey
    ) async throws -> StudyConsentCompletion {
        guard Self.isValid(proposedCompletion, for: key) else {
            throw PendingConsentStoreError.invalidRecord
        }

        let fileURL = try fileURL(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            try prepareDirectory()
            try applyProtectionAndBackupExclusion(to: fileURL)
            let recoveredCompletion = try load(from: fileURL, for: key)
            guard recoveredCompletion == proposedCompletion else {
                throw PendingConsentStoreError.conflictingRecord
            }
            return recoveredCompletion
        }

        let record = PendingConsentRecord(
            schemaVersion: 1,
            attemptID: key.attemptID,
            userID: key.userID,
            studyID: key.studyID,
            consentVersion: key.consentVersion,
            completion: proposedCompletion
        )

        do {
            try prepareDirectory()
            let data = try JSONEncoder().encode(record)
            try data.write(
                to: fileURL,
                options: Self.protectedWritingOptions
            )
            try applyProtectionAndBackupExclusion(to: fileURL)
            return proposedCompletion
        } catch let error as PendingConsentStoreError {
            throw error
        } catch {
            throw PendingConsentStoreError.persistenceFailed
        }
    }

    func clear(for key: PendingConsentKey) async throws {
        let fileURL = try fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw PendingConsentStoreError.persistenceFailed
        }
    }

    private func load(
        from fileURL: URL,
        for key: PendingConsentKey
    ) throws -> StudyConsentCompletion {
        do {
            let data = try Data(contentsOf: fileURL)
            let record = try JSONDecoder().decode(PendingConsentRecord.self, from: data)
            guard record.schemaVersion == 1,
                  record.attemptID == key.attemptID,
                  record.userID == key.userID,
                  record.studyID == key.studyID,
                  record.consentVersion == key.consentVersion,
                  Self.isValid(record.completion, for: key) else {
                throw PendingConsentStoreError.invalidRecord
            }
            return record.completion
        } catch let error as PendingConsentStoreError {
            throw error
        } catch {
            throw PendingConsentStoreError.invalidRecord
        }
    }

    private func fileURL(for key: PendingConsentKey) throws -> URL {
        guard let baseDirectory else {
            throw PendingConsentStoreError.applicationSupportUnavailable
        }
        return baseDirectory
            .appendingPathComponent(key.attemptID.uuidString.lowercased())
            .appendingPathExtension("json")
    }

    private func prepareDirectory() throws {
        guard let baseDirectory else {
            throw PendingConsentStoreError.applicationSupportUnavailable
        }

        do {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try applyProtectionAndBackupExclusion(to: baseDirectory)
        } catch let error as PendingConsentStoreError {
            throw error
        } catch {
            throw PendingConsentStoreError.persistenceFailed
        }
    }

    private func applyProtectionAndBackupExclusion(to url: URL) throws {
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            var protectedURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)

            #if !targetEnvironment(simulator)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.protectionKey] as? FileProtectionType == .complete else {
                throw PendingConsentStoreError.persistenceFailed
            }
            #endif

            let verifiedValues = try protectedURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            )
            guard verifiedValues.isExcludedFromBackup == true else {
                throw PendingConsentStoreError.persistenceFailed
            }
        } catch let error as PendingConsentStoreError {
            throw error
        } catch {
            throw PendingConsentStoreError.persistenceFailed
        }
    }

    nonisolated private static func isValid(
        _ completion: StudyConsentCompletion,
        for key: PendingConsentKey
    ) -> Bool {
        guard completion.consentVersion == key.consentVersion,
              completion.isValidSignedConsent,
              let artifact = completion.artifact,
              artifact.storageBucket == StudyConsentCatalog.consentStorageBucket else {
            return false
        }

        let digest = SHA256.hash(data: artifact.pdfData)
            .map { String(format: "%02x", $0) }
            .joined()
        return digest == artifact.pdfSHA256Hex
    }

    private var fileManager: FileManager {
        .default
    }
}

nonisolated private struct PendingConsentRecord: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let attemptID: UUID
    let userID: UUID
    let studyID: UUID
    let consentVersion: String
    let completion: StudyConsentCompletion
}
