//
//  BannerPanel.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The borderless, non-activating floating NSPanel that hosts the banner's
//  SwiftUI content above all other windows without stealing focus.
//

import AppKit

// MARK: - Banner Panel

class BannerPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Positioning

    /// Position the banner centered horizontally, just below the menu bar.
    func positionBelowMenuBar() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Menu bar height = screen height - visible height - visible origin Y
        let menuBarBottom = visibleFrame.maxY

        let panelWidth = self.frame.width
        let x = screenFrame.midX - (panelWidth / 2)
        let y = menuBarBottom - self.frame.height - 8  // 8pt below menu bar

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Position the banner centered horizontally, above the Dock.
    func positionAboveDock() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let panelWidth = self.frame.width
        let x = visibleFrame.midX - (panelWidth / 2)
        let y = visibleFrame.origin.y + 24  // 24pt above dock

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
