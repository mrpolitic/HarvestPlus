//
//  MenuBarIconView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The menu-bar status item icon. Renders the hourglass+plus glyph filled in
//  harvestOrange while a timer is running, and as a tintable template image
//  (matching the menu-bar foreground) when stopped or offline.
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
    ///   • Running – fully filled in harvestOrange. A glance at the menu bar
    ///     tells you "a timer is on right now" without parsing a tiny dot.
    ///   • Stopped / Offline – standard template icon. macOS tints it to match
    ///     the menu bar foreground, so it sits quietly like any system glyph.
    ///
    /// The old "stopped during work hours" nudge dot is gone – that nudge
    /// already lives in the banner, and a second indicator in the menu bar
    /// was redundant.
    private func compositeIcon() -> NSImage {
        // Glyph is fit to the standard ~18pt menu-bar height; its width
        // follows the source aspect ratio rather than being forced square.
        // The hourglass+plus mark is wider than it is tall (≈4:3), so a
        // fixed square rect would squish it. Reading the aspect from the
        // base image keeps this correct for whatever shape is in the
        // MenuBarIcon imageset. 2pt of breathing room around the glyph.
        // 15pt tall (not the full ~18pt menu-bar height) so the mark has a
        // little breathing room – 18pt filled the bar edge-to-edge and read
        // as too large next to system glyphs. Centered in a 22pt canvas with
        // matching horizontal padding so the margin is even on all sides.
        let glyphHeight: CGFloat = 15
        let baseImage = NSImage(named: "MenuBarIcon")
        let aspect = (baseImage?.size.width ?? 1) / max(baseImage?.size.height ?? 1, 1)
        let glyphWidth = (glyphHeight * aspect).rounded()
        let canvasHeight: CGFloat = 22
        let hPad: CGFloat = 3
        let canvasSize = NSSize(width: glyphWidth + hPad * 2, height: canvasHeight)
        let yOffset = ((canvasHeight - glyphHeight) / 2).rounded()
        let imageRect = NSRect(x: hPad, y: yOffset, width: glyphWidth, height: glyphHeight)

        switch state {
        case .running:
            // Fully tinted; non-template so macOS preserves the orange.
            let image = NSImage(size: canvasSize, flipped: false) { _ in
                guard let baseImage = NSImage(named: "MenuBarIcon") else { return true }
                baseImage.draw(in: imageRect)
                (NSColor(named: "harvestOrange") ?? .systemOrange).set()
                imageRect.fill(using: .sourceAtop)
                return true
            }
            image.isTemplate = false
            return image

        case .stopped, .offline:
            // Template – macOS handles the menu bar tint for us.
            let image = NSImage(size: canvasSize, flipped: false) { _ in
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
