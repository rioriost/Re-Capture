import AppKit
import CoreServices
import Foundation

private let defaultsDomain = "com.apple.screencapture" as CFString
private let appDefaults = UserDefaults(suiteName: "st.rio.screenshot-renamer") ?? .standard
private let enabledDefaultsKey = "enabled"
private let outputType = "webp"
private let webpQuality = "85"
private let debounceSeconds: TimeInterval = 0.7
private let retrySeconds: TimeInterval = 1.0

struct ScreenshotSettings: Equatable {
    let location: String
    let prefix: String
    let type: String

    static func current() -> ScreenshotSettings {
        CFPreferencesAppSynchronize(defaultsDomain)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let location = CFPreferencesCopyAppValue("location" as CFString, defaultsDomain) as? String
        let prefix = CFPreferencesCopyAppValue("name" as CFString, defaultsDomain) as? String
        let type = CFPreferencesCopyAppValue("type" as CFString, defaultsDomain) as? String

        return ScreenshotSettings(
            location: NSString(string: location ?? "\(home)/Desktop").expandingTildeInPath,
            prefix: prefix ?? "Screen Shot",
            type: (type ?? "png").lowercased()
        )
    }
}

final class ScreenshotRenamer {
    private let queue = DispatchQueue(label: "screenshot-renamer")
    private var stream: FSEventStreamRef?
    private var settings = ScreenshotSettings.current()
    private var pendingWorkItem: DispatchWorkItem?
    private var isProcessing = false
    private var isEnabled = false

    private lazy var converter: Converter = Converter.detect()

    func setEnabled(_ enabled: Bool) {
        queue.async {
            guard enabled != self.isEnabled else { return }

            self.isEnabled = enabled
            if enabled {
                self.settings = ScreenshotSettings.current()
                self.startStream(for: self.settings)
                self.scheduleProcessing(after: debounceSeconds)
            } else {
                self.pendingWorkItem?.cancel()
                self.pendingWorkItem = nil
                self.stopStream()
                print("Screenshot renamer is off")
            }
        }
    }

