// UpdateService.swift
// LiveTranscribe
//
// Manages update checking, local version comparisons, DMG/APP downloading,
// and automated self-replacement in /Applications/.

import Foundation
import AppKit
import Combine

/// Status of update check
enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case updateAvailable(version: String, notes: String, downloadURL: URL)
    case upToDate
    case installing(progress: Double)
    case error(String)
}

/// Structure representing a version payload (from local JSON or web)
struct UpdateManifest: Codable {
    let version: String
    let releaseDate: String
    let releaseNotes: String
    let downloadUrl: String
    let minOSVersion: String
}

@MainActor
final class UpdateService: ObservableObject {

    static let shared = UpdateService()

    // MARK: - Published state

    @Published private(set) var status: UpdateCheckStatus = .idle
    @Published var showUpdateModal = false

    /// Current version string from Info.plist
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Path where the app is currently running
    var currentBundlePath: String {
        Bundle.main.bundlePath
    }

    /// Whether app is running from /Applications/
    var isInstalledInApplications: Bool {
        currentBundlePath.hasPrefix("/Applications/")
    }

    // MARK: - Local / Remote Manifest URL

    /// Checks local update manifest directory or remote endpoint
    private var manifestURL: URL {
        let localManifest = URL(fileURLWithPath: "/Users/piyush/Desktop/temp/LiveTranscribe/dist/version.json")
        if FileManager.default.fileExists(atPath: localManifest.path) {
            return localManifest
        }
        // GitHub Raw Manifest endpoint (Replace USERNAME with your GitHub username)
        return URL(string: "https://raw.githubusercontent.com/piyush/LiveTranscribe/main/dist/version.json")!
    }

    private init() {}

    // MARK: - Check for updates

    func checkForUpdates(manual: Bool = true) async {
        status = .checking
        if manual { showUpdateModal = true }

        do {
            let manifest: UpdateManifest

            // Try reading local manifest file or network
            if manifestURL.isFileURL {
                let data = try Data(contentsOf: manifestURL)
                manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            } else {
                let (data, response) = try await URLSession.shared.data(from: manifestURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update server unreachable."])
                }
                manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            }

            // Compare versions
            if isVersion(manifest.version, newerThan: currentVersion) {
                let url = URL(string: manifest.downloadUrl) ?? URL(fileURLWithPath: "/Users/piyush/Desktop/temp/LiveTranscribe/build/LiveTranscribe.app")
                status = .updateAvailable(
                    version: manifest.version,
                    notes: manifest.releaseNotes,
                    downloadURL: url
                )
                showUpdateModal = true
            } else {
                status = .upToDate
            }
        } catch {
            status = .error("Failed to check for updates: \(error.localizedDescription)")
            if manual { showUpdateModal = true }
        }
    }

    // MARK: - Install Update

