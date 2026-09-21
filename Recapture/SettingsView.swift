import SwiftUI

private struct FilenameTemplatePreset: Identifiable, Sendable {
    let id: String
    let titleKey: String
    let value: String
}

private let filenameTemplatePresets = [
    FilenameTemplatePreset(id: "timestamp", titleKey: "Timestamp", value: "yyyyMMdd-HHmmss"),
    FilenameTemplatePreset(id: "timestamp-sequence", titleKey: "Timestamp + Sequence", value: "yyyyMMdd-HHmmss-{sequence}"),
    FilenameTemplatePreset(id: "date-app", titleKey: "Date + App", value: "yyyyMMdd-{app}"),
    FilenameTemplatePreset(id: "date-app-title", titleKey: "Date + App + Title", value: "yyyyMMdd-HHmmss-{app}-{title}"),
]

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var controller: AppController
    @AppStorage("settingsPane") private var selectedPane = "general"
    @State private var showingTemplateHelp = false
    @State private var showingBulkConfirmation = false
    @State private var previewDate = Date()
    @State private var customTemplateSelected = false
    @FocusState private var templateFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedPane) {
                generalPane
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag("general")
                foldersPane
                    .tabItem { Label("Folders", systemImage: "folder") }
                    .tag("folders")
                outputPane
                    .tabItem { Label("Recapture Output", systemImage: "photo") }
                    .tag("output")
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
                Text(settings.statusText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Status"))
            .accessibilityValue(settings.statusText)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 600, idealHeight: 680)
    }

    private var generalPane: some View {
        Form {
            Section {
                Toggle("Enable Recapture", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                Toggle("Open at login", isOn: Binding(
                    get: { settings.startAtLogin },
                    set: { settings.startAtLogin = $0 }
                ))
            } header: {
                Text("Automatic processing")
            } footer: {
                Text("Automatically rename and convert screenshots in your watched folder.")
            }

            Section {
                LabeledContent("Automatic processing") {
                    Label {
                        Text(settings.isEnabled ? "Enabled" : "Paused")
                    } icon: {
                        Image(systemName: settings.isEnabled ? "checkmark.circle" : "pause.circle")
                    }
                }
                if settings.snapshot == nil {
                    Text("Choose a watched folder and an output folder to finish setup.")
                        .foregroundStyle(.secondary)
                    Button("Choose folders…") { selectedPane = "folders" }
                } else {
                    Button("Open Destination in Finder") {
                        settings.openDestinationInFinder()
                    }
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("Re-Capture processes your screenshots locally on this Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private var foldersPane: some View {
        Form {
            Section {
                folderRow("Watched folder", value: settings.screenshotLocationDisplayText,
                          selected: settings.screenshotLocationAccessURL != nil,
                          chooseLabel: "Choose watched folder…") {
                    chooseDirectory(title: "Watched folder", currentURL: settings.screenshotLocationAccessURL) {
                        settings.setScreenshotLocation($0)
                    }
                }
                Button("Open Screenshot") { settings.openScreenshotSettings() }
            } header: {
                Text("Watched folder")
            } footer: {
                Text("Choose the same folder as Screenshot’s Options > Save to. This selection only controls Re-Capture and does not change macOS settings.")
            }

            Section {
                folderRow("Destination", value: settings.destinationDisplayText,
                          selected: settings.destinationURL != nil,
                          chooseLabel: "Choose output folder…") {
                    chooseDirectory(title: "Destination", currentURL: settings.destinationURL) {
                        settings.setDestinationURL($0)
                    }
                }
                Button("Open in Finder") { settings.openDestinationInFinder() }
                    .disabled(settings.destinationURL == nil)
            } header: {
                Text("Destination")
            } footer: {
                Text("Output folder must be selected with the system picker before Re-Capture saves files.")
            }

            // Foreign preferences are editable only in confirmed non-sandboxed builds.
            Section {
                if settings.canApplyScreenshotDefaults {
                    DisclosureGroup("Advanced screenshot settings") {
                        screenshotDefaultsEditor
                    }
                } else {
                    Button("Refresh macOS Defaults") { settings.refreshScreenshotDefaults() }
                }
            } header: {
                Text("macOS Screenshot Defaults")
            } footer: {
                if !settings.canApplyScreenshotDefaults {
                    Text("Direct changes to macOS defaults are unavailable. Use Screenshot (Shift-Command-5).")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var screenshotDefaultsEditor: some View {
        Group {
            LabeledContent("Save to") {
                folderRow("Save to", value: settings.screenshotDefaultsDraft.locationURL.path,
                          selected: true, chooseLabel: "Choose screenshot save location…") {
                    chooseDirectory(title: "Save to", currentURL: settings.screenshotDefaultsDraft.locationURL) {
                        settings.screenshotDefaultsDraft.locationURL = $0
                    }
                }
            }
            TextField("Name prefix", text: $settings.screenshotDefaultsDraft.namePrefix)
            Picker("Source format", selection: Binding(
                get: { ScreenshotSourceFormat.fromScreencaptureValue(settings.screenshotDefaultsDraft.type) },
                set: { settings.screenshotDefaultsDraft.type = $0.screencaptureValue }
            )) {
                ForEach(ScreenshotSourceFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            Toggle("Include date in filename", isOn: $settings.screenshotDefaultsDraft.includeDate)
            Toggle("Disable window shadow", isOn: $settings.screenshotDefaultsDraft.disableShadow)
            Toggle("Show floating thumbnail", isOn: $settings.screenshotDefaultsDraft.showThumbnail)
            Toggle("Include mouse pointer", isOn: $settings.screenshotDefaultsDraft.captureMousePointer)
            HStack {
                Button("Refresh macOS Defaults") { settings.refreshScreenshotDefaults() }
                Spacer()
                Button("Apply to macOS") { settings.applyScreenshotDefaults() }
            }
            Text("Refreshing replaces unapplied edits but keeps your watched folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var outputPane: some View {
        Form {
            Section {
                Picker("Transfer", selection: $settings.transferMode) {
                    ForEach(TransferMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Original files")
            } footer: {
                Text(settings.transferMode == .move
                     ? "Move removes the original after the output is saved successfully."
                     : "Copy keeps the original in your watched folder.")
            }

            Section {
                Picker("Template preset", selection: templatePresetBinding) {
                    ForEach(filenameTemplatePresets) { preset in
                        Text(LocalizedStringKey(preset.titleKey)).tag(preset.id)
                    }
                    Text("Custom").tag("custom")
                }
                LabeledContent("Filename template") {
                    TextField("Filename template", text: $settings.filenameTemplate)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($templateFieldFocused)
                        .frame(maxWidth: .infinity)
                }
                if let templateValidationError {
                    Label {
                        Text(templateValidationError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if let filenamePreview {
                    LabeledContent("Example name") {
                        Text(filenamePreview)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(filenamePreview)
                    }
                }
                Button {
                    showingTemplateHelp.toggle()
                } label: {
                    Label("Filename template help", systemImage: "questionmark.circle")
                }
                .popover(isPresented: $showingTemplateHelp) { templateHelp }
            } header: {
                Text("Filename Template")
            } footer: {
                Text("Example uses sample app and window names, sequence 0001, and no file extension.")
            }

            Section("Output format") {
                Picker("Output format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                if settings.outputFormat.supportsCompressionQuality {
                    LabeledContent("Quality") {
                        Stepper(value: $settings.outputQuality, in: 1...100) {
                            Text("\(settings.outputQuality)%")
                                .monospacedDigit()
                        }
                        .accessibilityLabel(Text("Quality"))
                        .accessibilityValue(Text("\(settings.outputQuality)%"))
                    }
                }
            }

            Section {
                Button("Rename/Convert Existing Screenshots") {
                    showingBulkConfirmation = true
                }
                .disabled(settings.snapshot == nil || templateValidationError != nil)
                if settings.snapshot == nil {
                    Button("Choose folders…") { selectedPane = "folders" }
                }
            } footer: {
                Text("Process existing screenshots using the current output settings. You can also do this while paused.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Process existing screenshots?", isPresented: $showingBulkConfirmation) {
            Button("Process screenshots", role: settings.transferMode == .move ? .destructive : nil) {
                controller.processBulk()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(settings.transferMode == .move
                 ? "Existing screenshots in the watched folder will be renamed or converted. Originals are removed only after saving succeeds."
                 : "Existing screenshots in the watched folder will be copied and renamed or converted. Originals are kept.")
        }
    }

    private var templateValidationError: String? {
        do {
            try TemplateRenderer.validate(template: settings.filenameTemplate)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var filenamePreview: String? {
        try? TemplateRenderer.render(
            template: settings.filenameTemplate, date: previewDate, sequence: 1,
            activeWindowInfo: ActiveWindowInfo(appName: "App", windowTitle: "Window")
        )
    }

    private var templatePresetBinding: Binding<String> {
        Binding(
            get: {
                customTemplateSelected ? "custom"
                    : filenameTemplatePresets.first { $0.value == settings.filenameTemplate }?.id ?? "custom"
            },
            set: { id in
                if id == "custom" {
                    customTemplateSelected = true
                    templateFieldFocused = true
                    return
                }
                guard let preset = filenameTemplatePresets.first(where: { $0.id == id }) else { return }
                customTemplateSelected = false
                settings.filenameTemplate = preset.value
            }
        )
    }

    private var templateHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filename Template").font(.headline)
                Spacer()
                Button("Done") { showingTemplateHelp = false }
                    .keyboardShortcut(.cancelAction)
            }
            Text("Date parts use DateFormatter syntax, then Recapture replaces tokens.")
            Text("Examples: yyyyMMdd-HHmmss, yyyy-MM-dd-HH.mm.ss")
            Divider()
            Text("{app}: frontmost app name at processing time")
            Text("{title}: frontmost window title when available")
            Text("{sequence}: four-digit processing sequence")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 380, alignment: .leading)
        .padding(20)
    }

    private func folderRow(_ title: LocalizedStringKey, value: String, selected: Bool,
                           chooseLabel: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "folder" : "folder.badge.questionmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(title))
                .accessibilityValue(value)
            Button("Choose…", action: action)
                .accessibilityLabel(Text(chooseLabel))
        }
    }

    private func chooseDirectory(title: String, currentURL: URL?,
                                 _ onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL
        panel.title = NSLocalizedString(title, comment: "Folder picker title")
        panel.prompt = String(localized: "Choose")
        // Use a sheet so cancellation restores focus to the settings window.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { onSelect(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}
