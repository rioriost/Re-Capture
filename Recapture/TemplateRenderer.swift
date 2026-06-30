import Foundation

struct TemplateRenderer {
    static func render(template: String, date: Date, sequence: Int, activeWindowInfo: ActiveWindowInfo) -> String {
        let protectedTemplate = template
            .replacingOccurrences(of: "{app}", with: "'__RECAPTURE_APP__'")
            .replacingOccurrences(of: "{title}", with: "'__RECAPTURE_TITLE__'")
            .replacingOccurrences(of: "{sequence}", with: "'__RECAPTURE_SEQUENCE__'")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = protectedTemplate

        var rendered = formatter.string(from: date)
        rendered = rendered.replacingOccurrences(of: "__RECAPTURE_APP__", with: activeWindowInfo.appName)
        rendered = rendered.replacingOccurrences(of: "__RECAPTURE_TITLE__", with: activeWindowInfo.windowTitle)
        rendered = rendered.replacingOccurrences(of: "__RECAPTURE_SEQUENCE__", with: String(format: "%04d", sequence))

        return sanitizeFilename(rendered.isEmpty ? "Screenshot" : rendered)
    }

    private static func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)

        return value
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
