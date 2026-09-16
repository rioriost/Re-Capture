import AppKit
import Foundation
import ServiceManagement

struct ResolvedBookmark {
    var url: URL
    var isStale: Bool
}

@MainActor
struct BookmarkAccess {
    var make: (URL) throws -> Data
    var resolve: (Data) throws -> ResolvedBookmark
    var save: (Data?, String, UserDefaults) throws -> Void
    var startAccessing: (URL) -> Bool
    var stopAccessing: (URL) -> Void

    static let live = BookmarkAccess(
        make: {
            try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        },
        resolve: {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: $0,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(url: url, isStale: isStale)
        },
        save: { data, key, defaults in
            let previousValue = defaults.object(forKey: key)
            if let data {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            guard defaults.synchronize() else {
                if let previousValue {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
                _ = defaults.synchronize()
                throw FolderAccessError.bookmarkSaveFailed
            }
        },
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() }
    )
}

enum FolderAccessError: LocalizedError {
    case appContainer
    case bookmarkSaveFailed
    case sourceNotSelected
    case scopeDenied(URL)

    var errorDescription: String? {
        switch self {
        case .appContainer:
            String(localized: "Choose a folder outside the app container")
        case .bookmarkSaveFailed:
            String(localized: "Could not save folder access. Select the folder again and retry.")
        case .sourceNotSelected:
            String(localized: "Choose a watched folder using the system picker")
        case .scopeDenied(let url):
            String(format: String(localized: "Cannot access %@. Reconnect the volume and select the folder again."), url.path)
        }
    }
}

struct ProcessingConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var folderAccessRevision: UInt64
    var snapshot: SettingsSnapshot?
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var transferMode: TransferMode {
        didSet { defaults.set(transferMode.rawValue, forKey: Keys.transferMode) }
    }

    @Published var outputFormat: OutputFormat {
        didSet { defaults.set(outputFormat.rawValue, forKey: Keys.outputFormat) }
    }

    @Published var outputQuality: Int {
        didSet { defaults.set(outputQuality, forKey: Keys.outputQuality) }
    }

    @Published var filenameTemplate: String {
        didSet { defaults.set(filenameTemplate, forKey: Keys.filenameTemplate) }
    }

    @Published private(set) var screenshotDefaults: ScreenshotDefaults
    @Published var screenshotDefaultsDraft: ScreenshotDefaults
    @Published private(set) var destinationURL: URL?
    @Published private(set) var screenshotLocationAccessURL: URL?
    @Published private(set) var folderAccessRevision: UInt64 = 0
    @Published private(set) var statusText = String(localized: "Idle")

    private let defaults: UserDefaults
    private let bookmarks: BookmarkAccess
    private let preferences: ScreenshotPreferences
    private var activeScopeCounts: [URL: Int] = [:]

    init(
        defaults: UserDefaults = .standard,
        bookmarks: BookmarkAccess = .live,
        preferences: ScreenshotPreferences = .live
    ) {
        self.defaults = defaults
        self.bookmarks = bookmarks
        self.preferences = preferences
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        transferMode = TransferMode(rawValue: defaults.string(forKey: Keys.transferMode) ?? "") ?? .move
        outputFormat = OutputFormat(rawValue: defaults.string(forKey: Keys.outputFormat) ?? "") ?? .webp
        outputQuality = defaults.object(forKey: Keys.outputQuality) as? Int ?? 85
        filenameTemplate = defaults.string(forKey: Keys.filenameTemplate) ?? "yyyyMMdd-HHmmss"
        screenshotDefaults = .fallback
        screenshotDefaultsDraft = .fallback
        destinationURL = nil
        screenshotLocationAccessURL = nil

        var errors: [String] = []
        do {
            let current = try preferences.read()
            screenshotDefaults = current
            screenshotDefaultsDraft = current
            if Self.isInAppContainer(screenshotDefaults.locationURL) {
                screenshotDefaults.locationURL = ScreenshotDefaults.defaultLocationURL
            }
        } catch {
            errors.append(error.localizedDescription)
        }
        do {
            destinationURL = try restoredUserFolder(forKey: Keys.destinationBookmark)
        } catch {
            errors.append(restoreFailure(folder: String(localized: "Destination"), error: error))
        }
        do {
            screenshotLocationAccessURL = try restoredUserFolder(forKey: Keys.screenshotLocationBookmark)
            if let screenshotLocationAccessURL {
                screenshotDefaults.locationURL = screenshotLocationAccessURL
            }
        } catch {
            errors.append(restoreFailure(folder: String(localized: "Watched folder"), error: error))
        }
        if !errors.isEmpty {
            statusText = errors.joined(separator: "\n")
        } else if screenshotLocationAccessURL == nil {
            statusText = String(localized: "Choose a watched folder using the system picker")
        } else if destinationURL == nil {
            statusText = String(localized: "Choose an output folder to start")
        }
    }

