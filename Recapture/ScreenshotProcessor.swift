import Foundation

final class ScreenshotProcessor: @unchecked Sendable {
    private var sequence = 1
    private var processedAutomaticSources: Set<String> = []
    private var generatedAutomaticFiles: Set<String> = []
    private let generatedXattrName = "st.rio.recapture.generated"

    func process(settings: SettingsSnapshot, bulk: Bool) -> ProcessResult {
        let fileManager = FileManager.default
        let sourceDirectory = settings.screenshotDefaults.locationURL
        let destinationDirectory = settings.destinationURL

        guard let names = try? fileManager.contentsOfDirectory(atPath: sourceDirectory.path) else {
            return ProcessResult(
                processed: 0,
                message: String(
                    format: String(localized: "Cannot read %@"),
                    sourceDirectory.path
                )
            )
        }

        var processed = 0
        var conversionFallbacks = 0
        for name in names.sorted() {
            let sourceURL = sourceDirectory.appendingPathComponent(name)
            guard isCandidate(sourceURL: sourceURL, name: name, defaults: settings.screenshotDefaults) else { continue }
            if hasGeneratedMarker(sourceURL) { continue }
            if !bulk, !isStableFile(sourceURL) { continue }
            guard bulk || shouldProcessAutomatically(sourceURL) else { continue }

            let date = fileDate(sourceURL) ?? Date()
            let activeWindow = ActiveWindowInfo.current
            let baseName = TemplateRenderer.render(
                template: settings.filenameTemplate,
                date: date,
                sequence: sequence,
                activeWindowInfo: activeWindow
            )
            sequence += 1

            switch transfer(sourceURL: sourceURL, destinationDirectory: destinationDirectory, baseName: baseName, settings: settings) {
            case .converted(let destinationURL), .original(let destinationURL):
                rememberAutomaticSource(sourceURL)
                rememberGeneratedFile(destinationURL)
                processed += 1
            case .fallback(let destinationURL):
                rememberAutomaticSource(sourceURL)
                rememberGeneratedFile(destinationURL)
                processed += 1
                conversionFallbacks += 1
            case .failed:
                break
            }
        }

        let noun = processed == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let baseMessage = String(
            format: String(localized: "Processed %d %@"),
            processed,
            noun
        )
        let fallbackText = conversionFallbacks > 0
            ? String(
                format: String(localized: " (%d saved in original format)"),
                conversionFallbacks
            )
            : ""
        return ProcessResult(processed: processed, message: baseMessage + fallbackText)
    }

