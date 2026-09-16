import CoreServices
import Foundation

protocol ScreenshotWatching: AnyObject, Sendable {
    var onEvent: (@Sendable () -> Void)? { get set }
    func start(watching url: URL) throws
    func stop()
}

final class ScreenshotWatcher: ScreenshotWatching, @unchecked Sendable {
    private final class EventContext {
        var onEvent: (@Sendable () -> Void)?
        var isActive = true

        init(onEvent: (@Sendable () -> Void)?) {
            self.onEvent = onEvent
        }
    }

    private enum WatchError: LocalizedError {
        case createFailed
        case startFailed

        var errorDescription: String? {
            switch self {
            case .createFailed:
                String(localized: "Could not create the screenshot folder event stream")
            case .startFailed:
                String(localized: "Could not start the screenshot folder event stream")
            }
        }
    }

    private let queue = DispatchQueue(label: "st.rio.recapture.watcher")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var stream: FSEventStreamRef?
    private var watchedURL: URL?
    private var eventContext: EventContext?
    private var eventHandler: (@Sendable () -> Void)?

    init() {
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    var onEvent: (@Sendable () -> Void)? {
        get { onQueue { eventHandler } }
        set {
            onQueue {
                eventHandler = newValue
                eventContext?.onEvent = newValue
            }
        }
    }

    func start(watching url: URL) throws {
        try onQueue {
            guard watchedURL != url || stream == nil else { return }
            stopOnQueue()
            let eventContext = EventContext(onEvent: eventHandler)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(eventContext).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<EventContext>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<EventContext>.fromOpaque(info).release()
                },
                copyDescription: nil
            )

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    let context = Unmanaged<EventContext>.fromOpaque(info).takeUnretainedValue()
                    guard context.isActive else { return }
                    context.onEvent?()
                },
                &context,
                [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.7,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            ) else {
                throw WatchError.createFailed
            }

            self.stream = stream
            self.eventContext = eventContext
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                stopOnQueue()
                throw WatchError.startFailed
            }
            watchedURL = url
        }
    }

    func stop() {
        onQueue { stopOnQueue() }
    }

    private func stopOnQueue() {
        eventContext?.isActive = false
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedURL = nil
        eventContext = nil
    }

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}
