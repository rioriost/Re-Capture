import XCTest
@testable import Recapture

@MainActor
final class AppControllerTests: XCTestCase {
    func testCancelledDebouncesDoNotRunAfterThrowingOrReturningFromSleep() async {
        let fixture = Fixture()
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }

        fixture.watcher.emit()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(0, throwing: CancellationError())
        await settle(fixture)
        XCTAssertEqual(fixture.processor.calls.count, 0)

        fixture.watcher.emit()
        await eventually { fixture.clock.count == 3 }
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertEqual(fixture.processor.calls.count, 0)

        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-0" }
        XCTAssertEqual(fixture.processor.calls.count, 1)
    }

    func testBurstCoalescesIntoOneScanAfterQuietPeriod() async {
        let fixture = Fixture()
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        // Async sleep registrations need not arrive in task-creation order.
        for expectedCount in 2...31 {
            fixture.watcher.emit()
            await eventually { fixture.clock.count == expectedCount }
        }
        for index in 0..<30 {
            fixture.clock.complete(index)
        }
        await settle(fixture)
        XCTAssertEqual(fixture.processor.calls.count, 0)

        fixture.clock.complete(30)
        await eventually { fixture.settings.statusText == "result-0" }
        XCTAssertEqual(fixture.processor.calls.count, 1)
        XCTAssertEqual(fixture.processor.maximumActive, 1)
    }

    func testPauseRejectsDebounceAndAlreadyDeliveredWatcherCallbacks() async {
        let fixture = Fixture()
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        let oldCallback = fixture.watcher.onEvent

        fixture.pause()
        fixture.clock.complete(0)
        oldCallback?()
        await settle(fixture)

        XCTAssertEqual(fixture.processor.calls.count, 0)
        XCTAssertEqual(fixture.clock.count, 1)
        XCTAssertEqual(fixture.settings.statusText, String(localized: "Paused"))
        XCTAssertFalse(fixture.watcher.isWatching)
        XCTAssertEqual(fixture.access.activeCount, 0)
    }

    func testPauseInvalidatesAJobStillWaitingOnTheProcessingQueue() async {
        let queue = DispatchQueue(label: "AppControllerTests.held")
        queue.suspend()
        let fixture = Fixture(queue: queue)
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.clock.complete(0)
        await eventually { fixture.access.activeCount == 4 }

        fixture.pause()
        XCTAssertEqual(fixture.access.activeCount, 2)
        queue.resume()
        await eventually { fixture.access.activeCount == 0 }
        await settle(fixture)

        XCTAssertEqual(fixture.processor.calls.count, 0)
        XCTAssertEqual(fixture.settings.statusText, String(localized: "Paused"))
    }

    func testPauseAllowsCurrentTransactionToReturnButDropsPendingWorkAndStatus() async {
        let gate = DispatchSemaphore(value: 0)
        let processor = Processor { call in
            if call.index == 0 { _ = gate.wait(timeout: .now() + 5) }
            return ProcessResult(
                processed: 1, message: "stale transaction", retrySuggested: true,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer {
            gate.signal()
            fixture.stop()
        }
        await startFirstScan(fixture)
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(1)
        await settleActor()

        fixture.pause()
        XCTAssertTrue(processor.calls.first?.cancellation.isCancelled == true)
        XCTAssertEqual(fixture.access.activeCount, 2, "In-flight access must outlive watcher access.")
        gate.signal()
        await eventually { fixture.access.activeCount == 0 }
        await settle(fixture)

        XCTAssertEqual(processor.completedCount, 1)
        XCTAssertEqual(processor.calls.count, 1)
        XCTAssertEqual(fixture.clock.count, 2)
        XCTAssertEqual(fixture.settings.statusText, String(localized: "Paused"))
    }

    func testReconfigureDropsOldRequestsAndStatusAndUsesANewSnapshot() async {
        let gate = DispatchSemaphore(value: 0)
        let processor = Processor { call in
            if call.index == 0 { _ = gate.wait(timeout: .now() + 5) }
            return ProcessResult(
                processed: 1, message: "result-\(call.index)", retrySuggested: call.index == 0,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer {
            gate.signal()
            fixture.stop()
        }
        await startFirstScan(fixture)
        let oldCallback = fixture.watcher.onEvent
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(1)
        await settleActor()

        fixture.settings.filenameTemplate = "new-template"
        fixture.settings.setStatus("new configuration")
        fixture.controller.reconfigure()
        await eventually { fixture.clock.count == 3 }
        oldCallback?()
        XCTAssertTrue(processor.calls.first?.cancellation.isCancelled == true)
        gate.signal()
        await eventually { processor.completedCount == 1 }
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        XCTAssertEqual(fixture.settings.statusText, "new configuration")
        XCTAssertEqual(fixture.clock.count, 3)

        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-1" }
        XCTAssertEqual(processor.calls.count, 2)
        XCTAssertEqual(processor.calls.last?.settings.filenameTemplate, "new-template")
        XCTAssertEqual(processor.maximumActive, 1)
    }

    func testRequestsDuringProcessingCoalesceAndPreserveExplicitBulkIntent() async {
        let gate = DispatchSemaphore(value: 0)
        let processor = Processor { call in
            if call.index == 0 { _ = gate.wait(timeout: .now() + 5) }
            return ProcessResult(processed: 1, message: "result-\(call.index)")
        }
        let fixture = Fixture(processor: processor)
        defer {
            gate.signal()
            fixture.stop()
        }
        await startFirstScan(fixture)
        for _ in 0..<10 {
            fixture.controller.processBulk()
            fixture.watcher.emit()
        }
        await eventually { fixture.clock.count == 11 }
        for index in 1..<11 {
            fixture.clock.complete(index)
        }
        await settleActor()
        XCTAssertEqual(processor.calls.count, 1)

        gate.signal()
        await eventually { fixture.settings.statusText == "result-1" }
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 2)
        XCTAssertEqual(processor.calls.last?.bulk, true)
        XCTAssertEqual(processor.maximumActive, 1)
    }

    func testNewEventsResetQuietPeriodEvenWhenAnAutomaticRequestWasPending() async {
        let gate = DispatchSemaphore(value: 0)
        let processor = Processor { call in
            if call.index == 0 { _ = gate.wait(timeout: .now() + 5) }
            return ProcessResult(processed: 1, message: "result-\(call.index)")
        }
        let fixture = Fixture(processor: processor)
        defer {
            gate.signal()
            fixture.stop()
        }
        await startFirstScan(fixture)
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(1)
        await settleActor()
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 3 }
        gate.signal()
        await eventually { fixture.settings.statusText == "result-0" }
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)

        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-1" }
        XCTAssertEqual(processor.calls.count, 2)
    }

    func testRetriesAreDelayedAndBoundedAndANewEventCanTryAgain() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 0, message: "deferred-\(call.index)", deferred: 1, retrySuggested: true,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor, maximumRetries: 2)
        defer { fixture.stop() }
        await startFirstScan(fixture)
        await eventually { fixture.clock.count == 2 }
        XCTAssertEqual(fixture.clock.delays[1], .seconds(2))
        XCTAssertEqual(processor.calls.count, 1)

        fixture.clock.complete(1)
        await eventually { fixture.clock.count == 3 }
        XCTAssertEqual(fixture.clock.delays[2], .seconds(2))
        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "deferred-2" }
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 3)
        XCTAssertEqual(fixture.clock.count, 3)
        XCTAssertNil(processor.calls.first?.settings.includedSourcePaths)
        for call in processor.calls.dropFirst() {
            XCTAssertEqual(call.settings.includedSourcePaths, [call.sourcePath("unfinished.png")])
        }

        fixture.watcher.emit()
        await eventually { fixture.clock.count == 4 }
        fixture.clock.complete(3)
        await eventually { fixture.clock.count == 5 }
        XCTAssertEqual(processor.calls.count, 4)
        XCTAssertNil(processor.calls.last?.settings.includedSourcePaths)
    }

    func testPauseCancelsDelayedRetry() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 0, message: "deferred", deferred: 1, retrySuggested: true,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await startFirstScan(fixture)
        await eventually { fixture.clock.count == 2 }
        fixture.pause()
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        XCTAssertEqual(fixture.settings.statusText, String(localized: "Paused"))
    }

    func testReconfigureCancelsRetryAndRetainsOnlyTheNewConfigurationScan() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 0, message: "result-\(call.index)", retrySuggested: call.index == 0,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await startFirstScan(fixture)
        await eventually { fixture.clock.count == 2 }
        fixture.settings.filenameTemplate = "changed"
        fixture.controller.reconfigure()
        await eventually { fixture.clock.count == 3 }
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)

        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-1" }
        XCTAssertEqual(processor.calls.count, 2)
        XCTAssertEqual(processor.calls.last?.settings.filenameTemplate, "changed")
    }

    func testFreshEventRetainsAFullAutomaticScanWithoutWideningBulkRetry() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 1, message: "result-\(call.index)", retrySuggested: call.index == 0,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        let unfinishedPath = fixture.settings.screenshotDefaults.locationURL.appendingPathComponent("unfinished.png").path
        await eventually { fixture.clock.count == 1 }
        fixture.controller.processBulk()
        await eventually { fixture.clock.count == 2 }
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 3 }
        fixture.clock.complete(0)
        fixture.clock.complete(2)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        fixture.clock.complete(1)
        await eventually { fixture.settings.statusText == "result-2" }
        XCTAssertEqual(processor.calls.count, 3)
        XCTAssertEqual(processor.calls.map(\.bulk), [true, true, false])
        XCTAssertEqual(
            processor.calls.dropFirst().first?.settings.includedSourcePaths,
            [unfinishedPath]
        )
        XCTAssertNil(processor.calls.last?.settings.includedSourcePaths)
        XCTAssertEqual(processor.maximumActive, 1)
    }

    func testBulkRetriesOnlyDeferredSourcesAndChainedRetriesDropCompletedSources() async {
        let processor = Processor { call in
            switch call.index {
            case 0:
                ProcessResult(
                    processed: 1, message: "result-0", deferred: 2, retrySuggested: true,
                    retrySourcePaths: [call.sourcePath("unfinished-a.png"), call.sourcePath("unfinished-b.png")]
                )
            case 1:
                ProcessResult(
                    processed: 1, message: "result-1", deferred: 1, retrySuggested: true,
                    retrySourcePaths: [call.sourcePath("unfinished-b.png")]
                )
            default:
                ProcessResult(processed: 1, message: "result-\(call.index)")
            }
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        let source = fixture.settings.screenshotDefaults.locationURL
        let unfinishedA = source.appendingPathComponent("unfinished-a.png").path
        let unfinishedB = source.appendingPathComponent("unfinished-b.png").path
        fixture.settings.transferMode = .copy
        await eventually { fixture.clock.count == 1 }
        fixture.controller.processBulk()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(0)
        fixture.clock.complete(1)
        await eventually { fixture.clock.count == 3 }
        let firstRetry = processor.calls.last
        XCTAssertEqual(firstRetry?.settings.includedSourcePaths, [unfinishedA, unfinishedB])
        XCTAssertFalse(firstRetry?.settings.includedSourcePaths?.contains(source.appendingPathComponent("success.png").path) == true)

        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-2" }
        XCTAssertEqual(processor.calls.last?.settings.includedSourcePaths, [unfinishedB])
        XCTAssertTrue(processor.calls.allSatisfy(\.bulk))
        XCTAssertEqual(processor.calls.count, 3)

        fixture.controller.processBulk()
        await eventually { fixture.settings.statusText == "result-3" }
        XCTAssertEqual(processor.calls.count, 4)
        XCTAssertNil(processor.calls.last?.settings.includedSourcePaths)
        XCTAssertEqual(processor.calls.last?.bulk, true)
    }

    func testExplicitBulkReplacesAQueuedFilteredRetryWithAFullRequest() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 1, message: "result-\(call.index)", retrySuggested: call.index == 0,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.controller.processBulk()
        await eventually { fixture.clock.count == 2 }
        fixture.controller.processBulk()
        await eventually { fixture.settings.statusText == "result-1" }
        fixture.clock.complete(0)
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 2)
        XCTAssertTrue(processor.calls.allSatisfy { $0.bulk && $0.settings.includedSourcePaths == nil })
    }

    func testFreshAutomaticEventSupersedesFilteredAutomaticRetryWithAFullScan() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 1, message: "result-\(call.index)", retrySuggested: call.index == 0,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await startFirstScan(fixture)
        await eventually { fixture.clock.count == 2 }
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 3 }
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        fixture.clock.complete(2)
        await eventually { fixture.settings.statusText == "result-1" }
        XCTAssertEqual(processor.calls.count, 2)
        XCTAssertTrue(processor.calls.allSatisfy { !$0.bulk && $0.settings.includedSourcePaths == nil })
    }

    func testMissingRetryPathsNeverFallsBackToAutomaticFullBulkReplay() async {
        let processor = Processor { _ in
            ProcessResult(processed: 1, message: "missing retry paths", deferred: 1, retrySuggested: true)
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.controller.processBulk()
        await eventually { fixture.settings.statusText == "missing retry paths" }
        fixture.clock.complete(0)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        XCTAssertEqual(fixture.clock.count, 1)
    }

    func testWatcherStartFailureIsVisibleReleasesAccessAndCanBeRetried() async {
        let watcher = Watcher()
        watcher.shouldFail = true
        let fixture = Fixture(watcher: watcher)
        defer { fixture.stop() }
        XCTAssertTrue(fixture.settings.statusText.contains("test watcher failure"))
        XCTAssertEqual(fixture.access.activeCount, 0)
        XCTAssertFalse(watcher.isWatching)
        XCTAssertEqual(fixture.clock.count, 0)

        watcher.shouldFail = false
        fixture.controller.reconfigure()
        await startFirstScan(fixture)
        await eventually { fixture.settings.statusText == "result-0" }
        XCTAssertTrue(watcher.isWatching)
    }

    func testAccessFailurePreventsWatchingAndProcessingAndCanBeRetried() async {
        let access = Access()
        access.shouldFail = true
        let fixture = Fixture(access: access)
        defer { fixture.stop() }
        XCTAssertEqual(fixture.watcher.startCount, 0)
        XCTAssertEqual(fixture.access.activeCount, 0)
        XCTAssertEqual(fixture.clock.count, 0)
        XCTAssertNotEqual(fixture.settings.statusText, String(localized: "Paused"))
        XCTAssertTrue(fixture.settings.statusText.contains(fixture.settings.screenshotDefaults.locationURL.path))

        access.shouldFail = false
        fixture.controller.reconfigure()
        await startFirstScan(fixture)
        await eventually { fixture.settings.statusText == "result-0" }
    }

    func testJobAccessFailureDoesNotProcessAndNextEventCanRetry() async {
        let fixture = Fixture()
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.access.shouldFail = true
        fixture.clock.complete(0)
        await settle(fixture)
        XCTAssertEqual(fixture.processor.calls.count, 0)
        XCTAssertEqual(fixture.access.activeCount, 2)
        XCTAssertTrue(fixture.settings.statusText.contains(fixture.settings.screenshotDefaults.locationURL.path))

        fixture.access.shouldFail = false
        fixture.watcher.emit()
        await eventually { fixture.clock.count == 2 }
        fixture.clock.complete(1)
        await eventually { fixture.settings.statusText == "result-0" }
    }

    func testExplicitBulkIsStillAvailableWhilePausedButDoesNotAutomaticallyRetry() async {
        let processor = Processor { call in
            ProcessResult(
                processed: 0, message: "bulk deferred", retrySuggested: true,
                retrySourcePaths: [call.sourcePath("unfinished.png")]
            )
        }
        let fixture = Fixture(processor: processor)
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.pause()
        fixture.controller.processBulk()
        await eventually { fixture.settings.statusText == "bulk deferred" }
        fixture.clock.complete(0)
        await settle(fixture)
        XCTAssertEqual(processor.calls.count, 1)
        XCTAssertEqual(processor.calls.first?.bulk, true)
        XCTAssertEqual(fixture.clock.count, 1)
    }

    func testControllerReleaseStopsWatcherAndReleasesDirectoryAccess() async {
        let fixture = Fixture()
        defer { fixture.stop() }
        await eventually { fixture.clock.count == 1 }
        fixture.pause()
        fixture.clock.complete(0)
        await settle(fixture)

        fixture.settings.isEnabled = true
        let watcher = Watcher()
        var controller: AppController? = AppController(
            watcher: watcher,
            processor: fixture.processor,
            processingQueue: fixture.queue,
            sleep: { [clock = fixture.clock] in try await clock.sleep(for: $0) }
        )
        controller?.bind(to: fixture.settings)
        await eventually { fixture.clock.count == 2 }
        let releasedController = { [weak controller] in controller }
        let oldCallback = watcher.onEvent
        controller = nil
        XCTAssertNil(releasedController())
        await eventually { fixture.access.activeCount == 0 }
        oldCallback?()
        fixture.clock.complete(1)
        await settle(fixture)
        XCTAssertFalse(watcher.isWatching)
        XCTAssertEqual(fixture.processor.calls.count, 0)
    }

    private func startFirstScan(_ fixture: Fixture) async {
        await eventually { fixture.clock.count == 1 }
        fixture.clock.complete(0)
        await eventually { fixture.processor.calls.count == 1 }
    }

    private func eventually(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: () -> Bool
    ) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

    private func settleActor() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func settle(_ fixture: Fixture) async {
        await settleActor()
        await withCheckedContinuation { continuation in
            fixture.queue.async { continuation.resume() }
        }
        await settleActor()
    }
}

