import AppKit
import CoreGraphics
import Darwin
import Foundation
import Security
import UniformTypeIdentifiers

enum TransferMode: String, CaseIterable, Identifiable, Sendable {
    case move
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: String(localized: "Move")
        case .copy: String(localized: "Copy")
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case original
    case heic
    case webp
    case avif
    case bmp
    case psd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "Original")
        case .heic: "HEIC"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .bmp: "BMP"
        case .psd: "PSD"
        }
    }

    var pathExtension: String? {
        switch self {
        case .original: nil
        case .heic: "heic"
        case .webp: "webp"
        case .avif: "avif"
        case .bmp: "bmp"
        case .psd: "psd"
        }
    }

    var typeIdentifier: String? {
        switch self {
        case .original:
            nil
        case .heic:
            UTType.heic.identifier
        case .webp:
            "org.webmproject.webp"
        case .avif:
            "public.avif"
        case .bmp:
            "com.microsoft.bmp"
        case .psd:
            "com.adobe.photoshop-image"
        }
    }

    var supportsCompressionQuality: Bool {
        switch self {
        case .heic, .webp, .avif:
            true
        case .original, .bmp, .psd:
            false
        }
    }
}

enum ScreenshotSourceFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case pdf
    case tiff

    var id: String { rawValue }

    var screencaptureValue: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .pdf: "pdf"
        case .tiff: "tiff"
        }
    }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .pdf: "PDF"
        case .tiff: "TIFF"
        }
    }

    static func fromScreencaptureValue(_ value: String) -> ScreenshotSourceFormat {
        switch value.lowercased() {
        case "jpg", "jpeg":
            .jpeg
        case "pdf":
            .pdf
        case "tif", "tiff":
            .tiff
        default:
            .png
        }
    }
}

enum SandboxStatus: Sendable {
    case enabled
    case disabled
    case unknown

    static var current: SandboxStatus {
        guard let task = SecTaskCreateFromSelf(nil),
              let values = SecTaskCopyValuesForEntitlements(
                task,
                ["com.apple.security.app-sandbox"] as CFArray,
                nil
              ) as? [String: Any] else {
            return .unknown
        }
        guard let value = values["com.apple.security.app-sandbox"] else { return .disabled }
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
              let enabled = value as? Bool else {
            return .unknown
        }
        return enabled ? .enabled : .disabled
    }
}

enum ScreenshotPreferencesError: LocalizedError {
    case sandboxed
    case sandboxStatusUnknown
    case synchronizationFailed

    var errorDescription: String? {
        switch self {
        case .sandboxed:
            String(localized: "Direct macOS screenshot preference changes are unavailable in the sandbox. Use Screenshot (Shift-Command-5), then select the same watched folder here.")
        case .sandboxStatusUnknown:
            String(localized: "Cannot determine sandbox status. Direct macOS screenshot preference changes are disabled.")
        case .synchronizationFailed:
            String(localized: "Could not synchronize macOS screenshot preferences. Refresh and retry; macOS may have received only some changes.")
        }
    }
}

@MainActor
struct ScreenshotPreferences {
    var sandboxStatus: () -> SandboxStatus
    var read: () throws -> ScreenshotDefaults
    var write: (ScreenshotDefaults) throws -> Void

    static let live = ScreenshotPreferences(
        sandboxStatus: { .current },
        read: { try ScreenshotDefaults.current() },
        write: { try $0.apply() }
    )
}

struct ScreenshotDefaults: Equatable, Sendable {
    var locationURL: URL
    var namePrefix: String
    var type: String
    var includeDate: Bool
    var disableShadow: Bool
    var showThumbnail: Bool
    var captureMousePointer: Bool

    static let domain = "com.apple.screencapture"

    static var defaultLocationURL: URL {
        realUserHomeDirectoryURL.appendingPathComponent("Desktop", isDirectory: true)
    }

    static var fallback: ScreenshotDefaults {
        ScreenshotDefaults(
            locationURL: defaultLocationURL,
            namePrefix: "Screenshot",
            type: "png",
            includeDate: true,
            disableShadow: false,
            showThumbnail: true,
            captureMousePointer: false
        )
    }

    static func current() throws -> ScreenshotDefaults {
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            throw ScreenshotPreferencesError.synchronizationFailed
        }

        let location = CFPreferencesCopyAppValue("location" as CFString, domain as CFString) as? String
        let name = CFPreferencesCopyAppValue("name" as CFString, domain as CFString) as? String
        let type = CFPreferencesCopyAppValue("type" as CFString, domain as CFString) as? String
        let includeDate = optionalBool(forKey: "include-date", defaultValue: true)
        let disableShadow = optionalBool(forKey: "disable-shadow", defaultValue: false)
        let showThumbnail = optionalBool(forKey: "show-thumbnail", defaultValue: true)
        let captureMousePointer = optionalBool(forKey: "capture-mouse-pointer", defaultValue: false)

        return ScreenshotDefaults(
            locationURL: URL(
                fileURLWithPath: NSString(string: location ?? defaultLocationURL.path).expandingTildeInPath,
                isDirectory: true
            ),
            namePrefix: name ?? "Screenshot",
            type: (type ?? "png").lowercased(),
            includeDate: includeDate,
            disableShadow: disableShadow,
            showThumbnail: showThumbnail,
            captureMousePointer: captureMousePointer
        )
    }

    func apply() throws {
        switch SandboxStatus.current {
        case .enabled: throw ScreenshotPreferencesError.sandboxed
        case .unknown: throw ScreenshotPreferencesError.sandboxStatusUnknown
        case .disabled: break
        }

        CFPreferencesSetAppValue("location" as CFString, locationURL.path as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("name" as CFString, namePrefix as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("type" as CFString, type as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("include-date" as CFString, includeDate as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("disable-shadow" as CFString, disableShadow as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("show-thumbnail" as CFString, showThumbnail as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("capture-mouse-pointer" as CFString, captureMousePointer as CFBoolean, Self.domain as CFString)
        guard CFPreferencesAppSynchronize(Self.domain as CFString) else {
            throw ScreenshotPreferencesError.synchronizationFailed
        }
    }

    private static func optionalBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return defaultValue
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return defaultValue
    }

    private static var realUserHomeDirectoryURL: URL {
        if let passwordEntry = getpwuid(getuid()), let homeDirectory = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}

struct ActiveWindowInfo: Sendable {
    var appName: String
    var windowTitle: String

    static var current: ActiveWindowInfo {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown App"
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []

        let title = windows.first { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String else { return false }
            return owner == appName
        }?[kCGWindowName as String] as? String

        return ActiveWindowInfo(appName: appName, windowTitle: title ?? "")
    }
}
