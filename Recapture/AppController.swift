import Foundation

@MainActor
final class AppController: ObservableObject {
    private let watcher = ScreenshotWatcher()
    private let processor = ScreenshotProcessor()
    private let processingQueue = DispatchQueue(label: "st.rio.recapture.processor", qos: .utility)
    private var pendingTask: Task<Void, Never>?
    private weak var settingsStore: SettingsStore?

    func bind(to settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        watcher.onEvent = { [weak self] in
            Task { @MainActor in
                self?.scheduleProcessing()
            }
        }
        reconfigure()
    }

    func reconfigure() {
        guard let settingsStore else { return }
        if settingsStore.isEnabled {
            watcher.start(watching: settingsStore.screenshotDefaults.locationURL)
            scheduleProcessing()
        } else {
            pendingTask?.cancel()
            watcher.stop()
            settingsStore.setStatus(String(localized: "Paused"))
        }
    }

    func processBulk() {
        processNow(bulk: true)
    }

    private func scheduleProcessing() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            processNow(bulk: false)
        }
    }

    private func processNow(bulk: Bool) {
        guard let settingsStore, settingsStore.isEnabled || bulk else { return }

        let accessURLs = settingsStore.startAccessingConfiguredDirectories()
        let snapshot = SettingsSnapshot(
            screenshotDefaults: settingsStore.screenshotDefaults,
            destinationURL: settingsStore.effectiveDestinationURL,
            filenameTemplate: settingsStore.filenameTemplate,
            outputFormat: settingsStore.outputFormat,
            outputQuality: settingsStore.outputQuality,
            transferMode: settingsStore.transferMode
        )

        processingQueue.async { [processor] in
            let result = processor.process(settings: snapshot, bulk: bulk)
            Task { @MainActor in
                settingsStore.stopAccessing(accessURLs)
                settingsStore.setStatus(result.message)
            }
        }
    }
}
