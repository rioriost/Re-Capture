import AppKit
import SwiftUI

@main
@MainActor
struct RecaptureApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var controller: AppController
    @Environment(\.openSettings) private var openSettings

    init() {
        let settings = SettingsStore()
        let controller = AppController()
        controller.bind(to: settings)
        _settings = StateObject(wrappedValue: settings)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            Button(settings.isEnabled ? String(localized: "Pause Recapture") : String(localized: "Enable Recapture")) {
                settings.isEnabled.toggle()
                controller.reconfigure()
            }

            Button("Open Destination in Finder") {
                settings.openDestinationInFinder()
            }

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("About Recapture...") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Divider()

            Button("Quit Recapture") {
                NSApp.terminate(nil)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: settings.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .symbolRenderingMode(.palette)
                Text(LocalizedStringKey(settings.isEnabled ? "On" : "Off"))
            }
            .foregroundStyle(settings.isEnabled ? .green : .red)
        }
        .onChange(of: settings.screenshotDefaults) { _, _ in
            controller.reconfigure()
        }
        .onChange(of: settings.destinationURL) { _, _ in
            controller.reconfigure()
        }
        .onChange(of: settings.outputFormat) { _, _ in
            controller.reconfigure()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(controller)
        }
    }
}
