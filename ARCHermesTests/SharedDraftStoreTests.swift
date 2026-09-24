import XCTest
@testable import ARCHermes

final class SharedDraftStoreTests: XCTestCase {
    func testDraftTextCombinesTextAndURLsInOrder() {
        let draft = ARCHermesShareDraft.draftText(
            textSnippets: [
                "  Summarize this page  ",
                "\nSummarize this page\n",
                "Key quote",
                "https://example.com/article"
            ],
            urls: [
                URL(string: "https://example.com/article")!,
                URL(string: "https://example.com/article")!,
                URL(string: "https://example.com/notes")!
            ]
        )

        XCTAssertEqual(
            draft,
            """
            Summarize this page

            Key quote

            https://example.com/article

            https://example.com/notes
            """
        )
    }

    func testDraftTextIgnoresEmptyInput() {
        let draft = ARCHermesShareDraft.draftText(textSnippets: [" \n\t "], urls: [])

        XCTAssertEqual(draft, "")
    }

    func testComposerDraftAddsTrailingNewlineForFollowupInput() {
        XCTAssertEqual(
            ARCHermesShareDraft.composerDraft(from: "  https://example.com/article  "),
            "https://example.com/article\n"
        )
        XCTAssertEqual(ARCHermesShareDraft.composerDraft(from: " \n\t "), "")
    }

    func testShareOpenURLRecognizesOnlyARCHermesShareLinks() {
        let scheme = ARCHermesShareDraft.urlScheme

        XCTAssertTrue(ARCHermesShareDraft.isShareOpenURL(URL(string: "\(scheme)://share")!))
        XCTAssertFalse(ARCHermesShareDraft.isShareOpenURL(URL(string: "\(scheme)://settings")!))
        XCTAssertFalse(ARCHermesShareDraft.isShareOpenURL(URL(string: "https://example.com/share")!))
    }

