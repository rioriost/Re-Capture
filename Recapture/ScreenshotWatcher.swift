import CoreServices
import Foundation

final class ScreenshotWatcher: @unchecked Sendable {
    var onEvent: (() -> Void)?

    private let queue = DispatchQueue(label: "st.rio.recapture.watcher")
    private var stream: FSEventStreamRef?
    private var watchedURL: URL?

    func start(watching url: URL) {
        queue.async {
            guard self.watchedURL != url || self.stream == nil else { return }
            self.stopOnQueue()
            self.watchedURL = url

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
                    watcher.onEvent?()
                },
                &context,
                [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.7,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            ) else {
                return
            }

            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        queue.async {
            self.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
