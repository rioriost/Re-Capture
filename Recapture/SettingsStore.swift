import AppKit
import Foundation
import ServiceManagement

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

    @Published var screenshotDefaults: ScreenshotDefaults

    @Published private(set) var destinationURL: URL? {
        didSet { persistBookmark(destinationURL, key: Keys.destinationBookmark) }
    }

    @Published private(set) var screenshotLocationAccessURL: URL? {
        didSet { persistBookmark(screenshotLocationAccessURL, key: Keys.screenshotLocationBookmark) }
    }

    @Published private(set) var statusText = String(localized: "Idle")

    private let defaults = UserDefaults.standard

    init() {
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        transferMode = TransferMode(rawValue: defaults.string(forKey: Keys.transferMode) ?? "") ?? .move
        outputFormat = OutputFormat(rawValue: defaults.string(forKey: Keys.outputFormat) ?? "") ?? .webp
        outputQuality = defaults.object(forKey: Keys.outputQuality) as? Int ?? 85
        filenameTemplate = defaults.string(forKey: Keys.filenameTemplate) ?? "yyyyMMdd-HHmmss"
        screenshotDefaults = ScreenshotDefaults.current()
        if Self.isInAppContainer(screenshotDefaults.locationURL) {
            screenshotDefaults.locationURL = ScreenshotDefaults.defaultLocationURL
        }
        destinationURL = Self.restoredUserFolder(forKey: Keys.destinationBookmark)
        screenshotLocationAccessURL = Self.restoredUserFolder(forKey: Keys.screenshotLocationBookmark)
        if destinationURL == nil {
            statusText = String(localized: "Choose an output folder to start")
        }
    }

    var destinationDisplayText: String {
        destinationURL?.path ?? String(localized: "No output folder selected")
    }

    var startAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
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
        if let url, Self.isInAppContainer(url) {
            statusText = String(localized: "Choose a folder outside the app container")
            return false
        }

        destinationURL = url
        statusText = url == nil
            ? String(localized: "Choose an output folder to start")
            : String(localized: "Output folder selected")
        return true
    }

    @discardableResult
    func setScreenshotLocation(_ url: URL) -> Bool {
        guard !Self.isInAppContainer(url) else {
            statusText = String(localized: "Choose a folder outside the app container")
            return false
        }

        screenshotDefaults.locationURL = url
        screenshotLocationAccessURL = url
        statusText = String(localized: "Screenshot folder selected")
        return true
    }

    func applyScreenshotDefaults() {
        screenshotDefaults.apply()
        statusText = String(localized: "macOS screenshot settings updated")
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

    func startAccessingConfiguredDirectories() -> [URL] {
        var urls: [URL] = []
        if let screenshotLocationAccessURL {
            urls.append(screenshotLocationAccessURL)
        }
        if let destinationURL, destinationURL != screenshotLocationAccessURL {
            urls.append(destinationURL)
        }
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        return urls
    }

    func stopAccessing(_ urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func persistBookmark(_ url: URL?, key: String) {
        guard let url else {
            defaults.removeObject(forKey: key)
            return
        }

        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: key)
        } catch {
            statusText = String(
                format: String(localized: "Bookmark update failed: %@"),
                error.localizedDescription
            )
        }
    }

    private static func restoreBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return isStale ? nil : url
        } catch {
            return nil
        }
    }

    private static func restoredUserFolder(forKey key: String) -> URL? {
        guard let url = restoreBookmark(UserDefaults.standard.data(forKey: key)) else {
            return nil
        }

        if isInAppContainer(url) {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        return url
    }

    private static func isInAppContainer(_ url: URL) -> Bool {
        let containerURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let containerPath = containerURL.path
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