    var canApplyScreenshotDefaults: Bool {
        preferences.sandboxStatus() == .disabled
    }

    var destinationDisplayText: String {
        destinationURL?.path ?? String(localized: "No output folder selected")
    }

    var screenshotLocationDisplayText: String {
        screenshotLocationAccessURL?.path ?? String(localized: "No watched folder selected")
    }

    var snapshot: SettingsSnapshot? {
        guard let destinationURL, screenshotLocationAccessURL != nil else { return nil }
        return SettingsSnapshot(
            screenshotDefaults: screenshotDefaults,
            destinationURL: destinationURL,
            filenameTemplate: filenameTemplate,
            outputFormat: outputFormat,
            outputQuality: outputQuality,
            transferMode: transferMode
        )
    }

    var processingConfiguration: ProcessingConfiguration {
        ProcessingConfiguration(
            isEnabled: isEnabled,
            folderAccessRevision: folderAccessRevision,
            snapshot: snapshot
        )
    }

    var startAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                statusText = String(
                    format: String(localized: "Login item update failed: %@"),
                    error.localizedDescription
                )
            }
        }
    }

    @discardableResult
    func setDestinationURL(_ url: URL?) -> Bool {
        do {
            try persistBookmark(url, key: Keys.destinationBookmark)
            statusText = url == nil
                ? String(localized: "Choose an output folder to start")
                : String(localized: "Output folder selected")
            destinationURL = url
            folderAccessRevision &+= 1
            return true
        } catch {
            statusText = bookmarkFailure(error)
            return false
        }
    }

    @discardableResult
    func setScreenshotLocation(_ url: URL) -> Bool {
        do {
            try persistBookmark(url, key: Keys.screenshotLocationBookmark)
            statusText = String(localized: "Watched folder selected. The macOS save location was not changed.")
            screenshotLocationAccessURL = url
            var applied = screenshotDefaults
            applied.locationURL = url
            screenshotDefaults = applied
            folderAccessRevision &+= 1
            return true
        } catch {
            statusText = bookmarkFailure(error)
            return false
        }
    }

    @discardableResult
    func applyScreenshotDefaults() -> Bool {
        do {
            switch preferences.sandboxStatus() {
            case .enabled: throw ScreenshotPreferencesError.sandboxed
            case .unknown: throw ScreenshotPreferencesError.sandboxStatusUnknown
            case .disabled: break
            }
            let draft = screenshotDefaultsDraft
            guard !Self.isInAppContainer(draft.locationURL) else { throw FolderAccessError.appContainer }
            try preferences.write(draft)
            statusText = String(localized: "macOS screenshot settings updated. The watched folder is unchanged.")
            commitScreenshotDefaults(draft)
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshScreenshotDefaults() -> Bool {
        do {
            let current = try preferences.read()
            statusText = canApplyScreenshotDefaults
                ? String(localized: "Screenshot preferences refreshed. The watched folder is unchanged.")
                : String(localized: "Available preferences refreshed; sandbox reads may not reflect macOS settings. Confirm the save location in Screenshot and select the same watched folder.")
            screenshotDefaultsDraft = current
            commitScreenshotDefaults(current)
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func openScreenshotSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screencaptureui") else {
            statusText = String(localized: "Press Shift-Command-5 to open Screenshot, then use Options to choose the save location.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                self?.statusText = String(
                    format: String(localized: "Could not open Screenshot: %@. Press Shift-Command-5 instead."),
                    message
                )
            }
        }
    }

    func openDestinationInFinder() {
        guard let destinationURL else {
            statusText = String(localized: "Choose an output folder to start")
            return
        }
        NSWorkspace.shared.open(destinationURL)
    }

    func setStatus(_ text: String) {
        statusText = text
    }

    func startAccessingConfiguredDirectories() throws -> [URL] {
        var started: [URL] = []
        var paths: Set<String> = []
        do {
            guard let screenshotLocationAccessURL else { throw FolderAccessError.sourceNotSelected }
            for url in [screenshotLocationAccessURL, destinationURL].compactMap({ $0 }) {
                guard paths.insert(url.standardizedFileURL.path).inserted else { continue }
                guard bookmarks.startAccessing(url) else { throw FolderAccessError.scopeDenied(url) }
                activeScopeCounts[url, default: 0] += 1
                started.append(url)
            }
            return started
        } catch {
            stopAccessing(started)
            statusText = error.localizedDescription
            throw error
        }
    }

    func stopAccessing(_ urls: [URL]) {
        for url in urls {
            guard let count = activeScopeCounts[url], count > 0 else { continue }
            bookmarks.stopAccessing(url)
            if count == 1 {
                activeScopeCounts.removeValue(forKey: url)
            } else {
                activeScopeCounts[url] = count - 1
            }
        }
    }

    private func commitScreenshotDefaults(_ value: ScreenshotDefaults) {
        var applied = value
        // Processing uses the user's security-scoped selection, not a foreign preference domain.
        applied.locationURL = screenshotLocationAccessURL ?? screenshotDefaults.locationURL
        screenshotDefaults = applied
    }

    private func persistBookmark(_ url: URL?, key: String) throws {
        guard let url else {
            try bookmarks.save(nil, key, defaults)
            return
        }
        guard !Self.isInAppContainer(url) else { throw FolderAccessError.appContainer }
        let data = try bookmarks.make(url)
        try bookmarks.save(data, key, defaults)
    }

    private func restoredUserFolder(forKey key: String) throws -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let resolved = try bookmarks.resolve(data)
        guard !Self.isInAppContainer(resolved.url) else { throw FolderAccessError.appContainer }
        if resolved.isStale {
            guard bookmarks.startAccessing(resolved.url) else { throw FolderAccessError.scopeDenied(resolved.url) }
            defer { bookmarks.stopAccessing(resolved.url) }
            try persistBookmark(resolved.url, key: key)
        }
        return resolved.url
    }

    private func bookmarkFailure(_ error: Error) -> String {
        String(format: String(localized: "Bookmark update failed: %@"), error.localizedDescription)
    }

    private func restoreFailure(folder: String, error: Error) -> String {
        String(
            format: String(localized: "Could not restore %@: %@. Select the folder again."),
            folder,
            error.localizedDescription
        )
    }

    private static func isInAppContainer(_ url: URL) -> Bool {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard containerPath.contains("/Library/Containers/") else { return false }
        let path = url.standardizedFileURL.path
        return path == containerPath || path.hasPrefix(containerPath + "/")
    }

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let transferMode = "transferMode"
        static let outputFormat = "outputFormat"
        static let outputQuality = "outputQuality"
        static let filenameTemplate = "filenameTemplate"
        static let destinationBookmark = "destinationBookmark"
        static let screenshotLocationBookmark = "screenshotLocationBookmark"
    }
}
