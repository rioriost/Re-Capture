import AppKit
import CoreGraphics
import Darwin
import Foundation
import UniformTypeIdentifiers

enum TransferMode: String, CaseIterable, Identifiable {
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

enum OutputFormat: String, CaseIterable, Identifiable {
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

enum ScreenshotSourceFormat: String, CaseIterable, Identifiable {
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

struct ScreenshotDefaults: Equatable {
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

    static func current() -> ScreenshotDefaults {
        CFPreferencesAppSynchronize(domain as CFString)

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

    func apply() {
        CFPreferencesSetAppValue("location" as CFString, locationURL.path as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("name" as CFString, namePrefix as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("type" as CFString, type as CFString, Self.domain as CFString)
        CFPreferencesSetAppValue("include-date" as CFString, includeDate as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("disable-shadow" as CFString, disableShadow as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("show-thumbnail" as CFString, showThumbnail as CFBoolean, Self.domain as CFString)
        CFPreferencesSetAppValue("capture-mouse-pointer" as CFString, captureMousePointer as CFBoolean, Self.domain as CFString)
        CFPreferencesAppSynchronize(Self.domain as CFString)
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

struct ActiveWindowInfo {
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