    private func isCandidate(sourceURL: URL, name: String, defaults: ScreenshotDefaults) -> Bool {
        let pathExtension = sourceURL.pathExtension.lowercased()
        guard allSourceExtensions.contains(pathExtension) else { return false }
        if hasScreenshotMetadata(sourceURL) { return true }
        guard sourceExtensions(for: defaults.type).contains(pathExtension) else { return false }
        guard name.hasPrefix(defaults.namePrefix + " ") || name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ") else {
            return false
        }
        return true
    }

    private var allSourceExtensions: Set<String> {
        ["png", "jpg", "jpeg", "pdf", "tif", "tiff"]
    }

    private func sourceExtensions(for type: String) -> Set<String> {
        switch ScreenshotSourceFormat.fromScreencaptureValue(type) {
        case .png:
            ["png"]
        case .jpeg:
            ["jpg", "jpeg"]
        case .pdf:
            ["pdf"]
        case .tiff:
            ["tif", "tiff"]
        }
    }

    private func fileDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    private func isStableFile(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
            values.isRegularFile == true,
            let modified = values.contentModificationDate,
            let firstSize = values.fileSize
        else {
            return false
        }

        guard Date().timeIntervalSince(modified) >= 0.4 else { return false }
        Thread.sleep(forTimeInterval: 0.2)

        let secondSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return firstSize == secondSize
    }

    private func transfer(sourceURL: URL, destinationDirectory: URL, baseName: String, settings: SettingsSnapshot) -> TransferOutcome {
        let fileManager = FileManager.default
        if settings.outputFormat != .original, let outputExtension = settings.outputFormat.pathExtension {
            let destinationURL = uniqueURL(directoryURL: destinationDirectory, baseName: baseName, ext: outputExtension)
            let temporaryURL = temporaryURL(for: destinationURL)
            try? fileManager.removeItem(at: temporaryURL)

            if ImageConverter.convert(
                sourceURL: sourceURL,
                destinationURL: temporaryURL,
                outputFormat: settings.outputFormat,
                quality: settings.outputQuality
            ), isValidGeneratedFile(temporaryURL) {
                do {
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                } catch {
                    try? fileManager.removeItem(at: temporaryURL)
                    return .failed
                }

                guard isValidGeneratedFile(destinationURL) else {
                    try? fileManager.removeItem(at: destinationURL)
                    return .failed
                }

                if settings.transferMode == .move {
                    do {
                        try fileManager.removeItem(at: sourceURL)
                    } catch {
                        return .failed
                    }
                }
                markGenerated(destinationURL)
                return .converted(destinationURL)
            }

            try? fileManager.removeItem(at: temporaryURL)
        }

        let destinationURL = uniqueURL(directoryURL: destinationDirectory, baseName: baseName, ext: sourceURL.pathExtension)
        let temporaryURL = temporaryURL(for: destinationURL)
        try? fileManager.removeItem(at: temporaryURL)

        do {
            switch settings.transferMode {
            case .move:
                try fileManager.copyItem(at: sourceURL, to: temporaryURL)
                guard isValidGeneratedFile(temporaryURL) else {
                    try? fileManager.removeItem(at: temporaryURL)
                    return .failed
                }
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                guard isValidGeneratedFile(destinationURL) else {
                    try? fileManager.removeItem(at: destinationURL)
                    return .failed
                }
                try fileManager.removeItem(at: sourceURL)
            case .copy:
                try fileManager.copyItem(at: sourceURL, to: temporaryURL)
                guard isValidGeneratedFile(temporaryURL) else {
                    try? fileManager.removeItem(at: temporaryURL)
                    return .failed
                }
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                guard isValidGeneratedFile(destinationURL) else {
                    try? fileManager.removeItem(at: destinationURL)
                    return .failed
                }
            }
            markGenerated(destinationURL)
            return settings.outputFormat == .original ? .original(destinationURL) : .fallback(destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return .failed
        }
    }

    private func isValidGeneratedFile(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let size = values.fileSize
        else {
            return false
        }
        return size > 0
    }

    private func temporaryURL(for destinationURL: URL) -> URL {
        let id = UUID().uuidString
        let name = ".\(destinationURL.deletingPathExtension().lastPathComponent).\(id).tmp.\(destinationURL.pathExtension)"
        return destinationURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func uniqueURL(directoryURL: URL, baseName: String, ext: String) -> URL {
        var candidate = directoryURL.appendingPathComponent("\(baseName).\(ext)")
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName)-\(index).\(ext)")
            index += 1
        }

        return candidate
    }

    private func shouldProcessAutomatically(_ url: URL) -> Bool {
        guard let key = fileKey(url) else { return false }
        return !processedAutomaticSources.contains(key) && !generatedAutomaticFiles.contains(key)
    }

    private func rememberAutomaticSource(_ url: URL) {
        guard let key = fileKey(url) else { return }
        processedAutomaticSources.insert(key)
    }

    private func rememberGeneratedFile(_ url: URL) {
        guard let key = fileKey(url) else { return }
        generatedAutomaticFiles.insert(key)
    }

    private func fileKey(_ url: URL) -> String? {
        guard
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let modified = values.contentModificationDate,
            let size = values.fileSize
        else {
            return nil
        }

        return [
            url.standardizedFileURL.path,
            String(size),
            String(modified.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func hasGeneratedMarker(_ url: URL) -> Bool {
        if let key = fileKey(url), generatedAutomaticFiles.contains(key) {
            return true
        }

        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, generatedXattrName, nil, 0, 0, 0) >= 0
        }
    }

    private func hasScreenshotMetadata(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }

    private func markGenerated(_ url: URL) {
        var marker: UInt8 = 1
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = setxattr(path, generatedXattrName, &marker, 1, 0, 0)
        }
    }
}

private enum TransferOutcome {
    case converted(URL)
    case original(URL)
    case fallback(URL)
    case failed
}

struct SettingsSnapshot {
    var screenshotDefaults: ScreenshotDefaults
    var destinationURL: URL
    var filenameTemplate: String
    var outputFormat: OutputFormat
    var outputQuality: Int
    var transferMode: TransferMode
}

struct ProcessResult {
    var processed: Int
    var message: String
}