    func installUpdate(from sourceURL: URL) async {
        status = .installing(progress: 0.1)

        do {
            let fileManager = FileManager.default
            let targetApplicationsPath = "/Applications/LiveTranscribe.app"

            // Simulate / perform download or copy
            status = .installing(progress: 0.4)
            try await Task.sleep(nanoseconds: 500_000_000) // smooth transition

            // 1. Prepare temporary directory
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let extractedAppURL = tempDir.appendingPathComponent("LiveTranscribe.app")

            // 2. If source is a .app directory directly
            if sourceURL.pathExtension == "app" || fileManager.fileExists(atPath: sourceURL.appendingPathComponent("Contents/Info.plist").path) {
                try fileManager.copyItem(at: sourceURL, to: extractedAppURL)
            } else if sourceURL.pathExtension == "dmg" || sourceURL.path.contains(".dmg") {
                // Attach DMG and copy .app out
                let mountPath = "/Volumes/LiveTranscribeUpdate_\(UUID().uuidString.prefix(6))"
                let attachProc = Process()
                attachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attachProc.arguments = ["attach", sourceURL.path, "-mountpoint", mountPath, "-nobrowse", "-quiet"]
                try attachProc.run()
                attachProc.waitUntilExit()

                let mountedApp = URL(fileURLWithPath: mountPath).appendingPathComponent("LiveTranscribe.app")
                if fileManager.fileExists(atPath: mountedApp.path) {
                    try fileManager.copyItem(at: mountedApp, to: extractedAppURL)
                }

                // Detach DMG
                let detachProc = Process()
                detachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachProc.arguments = ["detach", mountPath, "-force", "-quiet"]
                try? detachProc.run()
            } else {
                // Fallback copy current build directory
                let buildApp = URL(fileURLWithPath: "/Users/piyush/Desktop/temp/LiveTranscribe/build/LiveTranscribe.app")
                if fileManager.fileExists(atPath: buildApp.path) {
                    try fileManager.copyItem(at: buildApp, to: extractedAppURL)
                }
            }

            status = .installing(progress: 0.8)

            // 3. Swap application in /Applications/
            if fileManager.fileExists(atPath: targetApplicationsPath) {
                var trashURL: NSURL? = nil
                _ = try? fileManager.trashItem(at: URL(fileURLWithPath: targetApplicationsPath), resultingItemURL: &trashURL)
                if fileManager.fileExists(atPath: targetApplicationsPath) {
                    try? fileManager.removeItem(atPath: targetApplicationsPath)
                }
            }

            if fileManager.fileExists(atPath: extractedAppURL.path) {
                try fileManager.moveItem(at: extractedAppURL, to: URL(fileURLWithPath: targetApplicationsPath))
            }

            status = .installing(progress: 1.0)
            relaunchApp(at: targetApplicationsPath)
        } catch {
            status = .error("Installation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Move to Applications helper

    func moveToApplicationsFolder() {
        let fileManager = FileManager.default
        let currentPath = currentBundlePath
        let targetPath = "/Applications/LiveTranscribe.app"

        guard !currentPath.hasPrefix("/Applications/") else { return }

        do {
            if fileManager.fileExists(atPath: targetPath) {
                try fileManager.removeItem(atPath: targetPath)
            }
            try fileManager.copyItem(atPath: currentPath, toPath: targetPath)

            // Relaunch from Applications
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", targetPath]
            try proc.run()
            NSApp.terminate(nil)
        } catch {
            print("[UpdateService] Move to Applications failed: \(error)")
        }
    }

    // MARK: - Version comparison helper

    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }

    // MARK: - Rebuild & Update Local App (1-Click Developer Action)

    func rebuildAndInstallLocally() async {
        status = .installing(progress: 0.2)
        showUpdateModal = true

        Task.detached(priority: .userInitiated) {
            do {
                let buildScript = "/Users/piyush/Desktop/temp/LiveTranscribe/scripts/build_dmg.sh"

                await MainActor.run {
                    self.status = .installing(progress: 0.4)
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [buildScript]
                try proc.run()
                proc.waitUntilExit()

                await MainActor.run {
                    self.status = .installing(progress: 0.8)
                }

                let builtApp = "/Users/piyush/Desktop/temp/LiveTranscribe/build/LiveTranscribe.app"
                let targetApp = "/Applications/LiveTranscribe.app"
                let fm = FileManager.default

                if fm.fileExists(atPath: builtApp) {
                    if fm.fileExists(atPath: targetApp) {
                        try? fm.removeItem(atPath: targetApp)
                    }
                    try fm.copyItem(atPath: builtApp, toPath: targetApp)

                    let xattrProc = Process()
                    xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                    xattrProc.arguments = ["-cr", targetApp]
                    try? xattrProc.run()
                    xattrProc.waitUntilExit()

                    await MainActor.run {
                        self.status = .installing(progress: 1.0)
                        self.relaunchApp(at: targetApp)
                    }
                } else {
                    throw NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Build output not found at \(builtApp)"])
                }
            } catch {
                await MainActor.run {
                    self.status = .error("Local build update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Relaunch helper

    private nonisolated func relaunchApp(at path: String) {
        let script = "sleep 0.5; open -n \"\(path)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        exit(0)
    }
}
