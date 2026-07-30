// OnboardingView.swift
// LiveTranscribe
//
// First-run guide shown when screen recording permission is missing,
// or when no Python/faster-whisper installation is found.

import SwiftUI
import ScreenCaptureKit

struct OnboardingView: View {

    @Environment(\.dismiss) var dismiss
    @State private var step = 0
    @State private var pythonCheckResult: String = "Checking…"
    @State private var permissionCheckResult: String = "Checking…"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Setup Guide", systemImage: "wand.and.sparkles")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            Divider()

            // Steps
            ScrollView {
                VStack(spacing: 20) {
                    stepCard(
                        number: 1,
                        icon: "hand.raised.fill",
                        title: "Screen Recording Permission",
                        description: "LiveTranscribe needs Screen Recording access to capture system audio. No video is ever captured.",
                        action: {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                            )
                        },
                        actionLabel: "Open System Settings",
                        statusText: permissionCheckResult,
                        statusOK: permissionCheckResult == "✅ Granted",
                        showRelaunchButton: permissionCheckResult.hasPrefix("⚠️")
                    )

                    stepCard(
                        number: 2,
                        icon: "terminal.fill",
                        title: "Install Python 3",
                        description: "Python 3.8 or later is required to run faster-whisper. Install via Homebrew (recommended).",
                        action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install python3", forType: .string)
                        },
                        actionLabel: "Copy install command",
                        statusText: pythonCheckResult,
                        statusOK: pythonCheckResult.hasPrefix("✅"),
                        showRelaunchButton: false
                    )

                    stepCard(
                        number: 3,
                        icon: "brain",
                        title: "Install faster-whisper",
                        description: "Run this command in Terminal to install the transcription engine and its dependencies.",
                        action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                "pip3 install faster-whisper", forType: .string)
                        },
                        actionLabel: "Copy pip command",
                        statusText: nil,
                        statusOK: nil,
                        showRelaunchButton: false
                    )

                    stepCard(
                        number: 4,
                        icon: "play.circle.fill",
                        title: "Start Recording",
                        description: "Press ⇧⌘R or click the red record button in the toolbar. The Whisper model will download automatically on first use.",
                        action: nil,
                        actionLabel: nil,
                        statusText: nil,
                        statusOK: nil,
                        showRelaunchButton: false
                    )

                    // Optional: BlackHole note
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Alternative: BlackHole virtual audio device", systemImage: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("If ScreenCaptureKit doesn't capture the audio you need, install BlackHole (a free virtual audio device) and route your audio through it. LiveTranscribe automatically detects BlackHole.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Download BlackHole", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole")!)
                            .font(.caption)
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(10)
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Recheck Status") {
                    Task { await recheck() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .onAppear {
            Task { await recheck() }
        }
    }

    // MARK: - Recheck

    private func recheck() async {
        permissionCheckResult = "Checking…"

        // Use the same authoritative check as AudioCaptureService:
        // SCShareableContent.excludingDesktopWindows is what SCStream actually needs.
        // CGPreflightScreenCaptureAccess() returns false for ad-hoc signed apps even
        // when the toggle IS on — so we never rely on it for the status display.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            permissionCheckResult = "✅ Granted"
        } catch {
            // Permission is toggled ON but the process needs a relaunch to pick it up
            // (macOS TCC only propagates to already-running processes after restart).
            let toggleIsOn = CGPreflightScreenCaptureAccess()
            if toggleIsOn {
                permissionCheckResult = "⚠️ Enabled — please Quit & Relaunch LiveTranscribe to activate."
            } else {
                permissionCheckResult = "❌ Not granted — enable the toggle in System Settings, then Quit & Relaunch."
            }
        }

        // Check Python (include venv)
        let venvPy = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LiveTranscribe/venv/bin/python3").path

        var pythonPaths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        if let venv = venvPy { pythonPaths.insert(venv, at: 0) }

        if let found = pythonPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            pythonCheckResult = "✅ Found at \(found.contains("venv") ? "Application Support venv" : found)"
        } else {
            pythonCheckResult = "❌ Not found — install via Homebrew"
        }
    }

    // MARK: - Step card

    private func stepCard(
        number: Int,
        icon: String,
        title: String,
        description: String,
        action: (() -> Void)?,
        actionLabel: String?,
        statusText: String?,
        statusOK: Bool?,
        showRelaunchButton: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Number badge
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = action, let label = actionLabel {
                    Button(label, action: action)
                        .font(.system(size: 12))
                        .buttonStyle(.bordered)
                }

                if let status = statusText {
                    let isWarning = status.hasPrefix("⚠️")
                    let isOK = statusOK == true
                    HStack(spacing: 4) {
                        Image(systemName: isOK
                              ? "checkmark.circle.fill"
                              : (isWarning ? "exclamationmark.circle.fill"
                              : (statusOK == false ? "xmark.circle.fill" : "circle")))
                            .foregroundStyle(isOK ? .green : (isWarning ? .orange : (statusOK == false ? .red : .gray)))
                        Text(status)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // "Quit & Relaunch" button shown when toggle is on but SCKit still denied
                if showRelaunchButton {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit & Relaunch", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}