    func testPendingDraftStorageLoadsAndClearsDraft() throws {
        let directory = try temporaryDirectory()

        try ARCHermesShareDraft.savePendingDraft(
            "  Draft from Safari  ",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let draft = try ARCHermesShareDraft.loadPendingDraft(from: directory)
        XCTAssertEqual(draft, "Draft from Safari")
        XCTAssertNil(try ARCHermesShareDraft.loadPendingDraft(from: directory))
    }

    func testPendingImportStorageLoadsAttachmentAndClearsStagedFiles() throws {
        let directory = try temporaryDirectory()
        let attachmentData = Data("pdf bytes".utf8)

        try ARCHermesShareDraft.savePendingImport(
            draft: "  Review this  ",
            attachments: [
                SharedAttachmentImport(
                    filename: "/private/tmp/report.pdf",
                    typeIdentifier: "com.adobe.pdf",
                    data: attachmentData
                )
            ],
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_001)
        )

        let sharedImport = try XCTUnwrap(try ARCHermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "Review this")
        XCTAssertEqual(sharedImport.attachments.count, 1)
        XCTAssertEqual(sharedImport.attachments.first?.filename, "report.pdf")
        XCTAssertEqual(sharedImport.attachments.first?.typeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(sharedImport.attachments.first?.data, attachmentData)
        XCTAssertNil(try ARCHermesShareDraft.loadPendingImport(from: directory))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ARCHermesShareDraft.pendingAttachmentsDirectoryName).path
            )
        )
    }

    func testPendingImportSupportsAttachmentOnlyShare() throws {
        let directory = try temporaryDirectory()

        try ARCHermesShareDraft.savePendingImport(
            draft: " \n ",
            attachments: [
                SharedAttachmentImport(
                    filename: "photo.jpg",
                    typeIdentifier: "public.jpeg",
                    data: Data([0x01, 0x02, 0x03])
                )
            ],
            in: directory
        )

        let sharedImport = try XCTUnwrap(try ARCHermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "")
        XCTAssertEqual(sharedImport.attachments.first?.filename, "photo.jpg")
        XCTAssertEqual(sharedImport.attachments.first?.data, Data([0x01, 0x02, 0x03]))
    }

    func testPendingImportKeepsMultipleUploadableAttachments() throws {
        let directory = try temporaryDirectory()

        try ARCHermesShareDraft.savePendingImport(
            draft: "",
            attachments: [
                SharedAttachmentImport(
                    filename: "first.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("first".utf8)
                ),
                SharedAttachmentImport(
                    filename: "second.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("second".utf8)
                )
            ],
            in: directory
        )

        let sharedImport = try XCTUnwrap(try ARCHermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.attachments.map(\.filename), ["first.txt", "second.txt"])
        XCTAssertEqual(sharedImport.attachments.map(\.data), [Data("first".utf8), Data("second".utf8)])
    }

    func testPendingImportCapsAttachmentsAtSharedLimit() throws {
        let directory = try temporaryDirectory()
        let attachments = (0..<(ARCHermesShareDraft.maximumSharedAttachmentCount + 1)).map { index in
            SharedAttachmentImport(
                filename: "file-\(index).txt",
                typeIdentifier: "public.plain-text",
                data: Data("file-\(index)".utf8)
            )
        }

        try ARCHermesShareDraft.savePendingImport(
            draft: "",
            attachments: attachments,
            in: directory
        )

        let sharedImport = try XCTUnwrap(try ARCHermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.attachments.count, ARCHermesShareDraft.maximumSharedAttachmentCount)
        XCTAssertEqual(sharedImport.attachments.first?.filename, "file-0.txt")
        XCTAssertEqual(sharedImport.attachments.last?.filename, "file-9.txt")
    }

    func testInboxKeepsTwoSharesAndReservesThemOldestFirst() throws {
        let directory = try temporaryDirectory()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_010)
        let secondDate = Date(timeIntervalSince1970: 1_800_000_020)

        try ARCHermesShareDraft.savePendingDraft("First share", in: directory, now: firstDate)
        try ARCHermesShareDraft.savePendingDraft("Second share", in: directory, now: secondDate)
        XCTAssertTrue(try ARCHermesShareDraft.hasPendingImport(in: directory, now: secondDate))

        let first = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate)
        )
        XCTAssertEqual(first.sharedImport.draft, "First share")
        XCTAssertEqual(first.createdAt, firstDate)
        XCTAssertTrue(try ARCHermesShareDraft.hasPendingImport(in: directory, now: secondDate))
        try ARCHermesShareDraft.consume(first, from: directory)

        let second = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate)
        )
        XCTAssertEqual(second.sharedImport.draft, "Second share")
        XCTAssertEqual(second.createdAt, secondDate)
        try ARCHermesShareDraft.consume(second, from: directory)

        XCTAssertFalse(try ARCHermesShareDraft.hasPendingImport(in: directory, now: secondDate))
        XCTAssertNil(try ARCHermesShareDraft.reserveNextPendingImport(from: directory, now: secondDate))
    }

    func testInboxDeduplicatesRepeatedPendingContent() throws {
        let directory = try temporaryDirectory()

        try ARCHermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_030)
        )
        try ARCHermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_040)
        )

        let reservation = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )
        try ARCHermesShareDraft.savePendingDraft(
            "Repeated share",
            in: directory,
            now: Date(timeIntervalSince1970: 1_800_000_050)
        )
        try ARCHermesShareDraft.consume(reservation, from: directory)

        XCTAssertNil(try ARCHermesShareDraft.reserveNextPendingImport(from: directory))
    }

    func testReleasedReservationCanBeReservedAgain() throws {
        let directory = try temporaryDirectory()
        try ARCHermesShareDraft.savePendingDraft("Route me later", in: directory)

        let first = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )
        try ARCHermesShareDraft.release(first, in: directory)

        let second = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(second.itemID, first.itemID)
        XCTAssertNotEqual(second.reservationID, first.reservationID)
        XCTAssertEqual(second.sharedImport, first.sharedImport)
    }

    func testExpiredReservationReturnsToInboxWithNewOwnership() throws {
        let directory = try temporaryDirectory()
        let reservationDate = Date(timeIntervalSince1970: 1_800_000_050)
        try ARCHermesShareDraft.savePendingDraft("Recover me", in: directory, now: reservationDate)

        let expired = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory, now: reservationDate)
        )
        let recovered = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(
                from: directory,
                now: reservationDate.addingTimeInterval(ARCHermesShareDraft.reservationLifetime + 1)
            )
        )

        XCTAssertEqual(recovered.itemID, expired.itemID)
        XCTAssertNotEqual(recovered.reservationID, expired.reservationID)
        XCTAssertThrowsError(try ARCHermesShareDraft.consume(expired, from: directory))
        try ARCHermesShareDraft.consume(recovered, from: directory)
    }

    func testMissingAttachmentOnlyItemDoesNotBlockLaterShare() throws {
        let directory = try temporaryDirectory()
        let attachmentDate = Date(timeIntervalSince1970: 1_800_000_060)
        try ARCHermesShareDraft.savePendingImport(
            draft: "",
            attachments: [
                SharedAttachmentImport(
                    filename: "missing.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("gone".utf8)
                )
            ],
            in: directory,
            now: attachmentDate
        )
        try ARCHermesShareDraft.savePendingDraft(
            "Still valid",
            in: directory,
            now: attachmentDate.addingTimeInterval(1)
        )

        for fileURL in try attachmentFileURLs(in: directory) {
            try FileManager.default.removeItem(at: fileURL)
        }

        let reservation = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(reservation.sharedImport.draft, "Still valid")
        try ARCHermesShareDraft.consume(reservation, from: directory)
        XCTAssertNil(try ARCHermesShareDraft.reserveNextPendingImport(from: directory))
    }

    func testMissingAttachmentDoesNotDiscardRemainingSharedContent() throws {
        let directory = try temporaryDirectory()
        try ARCHermesShareDraft.savePendingImport(
            draft: "Review what remains",
            attachments: [
                SharedAttachmentImport(
                    filename: "first.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("first".utf8)
                ),
                SharedAttachmentImport(
                    filename: "second.txt",
                    typeIdentifier: "public.plain-text",
                    data: Data("second".utf8)
                )
            ],
            in: directory
        )

        let attachmentFiles = try attachmentFileURLs(in: directory)
        XCTAssertEqual(attachmentFiles.count, 2)
        try FileManager.default.removeItem(at: attachmentFiles[0])

        let reservation = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )
        XCTAssertEqual(reservation.sharedImport.draft, "Review what remains")
        XCTAssertEqual(reservation.sharedImport.attachments.count, 1)
        try ARCHermesShareDraft.consume(reservation, from: directory)
    }

    func testFailedInboxPreparationDoesNotOverwriteExistingFile() throws {
        let parent = try temporaryDirectory()
        let fileURL = parent.appendingPathComponent("not-a-directory")
        let originalData = Data("keep me".utf8)
        try originalData.write(to: fileURL)

        XCTAssertThrowsError(
            try ARCHermesShareDraft.savePendingDraft("Unsaved share", in: fileURL)
        )
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testPendingImportDecodesLegacyDraftOnlyPayload() throws {
        let directory = try temporaryDirectory()
        let payloadURL = directory.appendingPathComponent(ARCHermesShareDraft.pendingDraftFileName)
        let legacyPayload = """
        {
          "draft": "Legacy note",
          "createdAt": 1800000002
        }
        """
        try Data(legacyPayload.utf8).write(to: payloadURL)

        let sharedImport = try XCTUnwrap(try ARCHermesShareDraft.loadPendingImport(from: directory))

        XCTAssertEqual(sharedImport.draft, "Legacy note")
        XCTAssertTrue(sharedImport.attachments.isEmpty)
    }

    func testMalformedLegacyPayloadDoesNotBlockTransactionalInbox() throws {
        let directory = try temporaryDirectory()
        try ARCHermesShareDraft.savePendingDraft("Valid new share", in: directory)

        let legacyPayloadURL = directory.appendingPathComponent(ARCHermesShareDraft.pendingDraftFileName)
        try Data("not json".utf8).write(to: legacyPayloadURL)
        let legacyAttachmentsURL = directory.appendingPathComponent(
            ARCHermesShareDraft.pendingAttachmentsDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyAttachmentsURL, withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: legacyAttachmentsURL.appendingPathComponent("orphan.txt"))

        let reservation = try XCTUnwrap(
            try ARCHermesShareDraft.reserveNextPendingImport(from: directory)
        )

        XCTAssertEqual(reservation.sharedImport.draft, "Valid new share")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPayloadURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyAttachmentsURL.path))
    }

    func testEmptyPendingDraftIsNotWritten() throws {
        let directory = try temporaryDirectory()

        try ARCHermesShareDraft.savePendingDraft(" \n ", in: directory)

        XCTAssertNil(try ARCHermesShareDraft.loadPendingDraft(from: directory))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func attachmentFileURLs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard
                let url = element as? URL,
                url.pathExtension != "json",
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }
}
