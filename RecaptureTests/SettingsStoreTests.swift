import Combine
import Foundation
import XCTest
@testable import Recapture

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDraftEditsDoNotChangeAppliedSettingsOrWritePreferences() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let original = try XCTUnwrap(store.snapshot)
            let originalConfiguration = store.processingConfiguration
            let originalBookmark = fixture.defaults.data(forKey: "screenshotLocationBookmark")
            var publications = 0
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            store.screenshotDefaultsDraft.locationURL = fixture.otherURL
            store.screenshotDefaultsDraft.namePrefix = "Unapplied"
            store.screenshotDefaultsDraft.type = "pdf"
            store.screenshotDefaultsDraft.includeDate.toggle()
            store.screenshotDefaultsDraft.disableShadow.toggle()
            store.screenshotDefaultsDraft.showThumbnail.toggle()
            store.screenshotDefaultsDraft.captureMousePointer.toggle()

            XCTAssertEqual(store.snapshot?.screenshotDefaults, original.screenshotDefaults)
            XCTAssertEqual(store.processingConfiguration, originalConfiguration)
            XCTAssertEqual(store.screenshotLocationAccessURL, fixture.sourceURL)
            XCTAssertEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), originalBookmark)
            XCTAssertEqual(publications, 0)
            XCTAssertTrue(fixture.preferenceWrites.isEmpty)
        }
    }

    func testApplyCommitsOnceAfterSuccessfulWriteAndKeepsWatchedFolder() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            store.screenshotDefaultsDraft.namePrefix = "Applied"
            store.screenshotDefaultsDraft.locationURL = fixture.otherURL
            let draft = store.screenshotDefaultsDraft
            var writeCountsAtPublication: [Int] = []
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in
                writeCountsAtPublication.append(fixture.preferenceWrites.count)
            }
            defer { observation.cancel() }

            XCTAssertTrue(store.applyScreenshotDefaults())

            XCTAssertEqual(fixture.preferenceWrites, [draft])
            XCTAssertEqual(writeCountsAtPublication, [1])
            XCTAssertEqual(store.snapshot?.screenshotDefaults.namePrefix, "Applied")
            XCTAssertEqual(store.snapshot?.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertEqual(store.screenshotDefaultsDraft.locationURL, fixture.otherURL)
        }
    }

    func testFailedApplyPreservesAppliedSettingsAndDraftAndReportsError() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let original = store.screenshotDefaults
            store.screenshotDefaultsDraft.namePrefix = "Keep my draft"
            fixture.writeError = TestFailure.injected
            var publications = 0
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            XCTAssertFalse(store.applyScreenshotDefaults())

            XCTAssertEqual(store.screenshotDefaults, original)
            XCTAssertEqual(store.screenshotDefaultsDraft.namePrefix, "Keep my draft")
            XCTAssertEqual(publications, 0)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
        }
    }

    func testSandboxAndUnknownStatusNeverCallPreferenceWriter() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let original = store.screenshotDefaults
            store.screenshotDefaultsDraft.namePrefix = "Never write"
            for status in [SandboxStatus.enabled, .unknown] {
                fixture.sandboxStatus = status
                XCTAssertFalse(store.canApplyScreenshotDefaults)
                XCTAssertFalse(store.applyScreenshotDefaults())
                XCTAssertTrue(fixture.preferenceWrites.isEmpty)
                XCTAssertEqual(store.screenshotDefaults, original)
                XCTAssertEqual(store.screenshotDefaultsDraft.namePrefix, "Never write")
                XCTAssertFalse(store.statusText.isEmpty)
            }
        }
    }

    func testDeliberateRefreshUpdatesMetadataAndDraftButNotWatchedFolder() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            store.screenshotDefaultsDraft.namePrefix = "Discard on refresh"
            fixture.currentPreferences.namePrefix = "External change"
            fixture.currentPreferences.locationURL = fixture.otherURL
            var publications = 0
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            XCTAssertTrue(store.refreshScreenshotDefaults())

            XCTAssertEqual(store.screenshotDefaultsDraft, fixture.currentPreferences)
            XCTAssertEqual(store.screenshotDefaults.namePrefix, "External change")
            XCTAssertEqual(store.snapshot?.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertEqual(publications, 1)
            XCTAssertTrue(fixture.preferenceWrites.isEmpty)
        }
    }

    func testFailedRefreshPreservesDraftAndAppliedSettings() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            store.screenshotDefaultsDraft.namePrefix = "Keep"
            let draft = store.screenshotDefaultsDraft
            let applied = store.screenshotDefaults
            fixture.readError = TestFailure.injected

            XCTAssertFalse(store.refreshScreenshotDefaults())

            XCTAssertEqual(store.screenshotDefaultsDraft, draft)
            XCTAssertEqual(store.screenshotDefaults, applied)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
        }
    }

    func testBookmarkCreationFailureDoesNotCommitEitherFolderOrOverwriteError() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let sourceData = fixture.defaults.data(forKey: "screenshotLocationBookmark")
            let destinationData = fixture.defaults.data(forKey: "destinationBookmark")
            fixture.makeError = TestFailure.injected

            XCTAssertFalse(store.setDestinationURL(fixture.otherURL))
            XCTAssertEqual(store.destinationURL, fixture.destinationURL)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
            XCTAssertFalse(store.setScreenshotLocation(fixture.otherURL))
            XCTAssertEqual(store.screenshotLocationAccessURL, fixture.sourceURL)
            XCTAssertEqual(store.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
            XCTAssertEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), sourceData)
            XCTAssertEqual(fixture.defaults.data(forKey: "destinationBookmark"), destinationData)
        }
    }

    func testBookmarkSaveFailureDoesNotCommitSelectionOrRemoval() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            fixture.saveError = TestFailure.injected

            XCTAssertFalse(store.setDestinationURL(fixture.otherURL))
            XCTAssertEqual(store.destinationURL, fixture.destinationURL)
            XCTAssertFalse(store.setDestinationURL(nil))
            XCTAssertEqual(store.destinationURL, fixture.destinationURL)
            XCTAssertFalse(store.setScreenshotLocation(fixture.otherURL))
            XCTAssertEqual(store.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertEqual(store.screenshotLocationAccessURL, fixture.sourceURL)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
        }
    }

    func testSuccessfulSameSourceReselectionChangesProcessingConfiguration() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let before = store.processingConfiguration
            var revisions: [UInt64] = []
            let observation = store.$folderAccessRevision.dropFirst().sink { revisions.append($0) }
            defer { observation.cancel() }

            XCTAssertTrue(store.setScreenshotLocation(fixture.sourceURL))

            XCTAssertNotEqual(store.processingConfiguration, before)
            XCTAssertEqual(store.processingConfiguration.snapshot, before.snapshot)
            XCTAssertEqual(store.folderAccessRevision, before.folderAccessRevision + 1)
            XCTAssertEqual(revisions, [before.folderAccessRevision + 1])
        }
    }

    func testSuccessfulSameDestinationReselectionChangesProcessingConfiguration() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let before = store.processingConfiguration
            var revisions: [UInt64] = []
            let observation = store.$folderAccessRevision.dropFirst().sink { revisions.append($0) }
            defer { observation.cancel() }

            XCTAssertTrue(store.setDestinationURL(fixture.destinationURL))

            XCTAssertNotEqual(store.processingConfiguration, before)
            XCTAssertEqual(store.processingConfiguration.snapshot, before.snapshot)
            XCTAssertEqual(store.folderAccessRevision, before.folderAccessRevision + 1)
            XCTAssertEqual(revisions, [before.folderAccessRevision + 1])
        }
    }

    func testFailedBookmarkReselectionsDoNotChangeProcessingConfiguration() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let before = store.processingConfiguration
            var revisions: [UInt64] = []
            let observation = store.$folderAccessRevision.dropFirst().sink { revisions.append($0) }
            defer { observation.cancel() }

            fixture.makeError = TestFailure.injected
            XCTAssertFalse(store.setScreenshotLocation(fixture.sourceURL))
            XCTAssertFalse(store.setDestinationURL(fixture.destinationURL))
            XCTAssertEqual(store.processingConfiguration, before)

            fixture.makeError = nil
            fixture.saveError = TestFailure.injected
            XCTAssertFalse(store.setScreenshotLocation(fixture.sourceURL))
            XCTAssertFalse(store.setDestinationURL(fixture.destinationURL))

            XCTAssertEqual(store.processingConfiguration, before)
            XCTAssertEqual(store.folderAccessRevision, before.folderAccessRevision)
            XCTAssertTrue(revisions.isEmpty)
        }
    }

    func testOutputFirstThenSameDefaultSourceEnablesProcessingConfiguration() {
        withFixture { fixture in
            fixture.currentPreferences.locationURL = fixture.sourceURL
            let store = fixture.makeStore()
            let initialDefaults = store.screenshotDefaults
            XCTAssertTrue(store.setDestinationURL(fixture.destinationURL))
            let beforeSourceSelection = store.processingConfiguration
            XCTAssertNil(beforeSourceSelection.snapshot)

            XCTAssertTrue(store.setScreenshotLocation(fixture.sourceURL))

            XCTAssertEqual(store.screenshotDefaults, initialDefaults)
            XCTAssertNotEqual(store.processingConfiguration, beforeSourceSelection)
            XCTAssertTrue(store.processingConfiguration.isEnabled)
            XCTAssertEqual(store.processingConfiguration.snapshot?.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertEqual(store.processingConfiguration.snapshot?.destinationURL, fixture.destinationURL)
            XCTAssertEqual(store.folderAccessRevision, beforeSourceSelection.folderAccessRevision + 1)
        }
    }

    func testProcessingConfigurationIncludesEveryAppliedOption() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            var before = store.processingConfiguration

            store.isEnabled.toggle()
            XCTAssertNotEqual(store.processingConfiguration, before)
            before = store.processingConfiguration
            store.transferMode = .copy
            XCTAssertNotEqual(store.processingConfiguration, before)
            before = store.processingConfiguration
            store.outputFormat = .original
            XCTAssertNotEqual(store.processingConfiguration, before)
            before = store.processingConfiguration
            store.outputQuality = 42
            XCTAssertNotEqual(store.processingConfiguration, before)
            before = store.processingConfiguration
            store.filenameTemplate = "yyyyMMdd-{sequence}"
            XCTAssertNotEqual(store.processingConfiguration, before)
            before = store.processingConfiguration
            store.screenshotDefaultsDraft.namePrefix = "Applied"
            XCTAssertEqual(store.processingConfiguration, before)

            XCTAssertTrue(store.applyScreenshotDefaults())

            XCTAssertNotEqual(store.processingConfiguration, before)
        }
    }

    func testSelectionPublishesOnlyAfterBookmarkHasBeenSaved() {
        withFixture { fixture in
            let store = fixture.makeStore()
            var storedAtPublication: [Data?] = []
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in
                storedAtPublication.append(fixture.defaults.data(forKey: "screenshotLocationBookmark"))
            }
            defer { observation.cancel() }

            XCTAssertTrue(store.setScreenshotLocation(fixture.sourceURL))

            XCTAssertEqual(storedAtPublication.count, 1)
            XCTAssertNotNil(storedAtPublication.first!)
            XCTAssertTrue(fixture.preferenceWrites.isEmpty)
        }
    }

    func testSuccessfulCommitDoesNotOverwriteAnObserverAccessError() {
        withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let message = "Injected observer access failure"
            let observation = store.$screenshotDefaults.dropFirst().sink { _ in
                store.setStatus(message)
            }
            let destinationObservation = store.$destinationURL.dropFirst().sink { _ in
                store.setStatus(message)
            }
            defer {
                observation.cancel()
                destinationObservation.cancel()
            }

            XCTAssertTrue(store.setScreenshotLocation(fixture.otherURL))
            XCTAssertEqual(store.statusText, message)
            XCTAssertTrue(store.setDestinationURL(fixture.otherURL))
            XCTAssertEqual(store.statusText, message)
            XCTAssertTrue(store.applyScreenshotDefaults())
            XCTAssertEqual(store.statusText, message)
            XCTAssertTrue(store.refreshScreenshotDefaults())
            XCTAssertEqual(store.statusText, message)
        }
    }

    func testSelectedSourceRestoresIndependentlyOfExternalSaveLocation() {
        withFixture { fixture in
            let firstStore = fixture.makeStore()
            fixture.selectFolders(in: firstStore)
            fixture.currentPreferences.locationURL = fixture.otherURL

            let restored = fixture.makeStore()

            XCTAssertEqual(restored.screenshotLocationAccessURL, fixture.sourceURL)
            XCTAssertEqual(restored.snapshot?.screenshotDefaults.locationURL, fixture.sourceURL)
            XCTAssertEqual(restored.destinationURL, fixture.destinationURL)
            XCTAssertEqual(restored.screenshotDefaultsDraft.locationURL, fixture.otherURL)
            XCTAssertTrue(fixture.preferenceWrites.isEmpty)
        }
    }

    func testStaleBookmarkIsRenewedAndRenewalScopeIsBalanced() {
        withFixture { fixture in
            let oldData = fixture.seedSourceBookmark()
            fixture.staleURLs.insert(fixture.sourceURL)

            let store = fixture.makeStore()

            XCTAssertEqual(store.screenshotLocationAccessURL, fixture.sourceURL)
            XCTAssertNotEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), oldData)
            XCTAssertEqual(fixture.started, [fixture.sourceURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
            store.stopAccessing([fixture.sourceURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
        }
    }

    func testFailedStaleRenewalBalancesScopeAndRequiresReselection() {
        withFixture { fixture in
            let oldData = fixture.seedSourceBookmark()
            fixture.staleURLs.insert(fixture.sourceURL)
            fixture.saveError = TestFailure.injected

            let store = fixture.makeStore()

            XCTAssertNil(store.screenshotLocationAccessURL)
            XCTAssertNil(store.snapshot)
            XCTAssertEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), oldData)
            XCTAssertEqual(fixture.started, [fixture.sourceURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
        }
    }

    func testUnresolvableBookmarkIsNotDiscardedOrReportedAsSuccess() {
        withFixture { fixture in
            let oldData = fixture.seedSourceBookmark()
            fixture.resolveError = TestFailure.injected

            let store = fixture.makeStore()

            XCTAssertNil(store.screenshotLocationAccessURL)
            XCTAssertEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), oldData)
            XCTAssertTrue(store.statusText.contains(TestFailure.injected.localizedDescription))
            XCTAssertTrue(fixture.started.isEmpty)
            XCTAssertTrue(fixture.stopped.isEmpty)
        }
    }

    func testStaleScopeFailureDoesNotRenewOrStopAnUnstartedScope() {
        withFixture { fixture in
            let oldData = fixture.seedSourceBookmark()
            fixture.staleURLs.insert(fixture.sourceURL)
            fixture.failedStarts.insert(fixture.sourceURL)

            let store = fixture.makeStore()

            XCTAssertNil(store.screenshotLocationAccessURL)
            XCTAssertEqual(fixture.defaults.data(forKey: "screenshotLocationBookmark"), oldData)
            XCTAssertTrue(fixture.stopped.isEmpty)
            XCTAssertTrue(store.statusText.contains(fixture.sourceURL.path))
        }
    }

    func testLaterScopeFailureCleansUpEarlierSuccessfulStarts() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            fixture.failedStarts.insert(fixture.destinationURL)

            XCTAssertThrowsError(try store.startAccessingConfiguredDirectories())

            XCTAssertEqual(fixture.started, [fixture.sourceURL, fixture.destinationURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
            store.stopAccessing([fixture.sourceURL, fixture.destinationURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
            XCTAssertTrue(store.statusText.contains(fixture.destinationURL.path))
        }
    }

    func testFirstScopeFailureDoesNotStopAnyScope() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            fixture.failedStarts.insert(fixture.sourceURL)

            XCTAssertThrowsError(try store.startAccessingConfiguredDirectories())

            XCTAssertEqual(fixture.started, [fixture.sourceURL])
            XCTAssertTrue(fixture.stopped.isEmpty)
        }
    }

    func testFailedAdditionalAccessDoesNotReleaseExistingAccess() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            fixture.selectFolders(in: store)
            let existing = try store.startAccessingConfiguredDirectories()
            fixture.failedStarts.insert(fixture.destinationURL)

            XCTAssertThrowsError(try store.startAccessingConfiguredDirectories())
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL])
            store.stopAccessing(existing)

            XCTAssertEqual(fixture.stopped, [fixture.sourceURL, fixture.sourceURL, fixture.destinationURL])
        }
    }

    func testRepeatedAccessAndSharedDirectoryAreBalanced() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            XCTAssertTrue(store.setScreenshotLocation(fixture.sourceURL))
            XCTAssertTrue(store.setDestinationURL(fixture.sourceURL))

            let first = try store.startAccessingConfiguredDirectories()
            let second = try store.startAccessingConfiguredDirectories()
            XCTAssertEqual(first, [fixture.sourceURL])
            XCTAssertEqual(second, [fixture.sourceURL])
            store.stopAccessing(first)
            store.stopAccessing(second)
            store.stopAccessing([fixture.otherURL])

            XCTAssertEqual(fixture.started, [fixture.sourceURL, fixture.sourceURL])
            XCTAssertEqual(fixture.stopped, [fixture.sourceURL, fixture.sourceURL])
        }
    }

    func testAccessRequiresExplicitlySelectedSource() throws {
        try withFixture { fixture in
            let store = fixture.makeStore()
            XCTAssertTrue(store.setDestinationURL(fixture.destinationURL))

            XCTAssertThrowsError(try store.startAccessingConfiguredDirectories())

            XCTAssertNil(store.snapshot)
            XCTAssertTrue(fixture.started.isEmpty)
            XCTAssertTrue(fixture.stopped.isEmpty)
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) rethrows {
        let fixture = Fixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        try body(fixture)
    }
}

