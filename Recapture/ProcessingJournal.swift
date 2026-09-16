import Darwin
import Foundation

struct FileStamp: Codable, Equatable, Sendable {
    var device: Int32
    var inode: UInt64
    var size: Int64
    var modifiedSeconds: Int64
    var modifiedNanoseconds: Int64

    static func read(_ url: URL) throws -> FileStamp {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &information)
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw ProcessingError.notRegular
        }
        return FileStamp(
            device: information.st_dev,
            inode: information.st_ino,
            size: information.st_size,
            modifiedSeconds: Int64(information.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(information.st_mtimespec.tv_nsec)
        )
    }

    func key(for url: URL) -> String {
        // Device numbers can change when a volume is remounted.
        "\(Self.canonicalPath(url))|\(inode)|\(size)|\(modifiedSeconds)|\(modifiedNanoseconds)"
    }

    static func canonicalPath(_ url: URL) -> String {
        // Resolve the existing parent even when the final output has not been published yet.
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).standardizedFileURL.path
    }

    var modificationDate: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000)
    }
}

struct TransferRecord: Codable {
    var sourcePath: String
    var sourceStamp: FileStamp
    var destinationPath: String
    var stagingPath: String
    var outputStamp: FileStamp
    var committed: Bool
    var needsSourceRemoval: Bool
    var fallback: Bool

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
    var stagingURL: URL { URL(fileURLWithPath: stagingPath) }
}

struct ProcessingJournal {
    struct State: Codable {
        var version = 1
        var sequence = 1
        var initializedDirectories: Set<String> = []
        var ignoredSources: Set<String> = []
        var generatedFiles: Set<String> = []
        var records: [String: TransferRecord] = [:]
    }

    var url: URL
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Re-Capture", isDirectory: true)
            .appendingPathComponent("processing-journal.json")
    }

    func load() throws -> State {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return State() }
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard state.version == 1 else { throw ProcessingError.unsupportedJournal }
            return state
        } catch {
            throw ProcessingError.historyUnavailable(error.localizedDescription)
        }
    }

    func save(_ state: State) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(JSONEncoder().encode(state), url)
        } catch {
            throw ProcessingError.historyUnavailable(error.localizedDescription)
        }
    }
}

enum ProcessingError: LocalizedError {
    case notRegular
    case incomplete
    case sourceChanged
    case outputChanged
    case unsupportedJournal
    case historyUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notRegular:
            String(localized: "Not a regular file.")
        case .incomplete:
            String(localized: "Image is incomplete or still being written. Original retained.")
        case .sourceChanged:
            String(localized: "Source changed during processing. Original retained.")
        case .outputChanged:
            String(localized: "Saved output is missing or changed. Original retained; check the output folder.")
        case .unsupportedJournal:
            String(localized: "Unsupported processing history. Update Re-Capture before processing files.")
        case .historyUnavailable(let reason):
            String(format: String(localized: "Processing history is unavailable: %@"), reason)
        }
    }
}
