import Foundation

@MainActor
final class AppController: ObservableObject {
    private struct Request: Sendable {
        var bulk: Bool
        var retryAttempt = 0
        var includedSourcePaths: Set<String>? = nil
    }

    private struct Job: Sendable {
        let id = UUID()
        let generation: UInt64
        let request: Request
        let cancellation = ProcessingCancellation()
    }

    private let watcher: any ScreenshotWatching
    private let processor: any ScreenshotProcessing
    private let processingQueue: DispatchQueue
    private let debounceDelay: Duration
    private let retryDelay: Duration
    private let maximumRetryAttempts: Int
    private let sleep: @Sendable (Duration) async throws -> Void
    private var delayedTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryRequest: Request?
    private var pendingRetryRequest: Request?
    private var pendingRequest: Request?
    private var runningJob: Job?
    private var generation: UInt64 = 0
    private var watcherIsReady = false
    private var watcherAccessURLs: [URL] = []
    private var settingsStore: SettingsStore?

    init(
        watcher: any ScreenshotWatching = ScreenshotWatcher(),
        processor: any ScreenshotProcessing = ScreenshotProcessor(),
        processingQueue: DispatchQueue = DispatchQueue(label: "st.rio.recapture.processor", qos: .utility),
        debounceDelay: Duration = .milliseconds(800),
        retryDelay: Duration = .seconds(2),
        maximumRetryAttempts: Int = 3,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.watcher = watcher
        self.processor = processor
        self.processingQueue = processingQueue
        self.debounceDelay = debounceDelay
        self.retryDelay = retryDelay
        self.maximumRetryAttempts = max(0, maximumRetryAttempts)
        self.sleep = sleep
    }

    deinit {
        delayedTask?.cancel()
        retryTask?.cancel()
        runningJob?.cancellation.cancel()
        watcher.stop()
        let urls = watcherAccessURLs
        if let settingsStore, !urls.isEmpty {
            Task { @MainActor in
                settingsStore.stopAccessing(urls)
            }
        }
    }

    func bind(to settingsStore: SettingsStore) {
        stopWatching()
        self.settingsStore = settingsStore
        reconfigure()
    }

