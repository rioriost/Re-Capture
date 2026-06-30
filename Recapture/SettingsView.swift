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
            generalSection
            screenshotSection
            outputSection

            HStack {
                Text(settings.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 880, height: 620)
    }

    private var generalSection: some View {
        sectionBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    Toggle("Enable Recapture", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: settings.isEnabled) { _, _ in controller.reconfigure() }

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
                settingsRow("Save to") {
                    HStack {
                        pathText(settings.screenshotDefaults.locationURL.path)
                        Spacer()
                        Button("Choose") {
                            chooseDirectory { url in
                                settings.setScreenshotLocation(url)
                                controller.reconfigure()
                            }
                        }
                    }
                }

                settingsRow("Name prefix") {
                    TextField("Name prefix", text: Binding(
                        get: { settings.screenshotDefaults.namePrefix },
                        set: { settings.screenshotDefaults.namePrefix = $0 }
                    ))
                    .frame(width: 260)
                }

                settingsRow("Source format") {
                    Picker("Source format", selection: Binding(
                        get: { ScreenshotSourceFormat.fromScreencaptureValue(settings.screenshotDefaults.type) },
                        set: { settings.screenshotDefaults.type = $0.screencaptureValue }
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
                        Toggle("Include date in filename", isOn: Binding(
                            get: { settings.screenshotDefaults.includeDate },
                            set: { settings.screenshotDefaults.includeDate = $0 }
                        ))
                        Toggle("Disable window shadow", isOn: Binding(
                            get: { settings.screenshotDefaults.disableShadow },
                            set: { settings.screenshotDefaults.disableShadow = $0 }
                        ))
                    }
                }

                settingsRow("") {
                    HStack(spacing: 24) {
                        Toggle("Show floating thumbnail", isOn: Binding(
                            get: { settings.screenshotDefaults.showThumbnail },
                            set: { settings.screenshotDefaults.showThumbnail = $0 }
                        ))
                        Toggle("Include mouse pointer", isOn: Binding(
                            get: { settings.screenshotDefaults.captureMousePointer },
                            set: { settings.screenshotDefaults.captureMousePointer = $0 }
                        ))
                    }
                }

                HStack {
                    Spacer()
                    Button("Apply to macOS") {
                        settings.applyScreenshotDefaults()
                        controller.reconfigure()
                    }
                }
            }
            .padding(10)
        }
    }

    private var outputSection: some View {
        sectionBox("Recapture Output") {
            VStack(alignment: .leading, spacing: 12) {
                settingsRow("Destination") {
                    HStack {
                        pathText(settings.effectiveDestinationURL.path)
                        Spacer()
                        Button("Choose") {
                            chooseDirectory { settings.setDestinationURL($0) }
                        }
                        Button("Use screenshot folder") {
                            settings.setDestinationURL(nil)
                        }
                        Button("Open in Finder") {
                            settings.openDestinationInFinder()
                        }
                    }
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
                }
            }
            .padding(10)
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