private enum TestFailure: LocalizedError {
    case injected

    var errorDescription: String? { "Injected settings test failure" }
}

@MainActor
private final class Fixture {
    let suiteName = "Recapture.SettingsStoreTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let sourceURL: URL
    let destinationURL: URL
    let otherURL: URL
    var currentPreferences: ScreenshotDefaults
    var sandboxStatus: SandboxStatus = .disabled
    var preferenceWrites: [ScreenshotDefaults] = []
    var makeError: Error?
    var resolveError: Error?
    var saveError: Error?
    var readError: Error?
    var writeError: Error?
    var staleURLs: Set<URL> = []
    var failedStarts: Set<URL> = []
    var started: [URL] = []
    var stopped: [URL] = []
    private var bookmarkGeneration = 0

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        sourceURL = root.appendingPathComponent("mock-source", isDirectory: true)
        destinationURL = root.appendingPathComponent("mock-destination", isDirectory: true)
        otherURL = root.appendingPathComponent("mock-other", isDirectory: true)
        currentPreferences = ScreenshotDefaults.fallback
        currentPreferences.locationURL = otherURL
    }

    func makeStore() -> SettingsStore {
        SettingsStore(
            defaults: defaults,
            bookmarks: BookmarkAccess(
                make: { [self] url in
                    if let makeError { throw makeError }
                    bookmarkGeneration += 1
                    return Data("\(bookmarkGeneration)|\(url.absoluteString)".utf8)
                },
                resolve: { [self] data in
                    if let resolveError { throw resolveError }
                    let encoded = String(decoding: data, as: UTF8.self)
                    guard let address = encoded.split(separator: "|", maxSplits: 1).last,
                          let url = URL(string: String(address)) else {
                        throw TestFailure.injected
                    }
                    return ResolvedBookmark(url: url, isStale: staleURLs.contains(url))
                },
                save: { [self] data, key, defaults in
                    if let saveError { throw saveError }
                    if let data {
                        defaults.set(data, forKey: key)
                    } else {
                        defaults.removeObject(forKey: key)
                    }
                },
                startAccessing: { [self] url in
                    started.append(url)
                    return !failedStarts.contains(url)
                },
                stopAccessing: { [self] url in stopped.append(url) }
            ),
            preferences: ScreenshotPreferences(
                sandboxStatus: { [self] in sandboxStatus },
                read: { [self] in
                    if let readError { throw readError }
                    return currentPreferences
                },
                write: { [self] value in
                    preferenceWrites.append(value)
                    if let writeError { throw writeError }
                    currentPreferences = value
                }
            )
        )
    }

    func selectFolders(in store: SettingsStore) {
        XCTAssertTrue(store.setScreenshotLocation(sourceURL))
        XCTAssertTrue(store.setDestinationURL(destinationURL))
    }

    @discardableResult
    func seedSourceBookmark() -> Data {
        let data = Data("old|\(sourceURL.absoluteString)".utf8)
        defaults.set(data, forKey: "screenshotLocationBookmark")
        return data
    }
}
