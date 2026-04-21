//
//  MenuBarIconView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import SwiftUI
import AppKit

// MARK: - Menu Bar Icon

struct MenuBarIconView: View {
    let state: TimerState

    var body: some View {
        Image(nsImage: compositeIcon())
    }

    // MARK: - Icon Compositing

    /// Two visual states:
    ///
    ///   • Running — fully filled in harvestOrange. A glance at the menu bar
    ///     tells you "a timer is on right now" without parsing a tiny dot.
    ///   • Stopped / Offline — standard template icon. macOS tints it to match
    ///     the menu bar foreground, so it sits quietly like any system glyph.
    ///
    /// The old "stopped during work hours" nudge dot is gone — that nudge
    /// already lives in the banner, and a second indicator in the menu bar
    /// was redundant.
    private func compositeIcon() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let imageRect = NSRect(x: 2, y: 2, width: 18, height: 18)

        switch state {
        case .running:
            // Fully tinted; non-template so macOS preserves the orange.
            let image = NSImage(size: size, flipped: false) { _ in
                guard let baseImage = NSImage(named: "MenuBarIcon") else { return true }
                baseImage.draw(in: imageRect)
                (NSColor(named: "harvestOrange") ?? .systemOrange).set()
                imageRect.fill(using: .sourceAtop)
                return true
            }
            image.isTemplate = false
            return image

        case .stopped, .offline:
            // Template — macOS handles the menu bar tint for us.
            let image = NSImage(size: size, flipped: false) { _ in
                NSImage(named: "MenuBarIcon")?.draw(in: imageRect)
                return true
            }
            image.isTemplate = true
            return image
        }
    }
}

// MARK: - Custom Colors

enum AppColor {
    static let harvestOrange = Color("harvestOrange")
    static let harvestGreen = Color("harvestGreen")
    static let harvestRed = Color("harvestRed")
    static let harvestDark = Color("harvestDark")
    static let bannerBackground = Color("bannerBackground")
    static let timelineGap = Color("timelineGap")
    static let lunchBreak = Color("lunchBreak")
    static let meetingBlue = Color(red: 0.20, green: 0.47, blue: 0.85)
}
