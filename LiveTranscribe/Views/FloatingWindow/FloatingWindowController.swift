// FloatingWindowController.swift
// LiveTranscribe
//
// Manages the always-on-top NSPanel that hosts FloatingTranscriptView.
// This controller is kept in AppDelegate and accessed via static methods.

import AppKit
import SwiftUI

/// Manages the floating, always-on-top transcript NSPanel.
final class FloatingWindowController: NSObject {

    // MARK: - Private state

    private var panel: NSPanel?
    private weak var transcriptionVM: TranscriptionViewModel?

    // MARK: - Init

    init(transcriptionVM: TranscriptionViewModel) {
        self.transcriptionVM = transcriptionVM
        super.init()
    }

    // MARK: - Panel creation

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .nonactivatingPanel,
                .utilityWindow,
            ],
            backing: .buffered,
            defer: false
        )
        p.title              = "Live Transcript"
        p.level              = .floating
        p.isFloatingPanel    = true
        p.hidesOnDeactivate  = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.titlebarAppearsTransparent  = true
        p.backgroundColor    = NSColor.black.withAlphaComponent(0.01)
        p.isOpaque           = false
        p.hasShadow          = true
        p.minSize            = NSSize(width: 380, height: 100)
        return p
    }

    // MARK: - Show / Hide / Toggle

    func show() {
        guard let vm = transcriptionVM else { return }

        if panel == nil {
            let newPanel = makePanel()
            let rootView = FloatingTranscriptView().environmentObject(vm)
            newPanel.contentView = NSHostingView(rootView: rootView)
            panel = newPanel
        }

        if !(panel?.isVisible ?? false) { panel?.center() }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}
