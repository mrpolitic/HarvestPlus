//
//  GeneralSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  General settings: launch at login, the Harvest polling interval, and the
//  Liquid Glass appearance toggle.
//

import SwiftUI
import ServiceManagement

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var launchAtLogin: Bool = false
    @State private var pollingInterval: Double = 60

    // Liquid Glass on by default – it's the platform's native material on
    // macOS 26 and what every other Apple app opts into. The toggle exists
    // for users on lower-end hardware or those who simply prefer the flat
    // look; it's read by `HarvestSurfaceModifier` via @AppStorage so every
    // surface in the app updates instantly when flipped.
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled: Bool = true

    // 15s is the practical floor: fast enough that HarvestPlus feels live when
    // you start/stop a timer elsewhere, but doesn't hammer the Harvest API or
    // your battery. 10s is offered for power users; going lower buys nothing
    // because the running-timer state rarely changes on human timescales.
    // 5 minutes was dropped – anything slower than 2 minutes feels broken.
    private let pollingOptions: [Double] = [10, 15, 30, 60, 120]

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                        appState.settings.launchAtLogin = newValue
                        UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
                    }

                Text("Automatically start HarvestPlus when you log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Polling Interval", selection: $pollingInterval) {
                    ForEach(pollingOptions, id: \.self) { interval in
                        Text(formatInterval(interval)).tag(interval)
                    }
                }
                .onChange(of: pollingInterval) { _, newValue in
                    appState.settings.pollingInterval = newValue
                    UserDefaults.standard.set(newValue, forKey: "pollingInterval")
                    appState.timerMonitor?.restartPolling(interval: newValue)
                }

                Text("How often to check Harvest for timer updates. 15–30s is the sweet spot – faster feels live when you start a timer in Harvest itself, slower saves battery on the go.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Liquid Glass", isOn: $liquidGlassEnabled)

                Text("Apple's translucent material. Gives cards, the banner, and the popover a reflective, frosted look. Turn off for a flat, opaque appearance – slightly lighter on the GPU and a bit easier to read on older displays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                UpdateSection(checker: appState.updateChecker)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
            let stored = UserDefaults.standard.double(forKey: "pollingInterval")
            // Migrate any value no longer in the picker (e.g. legacy 300s) to
            // the default so the Picker always has a matching selection.
            pollingInterval = pollingOptions.contains(stored) ? stored : 60
        }
    }

    private func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds / 60)) min"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail – not critical
        }
    }
}
