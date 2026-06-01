//
//  HarvestPlusApp.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  App entry point (`@main`). Declares the menu-bar extra, the Dashboard and
//  Log-Meeting windows, and the Settings scene, and injects the shared
//  `AppState` into each.
//

import SwiftUI

@main
struct HarvestPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView(state: appState.timerState)
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
        }
        .defaultSize(width: 680, height: 720)
        .windowResizability(.contentMinSize)

        Window("Log Meeting", id: "meeting-entry") {
            MeetingEntryWindow()
                .environmentObject(appState)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

