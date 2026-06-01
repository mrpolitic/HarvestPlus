//
//  AppDelegate.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  NSApplicationDelegate. Bridges AppKit system notifications (sleep/wake,
//  screen lock/unlock) into the in-app Notification.Name events that
//  SystemEventHandler listens for, and handles the `harvestplus://` URL scheme.
//

import AppKit
import SwiftUI

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for system events
        registerSystemEventObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup on quit
        removeSystemEventObservers()
    }

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "harvestplus" else { continue }
            handleOAuthCallback(url: url)
        }
    }

    private func handleOAuthCallback(url: URL) {
        // Parse OAuth callback – implemented in Session 4 (Outlook integration)
        // Expected format: harvestplus://auth/microsoft?code=xxx&state=yyy
        NotificationCenter.default.post(
            name: .oauthCallback,
            object: nil,
            userInfo: ["url": url]
        )
    }

    // MARK: - System Event Observers

    private func registerSystemEventObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        workspace.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        workspace.addObserver(
            self,
            selector: #selector(handleScreenLock),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        workspace.addObserver(
            self,
            selector: #selector(handleScreenUnlock),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    private func removeSystemEventObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleSleep() {
        NotificationCenter.default.post(name: .systemWillSleep, object: nil)
    }

    @objc private func handleWake() {
        NotificationCenter.default.post(name: .systemDidWake, object: nil)
    }

    @objc private func handleScreenLock() {
        NotificationCenter.default.post(name: .screenDidLock, object: nil)
    }

    @objc private func handleScreenUnlock() {
        NotificationCenter.default.post(name: .screenDidUnlock, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let oauthCallback = Notification.Name("HarvestPlus.oauthCallback")
    static let systemWillSleep = Notification.Name("HarvestPlus.systemWillSleep")
    static let systemDidWake = Notification.Name("HarvestPlus.systemDidWake")
    static let screenDidLock = Notification.Name("HarvestPlus.screenDidLock")
    static let screenDidUnlock = Notification.Name("HarvestPlus.screenDidUnlock")
}
