// ContentView.swift
// LiveTranscribe
//
// Root view: NavigationSplitView with session sidebar and transcript detail.
// The toolbar hosts recording controls and the floating window toggle.

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var transcriptionVM: TranscriptionViewModel
    @EnvironmentObject var historyVM:       SessionHistoryViewModel
    @EnvironmentObject var aiVM:            AIViewModel
    @EnvironmentObject var settings:        AppSettings
    @EnvironmentObject var updateService:   UpdateService

    @State private var showAIPanel  = false
    @State private var showExport   = false
    @State private var selectedExportFormat: ExportFormat = .txt
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            TranscriptDetailView()
        }
        .navigationTitle("LiveTranscribe")
        .toolbar {
            mainToolbar
        }
        // AI Sheet
        .sheet(isPresented: $showAIPanel) {
            AIPanelView(session: historyVM.selectedSession
                        ?? transcriptionVM.currentSession
                        ?? TranscriptSession.empty())
                .environmentObject(aiVM)
                .frame(minWidth: 680, minHeight: 540)
        }
        // Error alert
        .alert("Error", isPresented: Binding(
            get: { transcriptionVM.errorMessage != nil },
            set: { if !$0 { transcriptionVM.errorMessage = nil } }
        )) {
            Button("OK") { transcriptionVM.errorMessage = nil }
        } message: {
            Text(transcriptionVM.errorMessage ?? "")
        }
        // Onboarding sheet
        .sheet(isPresented: $transcriptionVM.showOnboarding) {
            OnboardingView()
                .frame(minWidth: 540, minHeight: 420)
        }
        // Update modal sheet
        .sheet(isPresented: $updateService.showUpdateModal) {
            UpdateView()
                .environmentObject(updateService)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {

        // Left: Record button
        ToolbarItemGroup(placement: .navigation) {
            RecordButton()
                .environmentObject(transcriptionVM)
        }

        // Centre: Status + audio level
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(transcriptionVM.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AudioLevelBar(level: transcriptionVM.audioLevel)
                    .frame(width: 160, height: 4)
                    .opacity(transcriptionVM.isCapturing ? 1 : 0)
            }
        }

        // Right: AI, floating window, model picker
        ToolbarItemGroup(placement: .primaryAction) {
            // Model selector
            Picker("Model", selection: $settings.whisperModel) {
                ForEach(WhisperModelSize.allCases) { m in
                    Text(m.shortName).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .disabled(transcriptionVM.isCapturing)

            Divider()

            // AI features
            Button {
                showAIPanel = true
            } label: {
                Label("AI", systemImage: "sparkles")
            }
            .help("AI Features — summarise, notes, flashcards…")

            // Floating window
            Button {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.toggleFloatingWindow()
                }
            } label: {
                Label("Float", systemImage: "pip")
            }
            .help("Toggle floating transcript window")

            Divider()

            // Dependency Health Indicator
            DependencyHealthButton()
                .environmentObject(transcriptionVM)
        }
    }
}

// MARK: - Record Button

private struct RecordButton: View {

    @EnvironmentObject var vm: TranscriptionViewModel

    var body: some View {
        Button {
            Task {
                if vm.isCapturing {
                    await vm.stopTranscription()
                } else {
                    await vm.startTranscription()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(vm.isCapturing ? Color.red : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .shadow(color: vm.isCapturing ? .red.opacity(0.5) : .clear,
                            radius: vm.isCapturing ? 6 : 0)

                if vm.isCapturing {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .buttonStyle(.plain)
        .help(vm.isCapturing ? "Stop Recording" : "Start Recording")
        .overlay(alignment: .bottomTrailing) {
            if vm.isCapturing {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(vm.isPaused ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: vm.isPaused)
            }
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(level * 2.5, 1.0)))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
    }
}

// MARK: - Dependency Health Button & Popover

struct DependencyHealthButton: View {

    @EnvironmentObject var vm: TranscriptionViewModel
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.dependencyState.isHealthy ? "shield.checkmark.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(vm.dependencyState.isHealthy ? Color.green : Color.orange)
                    .font(.system(size: 13))
            }
        }
        .buttonStyle(.plain)
        .help("System Dependencies Status — \(vm.dependencyState.labelText)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Dependency Health", systemImage: "shield.fill")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Circle()
                        .fill(vm.dependencyState.isHealthy ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: vm.dependencyState == .permissionMissing ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(vm.dependencyState == .permissionMissing ? Color.red : Color.green)
                        Text("Screen Recording Permission")
                            .font(.system(size: 12))
                    }

                    HStack(spacing: 8) {
                        Image(systemName: vm.dependencyState == .whisperMissing ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(vm.dependencyState == .whisperMissing ? Color.red : Color.green)
                        Text("Python 3 & faster-whisper")
                            .font(.system(size: 12))
                    }
                }

                Divider()

                HStack {
                    Button {
                        Task { await vm.checkDependencyHealth() }
                    } label: {
                        Label("Recheck", systemImage: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        showPopover = false
                        vm.showOnboarding = true
                    } label: {
                        Text("Setup Guide")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 270)
        }
    }
}
