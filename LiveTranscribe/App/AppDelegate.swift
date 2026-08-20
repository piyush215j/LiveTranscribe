// AppDelegate.swift
// LiveTranscribe
//
// NSApplicationDelegate that manages:
//  - Menu bar status item with a popover
//  - Always-on-top floating transcript NSPanel
//  - Termination clean-up

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Injected by LiveTranscribeApp after launch
    var transcriptionVM: TranscriptionViewModel?
    var historyVM:       SessionHistoryViewModel?

    // MARK: - Menu bar

    private var statusItem:  NSStatusItem?
    private var statusPopover = NSPopover()

    // MARK: - Floating window

    private var floatingPanel: NSPanel?
    private var floatingHosting: NSHostingView<AnyView>?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        setupFloatingPanel()
        // Keep the app alive even when all windows are closed
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Stay alive in the menu bar / floating window mode
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure capture is stopped cleanly
        if let vm = transcriptionVM, vm.isCapturing {
            Task { await vm.stopTranscription() }
        }
    }

    // MARK: - Menu bar setup

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "LiveTranscribe"
            )
            button.action = #selector(toggleMenuBarPopover)
            button.target = self
        }

        statusPopover.contentSize   = NSSize(width: 320, height: 240)
        statusPopover.behavior      = .transient
        statusPopover.animates      = true
    }

    @objc private func toggleMenuBarPopover() {
        guard let button = statusItem?.button else { return }

        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            // Build content on-demand so we get the latest VM reference
            if let vm = transcriptionVM, let hvm = historyVM {
                let view = MenuBarView()
                    .environmentObject(vm)
                    .environmentObject(hvm)
                statusPopover.contentViewController =
                    NSHostingController(rootView: view)
            }
            statusPopover.show(relativeTo: button.bounds,
                               of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Floating panel

    private func setupFloatingPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 180),
            styleMask:   [.titled, .closable, .resizable,
                          .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing:     .buffered,
            defer:       false
        )
        panel.title             = "Live Transcript"
        panel.level             = .floating
        panel.isFloatingPanel   = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent  = true
        panel.backgroundColor   = .clear

        floatingPanel = panel
    }

    @MainActor
    func showFloatingWindow() {
        guard let panel = floatingPanel, let vm = transcriptionVM else { return }

        if floatingHosting == nil {
            let rootView = AnyView(
                FloatingTranscriptView()
                    .environmentObject(vm)
            )
            let hosting = NSHostingView(rootView: rootView)
            panel.contentView = hosting
            floatingHosting   = hosting
        }

        if !panel.isVisible {
            panel.center()
        }
        panel.orderFront(nil)
        vm.showFloatingWindow = true
    }

    @MainActor
    func hideFloatingWindow() {
        floatingPanel?.orderOut(nil)
        transcriptionVM?.showFloatingWindow = false
    }

    @MainActor
    func toggleFloatingWindow() {
        if floatingPanel?.isVisible == true {
            hideFloatingWindow()
        } else {
            showFloatingWindow()
        }
    }
}
