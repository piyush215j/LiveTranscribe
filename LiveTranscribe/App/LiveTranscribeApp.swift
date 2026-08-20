// LiveTranscribeApp.swift
// LiveTranscribe
//
// Application entry point. Creates the main window, Settings pane,
// and wires up the shared ViewModels via the SwiftUI environment.

import SwiftUI

@main
struct LiveTranscribeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Shared ViewModels — created once and injected into the environment
    @StateObject private var transcriptionVM = TranscriptionViewModel()
    @StateObject private var historyVM       = SessionHistoryViewModel()
    @StateObject private var aiVM            = AIViewModel()
    @StateObject private var settings        = AppSettings.shared
    @StateObject private var updateService   = UpdateService.shared

    var body: some Scene {

        // ── Main window ──────────────────────────────────────────────────
        WindowGroup {
            ContentView()
                .environmentObject(transcriptionVM)
                .environmentObject(historyVM)
                .environmentObject(aiVM)
                .environmentObject(settings)
                .environmentObject(updateService)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Pass the VM to the app delegate so it can show the
                    // floating window and respond to menu-bar actions.
                    appDelegate.transcriptionVM = transcriptionVM
                    appDelegate.historyVM       = historyVM
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updateService.checkForUpdates(manual: true) }
                }
            }

            // ── File menu additions ──────────────────────────────────────
            CommandGroup(after: .newItem) {
                Divider()
                Button("Start New Recording") {
                    historyVM.selectedSession = nil
                    Task { await transcriptionVM.startTranscription(resuming: nil) }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(transcriptionVM.isCapturing)

                Button("Resume Selected Session") {
                    if let s = historyVM.selectedSession {
                        Task { await transcriptionVM.startTranscription(resuming: s) }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(transcriptionVM.isCapturing || historyVM.selectedSession == nil)

                Button("Stop Recording") {
                    Task { await transcriptionVM.stopTranscription() }
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!transcriptionVM.isCapturing)

                Divider()

                Button("Toggle Floating Window") {
                    appDelegate.toggleFloatingWindow()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            // ── Edit ─────────────────────────────────────────────────────
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Search Transcript…") {
                    // Handled inside ContentView via focused binding
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        // ── Settings window ──────────────────────────────────────────────
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(transcriptionVM)
                .preferredColorScheme(.dark)
        }
    }
}
