// MenuBarView.swift
// LiveTranscribe
//
// Compact popover content shown when clicking the menu bar status item.
// Provides quick access to record, pause, model info, and the main window.

import SwiftUI

struct MenuBarView: View {

    @EnvironmentObject var vm: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                Text("LiveTranscribe")
                    .font(.system(size: 13, weight: .bold))

                Image(systemName: vm.dependencyState.isHealthy ? "shield.checkmark.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.dependencyState.isHealthy ? Color.green : Color.orange)
                    .help(vm.dependencyState.labelText)

                Spacer()
                // Bring main window to front
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open main window")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.08))

            Divider()

            // ── Status ────────────────────────────────────────────────────
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(vm.isCapturing
                              ? (vm.isPaused ? Color.orange : Color.green)
                              : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(vm.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if vm.isCapturing {
                    AudioLevelBar(level: vm.audioLevel)
                        .frame(height: 5)
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── Controls ──────────────────────────────────────────────────
            VStack(spacing: 6) {
                if !vm.isCapturing {
                    menuButton(
                        label: "Start Recording",
                        icon: "record.circle",
                        tint: .red
                    ) {
                        Task { await vm.startTranscription() }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                } else {
                    menuButton(
                        label: vm.isPaused ? "Resume" : "Pause",
                        icon: vm.isPaused ? "play.circle" : "pause.circle",
                        tint: .orange
                    ) {
                        vm.togglePause()
                    }

                    menuButton(
                        label: "Stop Recording",
                        icon: "stop.circle",
                        tint: .red
                    ) {
                        Task { await vm.stopTranscription() }
                    }
                }

                menuButton(
                    label: "Toggle Floating Window",
                    icon: "pip",
                    tint: Color.accentColor
                ) {
                    (NSApp.delegate as? AppDelegate)?.toggleFloatingWindow()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // ── Info ─────────────────────────────────────────────────────
            HStack(spacing: 6) {
                Label(vm.settings.whisperModel.shortName, systemImage: "cpu")
                Spacer()
                if vm.isCapturing {
                    Label("\(vm.liveSegments.count) segs", systemImage: "text.bubble")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private func menuButton(
        label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
