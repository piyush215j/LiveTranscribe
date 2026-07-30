// SettingsView.swift
// LiveTranscribe
//
// Preferences window (opened via Cmd+, or the Settings scene).
// Organised into tabs: General, Appearance, Folders, Advanced.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var transcriptionVM: TranscriptionViewModel

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General",    systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            FoldersTab()
                .tabItem { Label("Folders",    systemImage: "folder") }
            AdvancedTab()
                .tabItem { Label("Advanced",   systemImage: "slider.horizontal.3") }
        }
        .environmentObject(settings)
        .environmentObject(transcriptionVM)
        .frame(width: 500, height: 380)
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Whisper model", selection: $settings.whisperModel) {
                    ForEach(WhisperModelSize.allCases) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.displayName)
                            Text(m.accuracyDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }.tag(m)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("Language", selection: $settings.language) {
                    ForEach(TranscriptionLanguage.all) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
            }

            Section("Session") {
                Toggle("Auto-save sessions", isOn: $settings.autoSave)
                Toggle("Show timestamps",    isOn: $settings.showTimestamps)
                Toggle("Auto-scroll to latest segment", isOn: $settings.autoScroll)
            }

            Section("Software Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LiveTranscribe v\(UpdateService.shared.currentVersion)")
                            .font(.system(size: 13, weight: .medium))
                        Text(UpdateService.shared.isInstalledInApplications ? "Installed in /Applications" : "Standalone bundle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") {
                        Task { await UpdateService.shared.checkForUpdates(manual: true) }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer Local Update")
                            .font(.system(size: 13, weight: .medium))
                        Text("Rebuilds source code & updates /Applications/LiveTranscribe.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Rebuild & Update App") {
                        Task { await UpdateService.shared.rebuildAndInstallLocally() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance tab

private struct AppearanceTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Transcript Text") {
                HStack {
                    Text("Font size")
                    Spacer()
                    Slider(value: $settings.fontSize, in: 10...28, step: 1)
                        .frame(width: 180)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                // Preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("[00:12]")
                            .font(.system(size: settings.fontSize - 2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("This is how your transcript will look.")
                            .font(.system(size: settings.fontSize))
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
            }

            Section("Floating Window") {
                HStack {
                    Text("Background opacity")
                    Spacer()
                    Slider(value: $settings.floatingWindowOpacity, in: 0.5...1.0, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int(settings.floatingWindowOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Stepper(
                    "Lines shown: \(settings.floatingWindowLineCount)",
                    value: $settings.floatingWindowLineCount,
                    in: 2...20
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Folders tab

private struct FoldersTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showTranscriptPicker = false
    @State private var showExportPicker     = false

    var body: some View {
        Form {
            Section("Storage") {
                folderRow(
                    label: "Transcript folder",
                    path: $settings.transcriptFolderPath,
                    showPicker: $showTranscriptPicker
                )

                folderRow(
                    label: "Export folder",
                    path: $settings.exportFolderPath,
                    showPicker: $showExportPicker
                )
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("SQLite database is stored in ~/Library/Application Support/LiveTranscribe/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showTranscriptPicker) {
            FolderPickerView(selectedPath: $settings.transcriptFolderPath)
        }
        .sheet(isPresented: $showExportPicker) {
            FolderPickerView(selectedPath: $settings.exportFolderPath)
        }
    }

    private func folderRow(
        label: String,
        path: Binding<String>,
        showPicker: Binding<Bool>
    ) -> some View {
        HStack {
            Label(label, systemImage: "folder")
            Spacer()
            Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Change…") { showPicker.wrappedValue = true }
        }
    }
}

// MARK: - Advanced tab

private struct AdvancedTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Inference") {
                Toggle("Voice Activity Detection (VAD)", isOn: $settings.vadEnabled)
                    .help("Filters out silent periods to reduce hallucinations.")

                HStack {
                    Text("Chunk duration")
                    Spacer()
                    Slider(value: $settings.chunkDuration, in: 3...15, step: 1)
                        .frame(width: 180)
                    Text("\(Int(settings.chunkDuration)) s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .help("Seconds of audio processed per Whisper inference call. Shorter = lower latency.")
            }

            Section("Reset") {
                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Folder picker helper

struct FolderPickerView: View {
    @Binding var selectedPath: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Folder")
                .font(.headline)
            Text("Current: \(selectedPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Choose Folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles      = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        selectedPath = panel.url?.path ?? selectedPath
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