    func reconfigure() {
        generation &+= 1
        cancelScheduledRequests()
        // The running transaction retains its directory access until it safely returns.
        runningJob?.cancellation.cancel()
        stopWatching()

        guard let settingsStore else { return }
        guard settingsStore.isEnabled else {
            settingsStore.setStatus(String(localized: "Paused"))
            return
        }
        guard settingsStore.destinationURL != nil else {
            settingsStore.setStatus(String(localized: "Choose an output folder to start"))
            return
        }

        do {
            watcherAccessURLs = try settingsStore.startAccessingConfiguredDirectories()
        } catch {
            showAccessError(error, in: settingsStore)
            return
        }

        let expectedGeneration = generation
        watcher.onEvent = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.scheduleProcessing()
            }
        }
        do {
            try watcher.start(watching: settingsStore.screenshotDefaults.locationURL)
            watcherIsReady = true
            scheduleProcessing()
        } catch {
            stopWatching()
            settingsStore.setStatus(String(
                format: String(localized: "Could not watch screenshots: %@"),
                error.localizedDescription
            ))
        }
    }

    func processBulk() {
        // Explicit bulk processing remains available while automatic processing is paused.
        cancelScheduledRequests()
        enqueue(Request(bulk: true))
    }

    private func scheduleProcessing() {
        guard watcherIsReady, settingsStore?.isEnabled == true else { return }
        if retryRequest?.bulk == false {
            retryTask?.cancel()
            retryTask = nil
            retryRequest = nil
        }
        if pendingRetryRequest?.bulk == false {
            pendingRetryRequest = nil
        }
        if pendingRequest?.bulk == false {
            pendingRequest = nil
        }
        schedule(Request(bulk: false), after: debounceDelay)
    }

    private func enqueue(_ request: Request) {
        if var pendingRequest {
            pendingRequest.bulk = pendingRequest.bulk || request.bulk
            pendingRequest.retryAttempt = min(pendingRequest.retryAttempt, request.retryAttempt)
            self.pendingRequest = pendingRequest
        } else {
            pendingRequest = request
        }
        startPendingRequest()
    }

    private func startPendingRequest() {
        guard runningJob == nil, let settingsStore else { return }
        let request: Request
        if let retry = pendingRetryRequest {
            request = retry
            pendingRetryRequest = nil
        } else {
            // Finish filtered bulk retries before a fresh automatic scan can process those sources.
            guard retryRequest?.bulk != true, let pendingRequest else { return }
            request = pendingRequest
            self.pendingRequest = nil
        }
        guard request.bulk || (settingsStore.isEnabled && watcherIsReady) else { return }
        guard let destinationURL = settingsStore.destinationURL else {
            settingsStore.setStatus(String(localized: "Choose an output folder to start"))
            return
        }

        let accessURLs: [URL]
        do {
            accessURLs = try settingsStore.startAccessingConfiguredDirectories()
        } catch {
            showAccessError(error, in: settingsStore)
            return
        }
        let snapshot = SettingsSnapshot(
            screenshotDefaults: settingsStore.screenshotDefaults,
            destinationURL: destinationURL,
            filenameTemplate: settingsStore.filenameTemplate,
            outputFormat: settingsStore.outputFormat,
            outputQuality: settingsStore.outputQuality,
            transferMode: settingsStore.transferMode,
            includedSourcePaths: request.includedSourcePaths
        )
        let job = Job(generation: generation, request: request)
        runningJob = job
        processingQueue.async { [weak self, processor] in
            // A job may have been invalidated while waiting for this queue.
            let result = job.cancellation.isCancelled ? nil : processor.process(
                settings: snapshot,
                bulk: request.bulk,
                cancellation: job.cancellation
            )
            Task { @MainActor [weak self] in
                settingsStore.stopAccessing(accessURLs)
                self?.finish(job, result: result)
            }
        }
    }

    private func finish(_ job: Job, result: ProcessResult?) {
        guard runningJob?.id == job.id else { return }
        runningJob = nil
        let isCurrent = job.generation == generation && !job.cancellation.isCancelled
        if isCurrent, let result {
            settingsStore?.setStatus(result.message)
        }

        if isCurrent, let result, result.retrySuggested, pendingRequest?.bulk != true,
           job.request.bulk || (pendingRequest == nil && delayedTask == nil) {
            scheduleRetry(for: job.request, sourcePaths: result.retrySourcePaths)
        }
        startPendingRequest()
    }

    private func scheduleRetry(for request: Request, sourcePaths: Set<String>) {
        let sourcePaths = request.includedSourcePaths.map { sourcePaths.intersection($0) } ?? sourcePaths
        guard watcherIsReady, settingsStore?.isEnabled == true,
              request.retryAttempt < maximumRetryAttempts, !sourcePaths.isEmpty else { return }
        let retry = Request(
            bulk: request.bulk,
            retryAttempt: request.retryAttempt + 1,
            includedSourcePaths: sourcePaths
        )
        retryTask?.cancel()
        retryRequest = retry
        let expectedGeneration = generation
        retryTask = Task { @MainActor [weak self, sleep, retryDelay] in
            do {
                try await sleep(retryDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.retryTask = nil
            self.retryRequest = nil
            self.pendingRetryRequest = retry
            self.startPendingRequest()
        }
    }

    private func schedule(_ request: Request, after delay: Duration) {
        delayedTask?.cancel()
        let expectedGeneration = generation
        delayedTask = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.delayedTask = nil
            self.enqueue(request)
        }
    }

    private func cancelScheduledRequests() {
        delayedTask?.cancel()
        delayedTask = nil
        retryTask?.cancel()
        retryTask = nil
        retryRequest = nil
        pendingRetryRequest = nil
        pendingRequest = nil
    }

    private func stopWatching() {
        watcherIsReady = false
        watcher.stop()
        watcher.onEvent = nil
        settingsStore?.stopAccessing(watcherAccessURLs)
        watcherAccessURLs = []
    }

    private func showAccessError(_ error: Error, in settingsStore: SettingsStore) {
        settingsStore.setStatus(String(
            format: String(localized: "Folder access failed: %@"),
            error.localizedDescription
        ))
    }
}
