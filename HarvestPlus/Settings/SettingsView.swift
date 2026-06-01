//
//  SettingsView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The Settings window shell: a TabView hosting the General, Schedule,
//  Notifications, Integrations, Holidays, Export, and Feedback tabs.
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ScheduleSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Schedule", systemImage: "clock")
                }

            NotificationsSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            IntegrationsSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }

            HolidaysSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Holidays", systemImage: "calendar")
                }

            ExportSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

            FeedbackSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Feedback", systemImage: "bubble.left.and.bubble.right")
                }
        }
        .frame(width: 550, height: 500)
    }
}
