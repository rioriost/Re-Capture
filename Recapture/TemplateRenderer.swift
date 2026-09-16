import Foundation

struct TemplateRenderer {
    static func validate(template: String) throws {
        _ = try render(
            template: template,
            date: Date(),
            sequence: 1,
            activeWindowInfo: ActiveWindowInfo(appName: "App", windowTitle: "Window")
        )
    }

    static func render(template: String, date: Date, sequence: Int, activeWindowInfo: ActiveWindowInfo) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let characters = Array(template)
        var index = 0
        var quoted = false
        var dateFormat = ""
        var rendered = ""

        func flushDateFormat() {
            guard !dateFormat.isEmpty else { return }
            formatter.dateFormat = dateFormat
            rendered += formatter.string(from: date)
            dateFormat = ""
        }

        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                dateFormat.append(character)
                if index + 1 < characters.count, characters[index + 1] == "'" {
                    dateFormat.append("'")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if character == "{", !quoted {
                guard let end = characters[index...].firstIndex(of: "}") else {
                    throw FilenameError.invalidTemplate
                }
                flushDateFormat()
                switch String(characters[(index + 1)..<end]) {
                case "app": rendered += activeWindowInfo.appName
                case "title": rendered += activeWindowInfo.windowTitle
                case "sequence": rendered += String(format: "%04d", sequence)
                default: throw FilenameError.invalidTemplate
                }
                index = end + 1
                continue
            } else {
                dateFormat.append(character)
            }
            index += 1
        }
        guard !quoted else { throw FilenameError.invalidTemplate }
        flushDateFormat()

        let filename = sanitizeFilename(rendered)
        guard !filename.isEmpty, !filename.hasPrefix(".") else {
            throw FilenameError.emptyOrHiddenName
        }
        guard filename.utf8.count <= 250 else { throw FilenameError.tooLong }
        return filename
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

enum FilenameError: LocalizedError {
    case invalidTemplate
    case emptyOrHiddenName
    case tooLong

    var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            String(localized: "Invalid filename template: check tokens and quotes.")
        case .emptyOrHiddenName:
            String(localized: "Filename must not be empty or start with a dot.")
        case .tooLong:
            String(localized: "Filename is too long. Shorten the template or title.")
        }
    }
}
