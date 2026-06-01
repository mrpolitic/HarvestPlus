//
//  UpdateChecker.swift
//  HarvestPlus
//
//  Thin wrapper around Sparkle's SPUStandardUpdaterController. The Settings
//  UI and AppState only need: version strings, a "check for updates" action,
//  and a boolean to disable the button while a check is in flight.
//
//  Why Sparkle?
//  ------------
//  Sparkle 2 supports sandboxed apps via an XPC service bundled inside
//  Sparkle.framework. The XPC service runs out-of-process and performs the
//  bundle replacement that a sandboxed app can't do itself. No Apple Events,
//  no Terminal, no consent dialog. Updates are silently downloaded in the
//  background and installed on the next app quit.
//
//  Configuration lives in Info.plist:
//    SUFeedURL                          appcast.xml URL
//    SUPublicEDKey                      public half of the EdDSA keypair
//                                       (private key in the maintainer's keychain)
//    SUEnableInstallerLauncherService   YES – required in sandbox mode
//    SUEnableAutomaticChecks            YES
//    SUScheduledCheckInterval           86400 (1 day)
//    SUAutomaticallyUpdate              YES – download + install silently
//
//  `build.sh` signs each release zip with the private EdDSA key on the
//  release machine and updates the appcast.xml entry. Sparkle on the
//  client verifies the signature with the bundled public key before
//  letting the XPC installer touch anything.
//

import Foundation
import Combine
import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {

    /// Owns Sparkle's `SPUUpdater` and standard user driver. Initialised
    /// eagerly with `startingUpdater: true`, so the background scheduler
    /// is running before the user opens Settings for the first time.
    private let controller: SPUStandardUpdaterController

    /// Mirror of `SPUUpdater.canCheckForUpdates` for SwiftUI binding –
    /// flips to `false` while a check or download is in flight.
    @Published private(set) var canCheckForUpdates: Bool = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // KVO-observable on Sparkle's side; bridge into Combine for SwiftUI.
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger a manual update check. Sparkle shows its standard UI
    /// (modal with release notes + Install button) if an update is found.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
