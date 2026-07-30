// UpdateView.swift
// LiveTranscribe
//
// Update modal dialog showing version details, release notes, progress, and Install button.

import SwiftUI

struct UpdateView: View {

    @EnvironmentObject var updateService: UpdateService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 10)

            switch updateService.status {
            case .checking:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking for updates…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

            case .upToDate:
                VStack(spacing: 8) {
                    Text("You're Up to Date!")
                        .font(.system(size: 18, weight: .bold))
                    Text("LiveTranscribe v\(updateService.currentVersion) is currently the latest version.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("OK") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                }

            case .updateAvailable(let version, let notes, let downloadURL):
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("Update Available! (v\(version))")
                            .font(.system(size: 18, weight: .bold))
                        Text("A new version of LiveTranscribe is ready to install.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Release notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Release Notes:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(notes)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                        .frame(height: 110)
                    }

                    HStack(spacing: 12) {
                        Button("Later") { dismiss() }
                            .buttonStyle(.bordered)

                        Button("Install & Relaunch") {
                            Task {
                                await updateService.installUpdate(from: downloadURL)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .installing(let progress):
                VStack(spacing: 12) {
                    Text("Installing Update…")
                        .font(.system(size: 15, weight: .bold))
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text("LiveTranscribe will automatically restart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                }

            case .idle:
                EmptyView()
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
