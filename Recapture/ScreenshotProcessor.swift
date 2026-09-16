import Foundation
import ImageIO

protocol ScreenshotProcessing: Sendable {
    func process(settings: SettingsSnapshot, bulk: Bool, cancellation: ProcessingCancellation) -> ProcessResult
}

final class ProcessingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

struct ProcessingFileOperations {
    var copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    var remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    var markGenerated: (URL) -> Void = { url in
        var marker: UInt8 = 1
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            // The journal is authoritative on filesystems without extended attributes.
            _ = setxattr(path, "st.rio.recapture.generated", &marker, 1, 0, 0)
        }
    }
}

final class ScreenshotProcessor: ScreenshotProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private let journal: ProcessingJournal
    private let operations: ProcessingFileOperations
    private let settleInterval: TimeInterval
    private let minimumAge: TimeInterval
    private let activeWindow: () -> ActiveWindowInfo

    init(
        journalURL: URL = ProcessingJournal.defaultURL,
        operations: ProcessingFileOperations = ProcessingFileOperations(),
        settleInterval: TimeInterval = 0.2,
        minimumAge: TimeInterval = 0.4,
        activeWindow: @escaping () -> ActiveWindowInfo = { ActiveWindowInfo.current },
        journalWrite: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        journal = ProcessingJournal(url: journalURL, write: journalWrite)
        self.operations = operations
        self.settleInterval = settleInterval
        self.minimumAge = minimumAge
        self.activeWindow = activeWindow
    }

    func process(
        settings: SettingsSnapshot,
        bulk: Bool,
        cancellation: ProcessingCancellation = ProcessingCancellation()
    ) -> ProcessResult {
        lock.withLock {
            processSerially(settings: settings, bulk: bulk, cancellation: cancellation)
        }
    }

    private func processSerially(settings: SettingsSnapshot, bulk: Bool, cancellation: ProcessingCancellation) -> ProcessResult {
        var result = ProcessResult(processed: 0, message: "")
        var issues: [String] = []
        var fallbacks = 0

        do {
            try TemplateRenderer.validate(template: settings.filenameTemplate)
            var state = try journal.load()
            let sourceDirectory = settings.screenshotDefaults.locationURL.resolvingSymlinksInPath().standardizedFileURL
            let files = try FileManager.default.contentsOfDirectory(
                at: sourceDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let candidates = files.filter {
                isCandidate($0, defaults: settings.screenshotDefaults)
                    && (settings.includedSourcePaths?.contains(FileStamp.canonicalPath($0)) ?? true)
            }
            guard !cancellation.isCancelled else { return result }

            if state.initializedDirectories.insert(sourceDirectory.path).inserted {
                if !bulk {
                    for file in candidates {
                        let stamp = try FileStamp.read(file)
                        state.ignoredSources.insert(stamp.key(for: file))
                    }
                }
                try journal.save(state)
                if !bulk {
                    result.message = String(localized: "Watching for new screenshots. Use bulk processing for existing files.")
                    return result
                }
            }

            var recovered: Set<String> = []
            for (key, record) in state.records.sorted(by: { $0.key < $1.key })
            where !record.committed && record.sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == sourceDirectory {
                if cancellation.isCancelled { break }
                if let included = settings.includedSourcePaths, !included.contains(FileStamp.canonicalPath(record.sourceURL)) {
                    continue
                }
                do {
                    let retained = try finishRecord(key: key, state: &state)
                    result.processed += 1
                    if record.fallback { fallbacks += 1 }
                    if let retained {
                        result.retained += 1
                        issues.append("\(record.sourceURL.lastPathComponent): \(retained)")
                    }
                } catch {
                    result.failed += 1
                    issues.append("\(record.sourceURL.lastPathComponent): \(error.localizedDescription)")
                    state = try journal.load()
                }
                recovered.insert(key)
            }

            for sourceURL in candidates {
                if cancellation.isCancelled { break }
                do {
                    if !FileManager.default.fileExists(atPath: sourceURL.path) { continue }
                    let stamp = try FileStamp.read(sourceURL)
                    let key = stamp.key(for: sourceURL)
                    if recovered.contains(key) { continue }
                    if state.generatedFiles.contains(key) || hasGeneratedMarker(sourceURL) { continue }
                    if let record = state.records[key], !record.committed || record.needsSourceRemoval {
                        let retained = try finishRecord(key: key, state: &state)
                        if let retained {
                            result.retained += 1
                            issues.append("\(sourceURL.lastPathComponent): \(retained)")
                        }
                        continue
                    }
                    if !bulk, state.ignoredSources.contains(key) { continue }
                    if !bulk, state.records[key]?.committed == true { continue }

                    guard stamp.size > 0, Date().timeIntervalSince(stamp.modificationDate) >= minimumAge else {
                        throw ProcessingError.incomplete
                    }
                    Thread.sleep(forTimeInterval: settleInterval)
                    guard try FileStamp.read(sourceURL) == stamp else { throw ProcessingError.sourceChanged }
                    if cancellation.isCancelled { break }

                    let date = (try sourceURL.resourceValues(forKeys: [.creationDateKey])).creationDate ?? stamp.modificationDate
                    let baseName = try TemplateRenderer.render(
                        template: settings.filenameTemplate,
                        date: date,
                        sequence: state.sequence,
                        activeWindowInfo: activeWindow()
                    )
                    let record = try prepareTransfer(
                        sourceURL: sourceURL, stamp: stamp, baseName: baseName, settings: settings
                    )
                    state.records[key] = record
                    state.generatedFiles.insert(record.outputStamp.key(for: record.destinationURL))
                    state.sequence += 1
                    do {
                        // Persist the intended output before publishing it, so restart recovery cannot duplicate it.
                        try journal.save(state)
                    } catch {
                        try operations.remove(record.stagingURL)
                        throw error
                    }
                    let retained = try finishRecord(key: key, state: &state)
                    result.processed += 1
                    if record.fallback { fallbacks += 1 }
                    if let retained {
                        result.retained += 1
                        issues.append("\(sourceURL.lastPathComponent): \(retained)")
                    }
                } catch ProcessingError.incomplete {
                    result.deferred += 1
                    result.retrySuggested = true
                    result.retrySourcePaths.insert(FileStamp.canonicalPath(sourceURL))
                    issues.append("\(sourceURL.lastPathComponent): \(ProcessingError.incomplete.localizedDescription)")
                } catch ProcessingError.sourceChanged {
                    result.deferred += 1
                    result.retrySuggested = true
                    result.retrySourcePaths.insert(FileStamp.canonicalPath(sourceURL))
                    issues.append("\(sourceURL.lastPathComponent): \(ProcessingError.sourceChanged.localizedDescription)")
                } catch {
                    result.failed += 1
                    issues.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
                    // Reload durable state after any failed operation before processing another file.
                    state = try journal.load()
                }
            }
        } catch {
            result.failed += 1
            issues.append(error.localizedDescription)
        }

        result.message = resultMessage(result, fallbacks: fallbacks, issues: issues)
        return result
    }

    private func prepareTransfer(
        sourceURL: URL, stamp: FileStamp, baseName: String, settings: SettingsSnapshot
    ) throws -> TransferRecord {
        let snapshot = temporaryURL(directory: settings.destinationURL, ext: sourceURL.pathExtension)
        var output = snapshot
        do {
            try operations.copy(sourceURL, snapshot)
            guard try FileStamp.read(sourceURL) == stamp else { throw ProcessingError.sourceChanged }
            guard try Self.isCompleteImage(snapshot) else { throw ProcessingError.incomplete }

            var fallback = false
            if settings.outputFormat != .original, let ext = settings.outputFormat.pathExtension {
                let converted = temporaryURL(directory: settings.destinationURL, ext: ext)
                do {
                    if try ImageConverter.convert(
                        sourceURL: snapshot, destinationURL: converted,
                        outputFormat: settings.outputFormat, quality: settings.outputQuality
                    ), try Self.isCompleteImage(converted) {
                        output = converted
                        try operations.remove(snapshot)
                    } else {
                        if FileManager.default.fileExists(atPath: converted.path) { try operations.remove(converted) }
                        fallback = true
                    }
                } catch {
                    if FileManager.default.fileExists(atPath: converted.path) { try operations.remove(converted) }
                    throw error
                }
            }
            guard try FileStamp.read(sourceURL) == stamp else { throw ProcessingError.sourceChanged }
            let destination = try uniqueURL(
                directory: settings.destinationURL, baseName: baseName, ext: output.pathExtension
            )
            return TransferRecord(
                sourcePath: sourceURL.path, sourceStamp: stamp,
                destinationPath: destination.path, stagingPath: output.path,
                outputStamp: try FileStamp.read(output), committed: false,
                needsSourceRemoval: settings.transferMode == .move, fallback: fallback
            )
        } catch {
            if FileManager.default.fileExists(atPath: snapshot.path) { try operations.remove(snapshot) }
            if output != snapshot, FileManager.default.fileExists(atPath: output.path) { try operations.remove(output) }
            throw error
        }
    }

    private func finishRecord(key: String, state: inout ProcessingJournal.State) throws -> String? {
        guard var record = state.records[key] else { return nil }
        if !record.committed {
            if !FileManager.default.fileExists(atPath: record.destinationPath) {
                guard try FileStamp.read(record.stagingURL) == record.outputStamp,
                      try Self.isCompleteImage(record.stagingURL) else {
                    throw ProcessingError.outputChanged
                }
                try operations.move(record.stagingURL, record.destinationURL)
            }
            guard try FileStamp.read(record.destinationURL) == record.outputStamp else {
                throw ProcessingError.outputChanged
            }
            operations.markGenerated(record.destinationURL)
            record.committed = true
            state.records[key] = record
            try journal.save(state)
        }

        guard record.needsSourceRemoval else { return nil }
        do {
            guard try FileStamp.read(record.destinationURL) == record.outputStamp,
                  try Self.isCompleteImage(record.destinationURL) else {
                throw ProcessingError.outputChanged
            }
            do {
                guard try FileStamp.read(record.sourceURL) == record.sourceStamp else {
                    throw ProcessingError.sourceChanged
                }
                try operations.remove(record.sourceURL)
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
                // A crash may occur after removal but before the completed journal write.
            }
        } catch {
            return error.localizedDescription
        }
        record.needsSourceRemoval = false
        state.records[key] = record
        try journal.save(state)
        return nil
    }

    private func isCandidate(_ url: URL, defaults: ScreenshotDefaults) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "pdf", "tif", "tiff"].contains(ext) else { return false }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return false }
        if hasAttribute("com.apple.metadata:kMDItemIsScreenCapture", at: url) { return true }
        let extensions: [String]
        switch ScreenshotSourceFormat.fromScreencaptureValue(defaults.type) {
        case .png: extensions = ["png"]
        case .jpeg: extensions = ["jpg", "jpeg"]
        case .pdf: extensions = ["pdf"]
        case .tiff: extensions = ["tif", "tiff"]
        }
        guard extensions.contains(ext) else { return false }
        let stem = url.deletingPathExtension().lastPathComponent
        return [defaults.namePrefix, "Screenshot", "Screen Shot"].contains {
            !$0.isEmpty && (stem == $0 || stem.hasPrefix($0 + " "))
        }
    }

    static func isCompleteImage(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        // ImageIO can decode PNG/JPEG pixels successfully before their final marker arrives.
        if ext == "png",
           !data.suffix(12).elementsEqual([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]) {
            return false
        }
        if ["jpg", "jpeg"].contains(ext), !data.suffix(2).elementsEqual([255, 217]) {
            return false
        }
        if ext == "webp" {
            guard data.count >= 12 else { return false }
            let declaredSize = (0..<4).reduce(UInt64(0)) { $0 | (UInt64(data[4 + $1]) << (8 * $1)) }
            guard declaredSize + 8 == UInt64(data.count) else { return false }
        }
        if ext == "pdf" {
            guard let trailer = String(data: data.suffix(32), encoding: .ascii),
                  trailer.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("%%EOF"),
                  let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider), document.isUnlocked, document.numberOfPages > 0 else {
                return false
            }
            return (1...document.numberOfPages).allSatisfy { document.page(at: $0) != nil }
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0 else { return false }
        return (0..<CGImageSourceGetCount(source)).allSatisfy { index in
            CGImageSourceCreateImageAtIndex(
                source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            ) != nil && CGImageSourceGetStatusAtIndex(source, index) == .statusComplete
        }
    }

    private func hasAttribute(_ name: String, at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, name, nil, 0, 0, 0) >= 0
        }
    }

    private func hasGeneratedMarker(_ url: URL) -> Bool {
        hasAttribute("st.rio.recapture.generated", at: url)
    }

    private func temporaryURL(directory: URL, ext: String) -> URL {
        directory.appendingPathComponent(".\(UUID().uuidString).tmp.\(ext)")
    }

    private func uniqueURL(directory: URL, baseName: String, ext: String) throws -> URL {
        var index = 1
        while true {
            let suffix = index == 1 ? "" : "-\(index)"
            let name = "\(baseName)\(suffix).\(ext)"
            guard name.utf8.count <= 255 else { throw FilenameError.tooLong }
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func resultMessage(_ result: ProcessResult, fallbacks: Int, issues: [String]) -> String {
        let noun = result.processed == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        var message = String(format: String(localized: "Processed %d %@"), result.processed, noun)
        if fallbacks > 0 {
            message += String(format: String(localized: " (%d saved in original format)"), fallbacks)
        }
        if result.failed > 0 { message += String(format: String(localized: "; %d failed"), result.failed) }
        if result.deferred > 0 { message += String(format: String(localized: "; %d deferred"), result.deferred) }
        if result.retained > 0 { message += String(format: String(localized: "; %d originals retained"), result.retained) }
        if !issues.isEmpty { message += ": " + issues.joined(separator: "; ") }
        return message
    }
}

struct SettingsSnapshot: Equatable, Sendable {
    var screenshotDefaults: ScreenshotDefaults
    var destinationURL: URL
    var filenameTemplate: String
    var outputFormat: OutputFormat
    var outputQuality: Int
    var transferMode: TransferMode
    var includedSourcePaths: Set<String>? = nil
}

struct ProcessResult: Sendable {
    var processed: Int
    var message: String
    var failed = 0
    var deferred = 0
    var retained = 0
    var retrySuggested = false
    var retrySourcePaths: Set<String> = []
}