@MainActor
private final class Fixture {
    let settings: SettingsStore
    let controller: AppController
    let watcher: Watcher
    let processor: Processor
    let access: Access
    let clock = ManualSleeper()
    let queue: DispatchQueue
    private let suite = "AppControllerTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init(
        watcher: Watcher = Watcher(),
        processor: Processor = Processor(),
        access: Access = Access(),
        queue: DispatchQueue = DispatchQueue(label: "AppControllerTests.processor"),
        maximumRetries: Int = 3
    ) {
        self.watcher = watcher
        self.processor = processor
        self.access = access
        self.queue = queue
        defaults = UserDefaults(suiteName: suite)!
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("virtual-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let screenshotDefaults = ScreenshotDefaults(
            locationURL: source,
            namePrefix: "Test Screenshot",
            type: "png",
            includeDate: true,
            disableShadow: false,
            showThumbnail: false,
            captureMousePointer: false
        )
        settings = SettingsStore(
            defaults: defaults,
            bookmarks: BookmarkAccess(
                make: { Data($0.path.utf8) },
                resolve: { ResolvedBookmark(url: URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)), isStale: false) },
                save: { data, key, defaults in defaults.set(data, forKey: key) },
                startAccessing: { access.start($0) },
                stopAccessing: { access.stop($0) }
            ),
            preferences: ScreenshotPreferences(
                sandboxStatus: { .enabled },
                read: { screenshotDefaults },
                write: { _ in XCTFail("Tests must never write system screenshot preferences.") }
            )
        )
        XCTAssertTrue(settings.setScreenshotLocation(source))
        XCTAssertTrue(settings.setDestinationURL(root.appendingPathComponent("output", isDirectory: true)))
        let clock = clock
        controller = AppController(
            watcher: watcher,
            processor: processor,
            processingQueue: queue,
            maximumRetryAttempts: maximumRetries,
            sleep: { try await clock.sleep(for: $0) }
        )
        controller.bind(to: settings)
    }

    func pause() {
        settings.isEnabled = false
        controller.reconfigure()
    }

    func stop() {
        pause()
        clock.cancelAll()
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class ManualSleeper: @unchecked Sendable {
    private struct Waiter {
        let delay: Duration
        var continuation: CheckedContinuation<Void, any Error>?
    }

    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var isClosed = false

    var count: Int { lock.withLock { waiters.count } }
    var delays: [Duration] { lock.withLock { waiters.map(\.delay) } }

    // Deliberately ignore task cancellation so tests can exercise both sleep outcomes.
    func sleep(for delay: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let isClosed = lock.withLock {
                guard !self.isClosed else { return true }
                waiters.append(Waiter(delay: delay, continuation: continuation))
                return false
            }
            if isClosed {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func complete(_ index: Int, throwing error: (any Error)? = nil) {
        let continuation = lock.withLock {
            guard waiters.indices.contains(index) else { return Optional<CheckedContinuation<Void, any Error>>.none }
            let continuation = waiters[index].continuation
            waiters[index].continuation = nil
            return continuation
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    func cancelAll() {
        let continuations = lock.withLock {
            isClosed = true
            let continuations = waiters.compactMap(\.continuation)
            for index in waiters.indices {
                waiters[index].continuation = nil
            }
            return continuations
        }
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }
}

private final class Processor: ScreenshotProcessing, @unchecked Sendable {
    struct Call: Sendable {
        let index: Int
        let settings: SettingsSnapshot
        let bulk: Bool
        let cancellation: ProcessingCancellation

        func sourcePath(_ name: String) -> String {
            settings.screenshotDefaults.locationURL.appendingPathComponent(name).path
        }
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var active = 0
    private var maxActive = 0
    private var completed = 0
    private let body: @Sendable (Call) -> ProcessResult

    init(body: @escaping @Sendable (Call) -> ProcessResult = {
        ProcessResult(processed: 1, message: "result-\($0.index)")
    }) {
        self.body = body
    }

    var calls: [Call] { lock.withLock { recordedCalls } }
    var maximumActive: Int { lock.withLock { maxActive } }
    var completedCount: Int { lock.withLock { completed } }

    func process(settings: SettingsSnapshot, bulk: Bool, cancellation: ProcessingCancellation) -> ProcessResult {
        let call = lock.withLock {
            let call = Call(index: recordedCalls.count, settings: settings, bulk: bulk, cancellation: cancellation)
            recordedCalls.append(call)
            active += 1
            maxActive = max(maxActive, active)
            return call
        }
        let result = body(call)
        lock.withLock {
            active -= 1
            completed += 1
        }
        return result
    }
}

private final class Watcher: ScreenshotWatching, @unchecked Sendable {
    private enum Failure: LocalizedError {
        case start
        var errorDescription: String? { "test watcher failure" }
    }

    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var fail = false
    private var watching = false
    private var starts = 0

    var onEvent: (@Sendable () -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    var shouldFail: Bool {
        get { lock.withLock { fail } }
        set { lock.withLock { fail = newValue } }
    }

    var isWatching: Bool { lock.withLock { watching } }
    var startCount: Int { lock.withLock { starts } }

    func start(watching url: URL) throws {
        try lock.withLock {
            starts += 1
            if fail { throw Failure.start }
            watching = true
        }
    }

    func stop() { lock.withLock { watching = false } }
    func emit() { onEvent?() }
}

@MainActor
private final class Access {
    var shouldFail = false
    private(set) var activeCount = 0

    func start(_ url: URL) -> Bool {
        guard !shouldFail else { return false }
        activeCount += 1
        return true
    }

    func stop(_ url: URL) {
        activeCount -= 1
        XCTAssertGreaterThanOrEqual(activeCount, 0)
    }
}
