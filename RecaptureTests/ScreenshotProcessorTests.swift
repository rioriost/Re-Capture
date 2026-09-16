import CoreGraphics
import ImageIO
import XCTest
@testable import Recapture

final class ScreenshotProcessorTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!
    private var journalURL: URL!
    private var settings: SettingsSnapshot!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        destination = root.appendingPathComponent("destination", isDirectory: true)
        journalURL = root.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        settings = SettingsSnapshot(
            screenshotDefaults: ScreenshotDefaults(
                locationURL: source, namePrefix: "Screenshot", type: "png",
                includeDate: true, disableShadow: false, showThumbnail: false, captureMousePointer: false
            ),
            destinationURL: destination, filenameTemplate: "'Result'", outputFormat: .original,
            outputQuality: 85, transferMode: .copy
        )
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func processor(operations: ProcessingFileOperations = ProcessingFileOperations()) -> ScreenshotProcessor {
        ScreenshotProcessor(
            journalURL: journalURL, operations: operations, settleInterval: 0, minimumAge: 0,
            activeWindow: { ActiveWindowInfo(appName: "Test", windowTitle: "Test") }
        )
    }

    private func imageData(type: String = "public.png", count: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, count, nil))
        for _ in 0..<count { CGImageDestinationAddImage(encoder, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return data as Data
    }

    @discardableResult
    private func screenshot(_ name: String = "Screenshot input.png", data: Data? = nil) throws -> URL {
        let url = source.appendingPathComponent(name)
        try (data ?? imageData()).write(to: url)
        return url
    }

    private func outputs(in directory: URL? = nil) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory ?? destination, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
    }

    func testInitialAutomaticScanDoesNotTouchExistingFilesButBulkDoes() throws {
        let file = try screenshot()
        settings.transferMode = .move
        let subject = processor()
        XCTAssertEqual(subject.process(settings: settings, bulk: false).processed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try outputs().isEmpty)
        XCTAssertEqual(subject.process(settings: settings, bulk: true).processed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCopyIsIdempotentAcrossRestartAndBulkIsExplicit() throws {
        let subject = processor()
        _ = subject.process(settings: settings, bulk: false)
        let file = try screenshot()
        XCTAssertEqual(subject.process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(subject.process(settings: settings, bulk: false).processed, 0)
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 0)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertEqual(processor().process(settings: settings, bulk: true).processed, 1)
        XCTAssertEqual(try outputs().count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testNewFilesWhileClosedAreProcessedAfterInitialBaseline() throws {
        _ = processor().process(settings: settings, bulk: false)
        try screenshot()
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 1)
    }

    func testBulkNeverDeletesAnIncompleteActiveWriter() throws {
        settings.transferMode = .move
        let data = try imageData()
        let file = try screenshot(data: Data(data.prefix(8)))
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.seekToEnd()
        let result = processor().process(settings: settings, bulk: true)
        XCTAssertEqual(result.processed, 0)
        XCTAssertEqual(result.deferred, 1)
        XCTAssertTrue(result.retrySuggested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try outputs().isEmpty)
        try writer.write(contentsOf: data.dropFirst(8))
        try writer.close()
        XCTAssertEqual(processor().process(settings: settings, bulk: true).processed, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(outputs().first)), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRecentFileIsDeferredInBothModes() throws {
        try screenshot()
        let subject = ScreenshotProcessor(journalURL: journalURL, settleInterval: 0, minimumAge: 100)
        XCTAssertEqual(subject.process(settings: settings, bulk: true).deferred, 1)
        XCTAssertEqual(subject.process(settings: settings, bulk: false).deferred, 1)
        XCTAssertTrue(try outputs().isEmpty)
    }

    func testBulkRetryDoesNotRepeatSuccessfulCopies() throws {
        try screenshot("Screenshot complete.png")
        let data = try imageData()
        let incomplete = try screenshot("Screenshot incomplete.png", data: Data(data.prefix(8)))
        let subject = processor()
        let first = subject.process(settings: settings, bulk: true)
        XCTAssertEqual(first.processed, 1)
        XCTAssertEqual(first.deferred, 1)
        XCTAssertEqual(first.retrySourcePaths, [FileStamp.canonicalPath(incomplete)])

        var retry = try XCTUnwrap(settings)
        retry.includedSourcePaths = first.retrySourcePaths
        let second = subject.process(settings: retry, bulk: true)
        XCTAssertEqual(second.processed, 0)
        XCTAssertEqual(second.deferred, 1)
        XCTAssertEqual(try outputs().count, 1)

        try data.write(to: incomplete, options: .atomic)
        retry.includedSourcePaths = second.retrySourcePaths
        XCTAssertEqual(subject.process(settings: retry, bulk: true).processed, 1)
        XCTAssertEqual(try outputs().count, 2)
        XCTAssertEqual(subject.process(settings: settings, bulk: true).processed, 2)
        XCTAssertEqual(try outputs().count, 4)
    }

    func testSourceMutationDuringSnapshotKeepsOriginalAndRemovesStaging() throws {
        let file = try screenshot()
        settings.transferMode = .move
        var operations = ProcessingFileOperations()
        operations.copy = { from, to in
            try FileManager.default.copyItem(at: from, to: to)
            let writer = try FileHandle(forWritingTo: from)
            try writer.seekToEnd()
            try writer.write(contentsOf: Data([0]))
            try writer.close()
        }
        let result = processor(operations: operations).process(settings: settings, bulk: true)
        XCTAssertEqual(result.deferred, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 0)
    }

    func testRemovalFailurePreservesOneOutputAndRetriesOnlyRemovalAcrossRestart() throws {
        let file = try screenshot()
        settings.transferMode = .move
        _ = processor().process(settings: settings, bulk: false)
        var operations = ProcessingFileOperations()
        operations.remove = { url in
            if url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: url)
        }
        let first = processor(operations: operations).process(settings: settings, bulk: true)
        XCTAssertEqual(first.processed, 1)
        XCTAssertEqual(first.retained, 1)
        XCTAssertFalse(first.message.isEmpty)
        let second = processor(operations: operations).process(settings: settings, bulk: true)
        XCTAssertEqual(second.retained, 1)
        XCTAssertEqual(try outputs().count, 1)
        _ = processor().process(settings: settings, bulk: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try outputs().count, 1)
    }

    func testPreparedOutputIsRecoveredWithoutDuplicateAfterPublicationFailure() throws {
        let file = try screenshot()
        settings.transferMode = .move
        var operations = ProcessingFileOperations()
        operations.move = { _, _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: true).failed, 1)
        XCTAssertTrue(try outputs().isEmpty)
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
    }

    func testPublishedOutputIsRecoveredWhenCommitJournalWriteFails() throws {
        let file = try screenshot()
        settings.transferMode = .move
        var writes = 0
        let subject = ScreenshotProcessor(
            journalURL: journalURL, settleInterval: 0, minimumAge: 0,
            activeWindow: { ActiveWindowInfo(appName: "Test", windowTitle: "Test") },
            journalWrite: { data, url in
                writes += 1
                if writes == 3 { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            }
        )
        XCTAssertEqual(subject.process(settings: settings, bulk: true).failed, 1)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testChangedDestinationIsNeverUsedToJustifySourceDeletion() throws {
        let file = try screenshot()
        settings.transferMode = .move
        var operations = ProcessingFileOperations()
        operations.move = { from, to in
            try FileManager.default.moveItem(at: from, to: to)
            try Data("replaced".utf8).write(to: to, options: .atomic)
        }
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: true).failed, 1)
        XCTAssertEqual(processor().process(settings: settings, bulk: false).failed, 1)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testMissingDestinationAndFullDiskReportFailuresWithoutDeletingSource() throws {
        let file = try screenshot()
        settings.transferMode = .move
        var operations = ProcessingFileOperations()
        let diskError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        operations.copy = { _, _ in throw diskError }
        let diskResult = processor(operations: operations).process(settings: settings, bulk: true)
        XCTAssertEqual(diskResult.failed, 1)
        XCTAssertTrue(diskResult.message.contains(diskError.localizedDescription))
        try FileManager.default.removeItem(at: destination)
        let missingResult = processor().process(settings: settings, bulk: true)
        XCTAssertEqual(missingResult.failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptOrUnwritableJournalFailsClosed() throws {
        let file = try screenshot()
        settings.transferMode = .move
        let subject = ScreenshotProcessor(
            journalURL: journalURL, settleInterval: 0, minimumAge: 0,
            journalWrite: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )
        XCTAssertEqual(subject.process(settings: settings, bulk: true).failed, 1)
        try Data("not json".utf8).write(to: journalURL)
        XCTAssertEqual(processor().process(settings: settings, bulk: true).failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try outputs().isEmpty)
    }

    func testSameFolderAndNoExtendedAttributesDoNotReimportOutputs() throws {
        settings.destinationURL = source
        settings.filenameTemplate = "'Screenshot generated'"
        var operations = ProcessingFileOperations()
        operations.markGenerated = { _ in }
        _ = processor(operations: operations).process(settings: settings, bulk: false)
        try screenshot()
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: false).processed, 0)
        XCTAssertEqual(try outputs(in: source).count, 2)
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: true).processed, 1)
        XCTAssertEqual(try outputs(in: source).count, 3)
    }

    func testChildDestinationDoesNotBecomeInput() throws {
        settings.destinationURL = source.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: settings.destinationURL, withIntermediateDirectories: false)
        _ = processor().process(settings: settings, bulk: false)
        try screenshot()
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(processor().process(settings: settings, bulk: false).processed, 0)
        XCTAssertEqual(try outputs(in: settings.destinationURL).count, 1)
    }

    func testAliasedDestinationWithoutExtendedAttributesDoesNotReimportOutput() throws {
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        settings.destinationURL = alias
        settings.filenameTemplate = "'Screenshot generated'"
        var operations = ProcessingFileOperations()
        operations.markGenerated = { _ in }
        _ = processor(operations: operations).process(settings: settings, bulk: false)
        try screenshot()
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: false).processed, 1)
        XCTAssertEqual(processor(operations: operations).process(settings: settings, bulk: false).processed, 0)
        XCTAssertEqual(try outputs(in: source).count, 2)
    }

    func testNoDateSuffixAndOriginalFormats() throws {
        for (ext, type) in [("png", "public.png"), ("jpg", "public.jpeg"), ("tiff", "public.tiff")] {
            settings.screenshotDefaults.type = ext
            settings.transferMode = .move
            let data = try imageData(type: type)
            let file = try screenshot("Screenshot.\(ext)", data: data)
            XCTAssertEqual(processor().process(settings: settings, bulk: true).processed, 1, ext)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertTrue(try ScreenshotProcessor.isCompleteImage(destination.appendingPathComponent("Result.\(ext)")))
        }
    }

    func testActualWebPAndHEICConversion() throws {
        let file = try screenshot()
        for format in [OutputFormat.webp, .heic] {
            settings.outputFormat = format
            let result = processor().process(settings: settings, bulk: true)
            XCTAssertEqual(result.processed, 1, result.message)
            let output = destination.appendingPathComponent("Result.\(format.pathExtension!)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), result.message)
            XCTAssertTrue(try ScreenshotProcessor.isCompleteImage(output))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testOtherTargetsConvertOrExplicitlyFallBackToOriginal() throws {
        try screenshot()
        for format in [OutputFormat.avif, .bmp, .psd] {
            settings.outputFormat = format
            let before = try outputs().count
            let result = processor().process(settings: settings, bulk: true)
            XCTAssertEqual(result.processed, 1, result.message)
            XCTAssertEqual(result.failed, 0, result.message)
            XCTAssertEqual(try outputs().count, before + 1)
        }
        for output in try outputs() {
            XCTAssertTrue(try ScreenshotProcessor.isCompleteImage(output))
        }
    }

    func testMultipageTIFFFallsBackWithoutDiscardingFrames() throws {
        let data = try imageData(type: "public.tiff", count: 2)
        let file = try screenshot("Screenshot pages.tiff", data: data)
        settings.screenshotDefaults.type = "tiff"
        settings.outputFormat = .webp
        settings.transferMode = .move
        XCTAssertEqual(processor().process(settings: settings, bulk: true).processed, 1)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Result.tiff")), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPDFOriginalAndMultipageFallback() throws {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 20, height: 20)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            context.fill(box)
            context.endPDFPage()
        }
        context.closePDF()
        let file = try screenshot("Screenshot document.pdf", data: data as Data)
        settings.screenshotDefaults.type = "pdf"
        settings.outputFormat = .webp
        settings.transferMode = .move
        let result = processor().process(settings: settings, bulk: true)
        XCTAssertEqual(result.processed, 1, result.message)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Result.pdf")), data as Data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTruncatedImagesAreNotComplete() throws {
        for (ext, type) in [("png", "public.png"), ("jpg", "public.jpeg"), ("tiff", "public.tiff")] {
            let data = try imageData(type: type)
            for missingBytes in [1, 12, data.count / 2] {
                let file = try screenshot("Screenshot truncated.\(ext)", data: Data(data.dropLast(missingBytes)))
                XCTAssertFalse(try ScreenshotProcessor.isCompleteImage(file), "\(ext): missing \(missingBytes) bytes")
            }
        }
    }

    func testBlankAndOverlongNamesDoNotMoveSource() throws {
        let file = try screenshot()
        settings.transferMode = .move
        for template in ["   ", "'" + String(repeating: "a", count: 251) + "'"] {
            settings.filenameTemplate = template
            XCTAssertEqual(processor().process(settings: settings, bulk: true).failed, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            XCTAssertTrue(try outputs().isEmpty)
        }
        settings.transferMode = .copy
        settings.filenameTemplate = "'" + String(repeating: "a", count: 250) + "'"
        XCTAssertEqual(processor().process(settings: settings, bulk: true).processed, 1)
        XCTAssertEqual(processor().process(settings: settings, bulk: true).failed, 1)
        XCTAssertEqual(try outputs().count, 1)
    }

    func testCancellationStopsAtFileBoundary() throws {
        try screenshot("Screenshot a.png")
        try screenshot("Screenshot b.png")
        settings.transferMode = .move
        let cancellation = ProcessingCancellation()
        var operations = ProcessingFileOperations()
        operations.copy = { from, to in
            try FileManager.default.copyItem(at: from, to: to)
            cancellation.cancel()
        }
        let result = processor(operations: operations).process(settings: settings, bulk: true, cancellation: cancellation)
        XCTAssertEqual(result.processed, 1)
        XCTAssertEqual(try outputs().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Screenshot b.png").path))
    }
}