    private func startStream(for settings: ScreenshotSettings) {
        stopStream()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard
            let newStream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    let renamer = Unmanaged<ScreenshotRenamer>.fromOpaque(info)
                        .takeUnretainedValue()
                    renamer.eventArrived()
                },
                &context,
                [settings.location] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                debounceSeconds,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            )
        else {
            fputs("Failed to create FSEvent stream for \(settings.location)\n", stderr)
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
        print("Watching \(settings.location) for \(settings.prefix)*.\(settings.type)")
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func eventArrived() {
        queue.async {
            guard self.isEnabled else { return }

            let latest = ScreenshotSettings.current()
            if latest != self.settings {
                self.settings = latest
                self.startStream(for: latest)
            }
            self.scheduleProcessing(after: debounceSeconds)
        }
    }

    private func scheduleProcessing(after delay: TimeInterval) {
        guard isEnabled else { return }

        pendingWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.processScreenshots()
        }
        pendingWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func processScreenshots() {
        guard isEnabled else { return }

        if isProcessing {
            scheduleProcessing(after: retrySeconds)
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let currentSettings = ScreenshotSettings.current()
        if currentSettings != settings {
            settings = currentSettings
            startStream(for: currentSettings)
        }

        let directoryURL = URL(fileURLWithPath: currentSettings.location, isDirectory: true)
        let fileManager = FileManager.default

        guard let names = try? fileManager.contentsOfDirectory(atPath: currentSettings.location)
        else {
            return
        }

        let pattern =
            "^" + NSRegularExpression.escapedPattern(for: currentSettings.prefix)
            + #" ([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{1,2})\.([0-9]{2})\.([0-9]{2}).*"#
            + NSRegularExpression.escapedPattern(for: "." + currentSettings.type) + "$"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            fputs("Invalid screenshot filename pattern: \(pattern)\n", stderr)
            return
        }

        var needsRetry = false

        for name in names {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard let match = regex.firstMatch(in: name, range: range) else { continue }

            let sourceURL = directoryURL.appendingPathComponent(name)
            guard isStableFile(sourceURL) else {
                needsRetry = true
                continue
            }

            let year = capture(match, in: name, at: 1)
            let month = capture(match, in: name, at: 2)
            let day = capture(match, in: name, at: 3)
            let hour = String(format: "%02d", Int(capture(match, in: name, at: 4)) ?? 0)
            let minute = capture(match, in: name, at: 5)
            let second = capture(match, in: name, at: 6)
            let baseName = "\(year)\(month)\(day)\(hour)\(minute)\(second)"

            renameOrConvert(
                sourceURL: sourceURL, directoryURL: directoryURL, baseName: baseName,
                originalType: currentSettings.type)
        }

        if needsRetry {
            scheduleProcessing(after: retrySeconds)
        }
    }
    private func capture(_ match: NSTextCheckingResult, in string: String, at index: Int) -> String
    {
        guard let range = Range(match.range(at: index), in: string) else { return "" }
        return String(string[range])
    }

    private func isStableFile(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
            ]),
            values.isRegularFile == true,
            let modified = values.contentModificationDate,
            let firstSize = values.fileSize
        else {
            return false
        }

        guard Date().timeIntervalSince(modified) >= 0.4 else {
            return false
        }

        Thread.sleep(forTimeInterval: 0.2)

        guard let secondSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            return false
        }

        return firstSize == secondSize
    }

    private func renameOrConvert(
        sourceURL: URL, directoryURL: URL, baseName: String, originalType: String
    ) {
        if outputType == "webp", let converterCommand = converter.command {
            let destinationURL = uniqueURL(
                directoryURL: directoryURL, baseName: baseName, ext: outputType)
            if converterCommand.convert(sourceURL: sourceURL, destinationURL: destinationURL) {
                try? FileManager.default.removeItem(at: sourceURL)
                print(
                    "Converted \(sourceURL.lastPathComponent) -> \(destinationURL.lastPathComponent)"
                )
                return
            }
        }

        let fallbackURL = uniqueURL(
            directoryURL: directoryURL, baseName: baseName, ext: originalType)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: fallbackURL)
            print("Renamed \(sourceURL.lastPathComponent) -> \(fallbackURL.lastPathComponent)")
        } catch {
            fputs("Failed to move \(sourceURL.path): \(error)\n", stderr)
        }
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let renamer = ScreenshotRenamer()
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var isEnabled: Bool

    override init() {
        if appDefaults.object(forKey: enabledDefaultsKey) == nil {
            isEnabled = true
        } else {
            isEnabled = appDefaults.bool(forKey: enabledDefaultsKey)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        applyEnabled(isEnabled, persist: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        renamer.setEnabled(false)
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()

        let toggle = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Screenshot Renamer", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        toggleItem = toggle
        updateMenu()
    }

    private func applyEnabled(_ enabled: Bool, persist: Bool) {
        isEnabled = enabled
        if persist {
            appDefaults.set(enabled, forKey: enabledDefaultsKey)
        }

        renamer.setEnabled(enabled)
        updateMenu()
    }

    private func updateMenu() {
        toggleItem?.title = isEnabled ? "Turn Off" : "Turn On"
        toggleItem?.state = isEnabled ? .on : .off

        let title = isEnabled ? "SR On" : "SR Off"
        statusItem?.button?.title = title
        statusItem?.button?.toolTip = "Screenshot Renamer: \(isEnabled ? "On" : "Off")"
    }

    @objc private func toggleEnabled() {
        applyEnabled(!isEnabled, persist: true)
    }

    @objc private func quit() {
        renamer.setEnabled(false)
        NSApp.terminate(nil)
    }
}

struct Converter {
    let command: ConverterCommand?

    static func detect() -> Converter {
        if runAndCapture("/usr/bin/sips", ["-h"]).contains("webp") {
            return Converter(command: .sips)
        }

        for path in ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return Converter(command: .cwebp(path))
            }
        }

        return Converter(command: nil)
    }

    private static func runAndCapture(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

enum ConverterCommand {
    case sips
    case cwebp(String)

    func convert(sourceURL: URL, destinationURL: URL) -> Bool {
        let process = Process()

        switch self {
        case .sips:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = [
                "-s", "format", "webp", sourceURL.path, "--out", destinationURL.path,
            ]
        case .cwebp(let path):
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [
                "-quiet", "-q", webpQuality, sourceURL.path, "-o", destinationURL.path,
            ]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
                && FileManager.default.fileExists(atPath: destinationURL.path)
        } catch {
            return false
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
