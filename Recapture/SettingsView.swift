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
    @State private var showingTemplateHelp = false
    private let labelWidth: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    generalSection
                    screenshotSection
                    outputSection
                }
            }

            HStack {
                Text(settings.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .help(settings.statusText)
                    .textSelection(.enabled)
                Spacer()
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 880, height: 760)
    }

    private var generalSection: some View {
        sectionBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    Toggle("Enable Recapture", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)

                    Toggle("Open at login", isOn: Binding(
                        get: { settings.startAtLogin },
                        set: { settings.startAtLogin = $0 }
                    ))
                }

                settingsRow("Transfer") {
                    Picker("Transfer", selection: $settings.transferMode) {
                        ForEach(TransferMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            .padding(10)
        }
    }

    private var screenshotSection: some View {
        sectionBox("macOS Screenshot Defaults") {
            VStack(alignment: .leading, spacing: 12) {
                settingsRow("Watched folder") {
                    HStack {
                        pathText(settings.screenshotLocationDisplayText)
                        Spacer()
                        Button("Choose") {
                            chooseDirectory { settings.setScreenshotLocation($0) }
                        }
                    }
                }

                Text("Choose the same folder as Screenshot’s Options > Save to. This selection only controls Re-Capture and does not change macOS settings.")
                    .foregroundStyle(.secondary)
                    .font(.callout)

                if settings.canApplyScreenshotDefaults {
                    screenshotDefaultsEditor
                } else {
                    Text("Direct changes to macOS defaults are unavailable. Use Screenshot (Shift-Command-5).")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                HStack {
                    Button("Open Screenshot") {
                        settings.openScreenshotSettings()
                    }
                    Button("Refresh macOS Defaults") {
                        settings.refreshScreenshotDefaults()
                    }
                    Spacer()
                    if settings.canApplyScreenshotDefaults {
                        Button("Apply to macOS") {
                            settings.applyScreenshotDefaults()
                        }
                    }
                }

                Text("Refreshing replaces unapplied edits but keeps your watched folder.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(10)
        }
    }

    private var screenshotDefaultsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsRow("Save to") {
                HStack {
                    pathText(settings.screenshotDefaultsDraft.locationURL.path)
                    Spacer()
                    Button("Choose") {
                        chooseDirectory { settings.screenshotDefaultsDraft.locationURL = $0 }
                    }
                }
            }

            settingsRow("Name prefix") {
                TextField("Name prefix", text: $settings.screenshotDefaultsDraft.namePrefix)
                    .frame(width: 260)
            }

            settingsRow("Source format") {
                Picker("Source format", selection: Binding(
                    get: { ScreenshotSourceFormat.fromScreencaptureValue(settings.screenshotDefaultsDraft.type) },
                    set: { settings.screenshotDefaultsDraft.type = $0.screencaptureValue }
                )) {
                    ForEach(ScreenshotSourceFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 260, alignment: .leading)
            }

            settingsRow("") {
                HStack(spacing: 24) {
                    Toggle("Include date in filename", isOn: $settings.screenshotDefaultsDraft.includeDate)
                    Toggle("Disable window shadow", isOn: $settings.screenshotDefaultsDraft.disableShadow)
                }
            }

            settingsRow("") {
                HStack(spacing: 24) {
                    Toggle("Show floating thumbnail", isOn: $settings.screenshotDefaultsDraft.showThumbnail)
                    Toggle("Include mouse pointer", isOn: $settings.screenshotDefaultsDraft.captureMousePointer)
                }
            }
        }
    }

    private var outputSection: some View {
        sectionBox("Recapture Output") {
            VStack(alignment: .leading, spacing: 12) {
                settingsRow("Destination") {
                    HStack {
                        pathText(settings.destinationDisplayText)
                        Spacer()
                        Button("Choose") {
                            chooseDirectory { settings.setDestinationURL($0) }
                        }
                        Button("Open in Finder") {
                            settings.openDestinationInFinder()
                        }
                        .disabled(settings.destinationURL == nil)
                    }
                }

                settingsRow("") {
                    Text("Output folder must be selected with the system picker before Re-Capture saves files.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                settingsRow("Filename template") {
                    HStack {
                        Picker("Template preset", selection: templatePresetBinding) {
                            ForEach(filenameTemplatePresets) { preset in
                                Text(LocalizedStringKey(preset.titleKey)).tag(preset.id)
                            }
                            Text("Custom").tag("custom")
                        }
                        .labelsHidden()
                        .frame(width: 190)

                        TextField("Filename template", text: $settings.filenameTemplate)
                            .frame(width: 310)

                        Button {
                            showingTemplateHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingTemplateHelp, arrowEdge: .trailing) {
                            templateHelp
                        }
                    }
                }

                if let templateValidationError {
                    settingsRow("") {
                        Text(templateValidationError)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                settingsRow("Output format") {
                    HStack {
                        Picker("Output format", selection: $settings.outputFormat) {
                            ForEach(OutputFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 136, alignment: .leading)

                        if settings.outputFormat.supportsCompressionQuality {
                            Stepper("\(settings.outputQuality)%", value: $settings.outputQuality, in: 1...100)
                                .frame(width: 120)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Rename/Convert Existing Screenshots") {
                        controller.processBulk()
                    }
                    .disabled(settings.snapshot == nil || templateValidationError != nil)
                }
            }
            .padding(10)
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

    private var templatePresetBinding: Binding<String> {
        Binding(
            get: {
                filenameTemplatePresets.first { $0.value == settings.filenameTemplate }?.id ?? "custom"
            },
            set: { id in
                guard let preset = filenameTemplatePresets.first(where: { $0.id == id }) else { return }
                settings.filenameTemplate = preset.value
            }
        )
    }

    private var templateHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filename Template")
                .font(.headline)
            Text("Date parts use DateFormatter syntax, then Recapture replaces tokens.")
            Text("Examples: yyyyMMdd-HHmmss, yyyy-MM-dd-HH.mm.ss")
            Divider()
            Text("{app}: frontmost app name at processing time")
            Text("{title}: frontmost window title when available")
            Text("{sequence}: four-digit processing sequence")
        }
        .frame(width: 360, alignment: .leading)
        .padding(14)
    }

    private func sectionBox<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            content()
        } label: {
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }

    private func settingsRow<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pathText(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func chooseDirectory(_ onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}
