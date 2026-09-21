import AppKit
import SwiftUI

@main
@MainActor
struct RecaptureApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var controller: AppController
    @Environment(\.openSettings) private var openSettings

    init() {
        let settings: SettingsStore
        let controller = AppController()
        if ProcessInfo.processInfo.environment["RECAPTURE_TESTING"] == "1" {
            let suiteName = "st.rio.recapture.tests.host"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            settings = SettingsStore(
                defaults: defaults,
                preferences: ScreenshotPreferences(
                    sandboxStatus: { .enabled },
                    read: { .fallback },
                    write: { _ in throw ScreenshotPreferencesError.sandboxed }
                )
            )
        } else {
            settings = SettingsStore()
            controller.bind(to: settings)
        }
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            Button(settings.isEnabled ? String(localized: "Pause Recapture") : String(localized: "Enable Recapture")) {
                settings.isEnabled.toggle()
            }

            Button("Open Destination in Finder") {
                settings.openDestinationInFinder()
            }
            .disabled(settings.destinationURL == nil)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("About Recapture...") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Link("Privacy Policy", destination: URL(string: "https://github.com/rioriost/Re-Capture/blob/v1.1.1/PRIVACY.md")!)

            Divider()

            Button("Quit Recapture") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Label("Re-Capture",
                  systemImage: settings.isEnabled ? "camera.aperture" : "pause.circle")
                .accessibilityValue(Text(settings.isEnabled ? "On" : "Off"))
        }
        .onChange(of: settings.processingConfiguration) { _, _ in
            controller.reconfigure()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(controller)
        }
        .defaultSize(width: 700, height: 680)
        .windowResizability(.contentMinSize)
    }
}
