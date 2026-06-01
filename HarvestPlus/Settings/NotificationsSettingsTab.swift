//
//  NotificationsSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Notifications settings: toggles and thresholds for the nudge, idle,
//  long-timer, and end-of-day / end-of-week summary banners, plus the
//  banner's screen position.
//

import SwiftUI

// MARK: - Notifications Settings Tab

struct NotificationsSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var timerNudge: Bool = true
    @State private var bannerPosition: BannerPosition = .top
    @State private var snoozeDuration: Double = 15  // minutes
    @State private var idleDetection: Bool = true
    @State private var idleThreshold: Double = 15  // minutes
    @State private var longTimerWarning: Bool = true
    @State private var longTimerThreshold: Double = 3  // hours
    @State private var eodSummary: Bool = true
    @State private var eodTime: Date = Calendar.current.date(from: DateComponents(hour: 16, minute: 0)) ?? Date()
    @State private var eowSummary: Bool = true
    @State private var eowTime: Date = Calendar.current.date(from: DateComponents(hour: 16, minute: 0)) ?? Date()
    @State private var autoStopOnSleep: Bool = false

    private let snoozeOptions: [Double] = [5, 10, 15, 30]
    private let idleOptions: [Double] = [5, 10, 15, 30, 60]
    private let longTimerOptions: [Double] = [1, 2, 3, 4, 5]

    var body: some View {
        Form {
            Section("Timer Nudge Banner") {
                Toggle("Show banner when no timer is running", isOn: $timerNudge)

                Picker("Banner Position", selection: $bannerPosition) {
                    ForEach(BannerPosition.allCases, id: \.self) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }

                Picker("Snooze Duration", selection: $snoozeDuration) {
                    ForEach(snoozeOptions, id: \.self) { m in
                        Text("\(Int(m)) min").tag(m)
                    }
                }
            }

            Section("Idle Detection") {
                Toggle("Detect when idle with timer running", isOn: $idleDetection)

                Picker("Idle Threshold", selection: $idleThreshold) {
                    ForEach(idleOptions, id: \.self) { m in
                        Text("\(Int(m)) min").tag(m)
                    }
                }
                .disabled(!idleDetection)

                Text("Prompts you if no mouse/keyboard activity while a timer is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Long Timer Warning") {
                Toggle("Warn when timer runs too long", isOn: $longTimerWarning)

                Picker("Threshold", selection: $longTimerThreshold) {
                    ForEach(longTimerOptions, id: \.self) { h in
                        Text("\(Int(h))h").tag(h)
                    }
                }
                .disabled(!longTimerWarning)

                Text("Shows a reminder if you might have forgotten to switch tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("End-of-Day Summary") {
                Toggle("Show daily summary", isOn: $eodSummary)

                DatePicker("Time", selection: $eodTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .disabled(!eodSummary)
            }

            Section("End-of-Week Summary") {
                Toggle("Show weekly summary on Friday", isOn: $eowSummary)

                DatePicker("Time", selection: $eowTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .disabled(!eowSummary)
            }

            Section("Automation") {
                Toggle("Auto-stop timer on sleep", isOn: $autoStopOnSleep)
                Text("Stops the running timer when your Mac goes to sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
        .onChange(of: timerNudge) { _, _ in saveSettings() }
        .onChange(of: bannerPosition) { _, _ in saveSettings() }
        .onChange(of: snoozeDuration) { _, _ in saveSettings() }
        .onChange(of: idleDetection) { _, _ in saveSettings() }
        .onChange(of: idleThreshold) { _, _ in saveSettings() }
        .onChange(of: longTimerWarning) { _, _ in saveSettings() }
        .onChange(of: longTimerThreshold) { _, _ in saveSettings() }
        .onChange(of: eodSummary) { _, _ in saveSettings() }
        .onChange(of: eodTime) { _, _ in saveSettings() }
        .onChange(of: eowSummary) { _, _ in saveSettings() }
        .onChange(of: eowTime) { _, _ in saveSettings() }
        .onChange(of: autoStopOnSleep) { _, _ in saveSettings() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let ud = UserDefaults.standard
        let cal = Calendar.current

        timerNudge = ud.object(forKey: "timerNudge") as? Bool ?? true
        bannerPosition = BannerPosition(rawValue: ud.string(forKey: "bannerPosition") ?? "Top") ?? .top
        snoozeDuration = ud.object(forKey: "snoozeDuration") as? Double ?? 15
        idleDetection = ud.object(forKey: "idleDetection") as? Bool ?? true
        idleThreshold = ud.object(forKey: "idleThreshold") as? Double ?? 15
        longTimerWarning = ud.object(forKey: "longTimerWarning") as? Bool ?? true
        longTimerThreshold = ud.object(forKey: "longTimerThreshold") as? Double ?? 3
        eodSummary = ud.object(forKey: "eodSummary") as? Bool ?? true
        eowSummary = ud.object(forKey: "eowSummary") as? Bool ?? true
        autoStopOnSleep = ud.bool(forKey: "autoStopOnSleep")

        let eodH = ud.object(forKey: "eodHour") as? Int ?? 16
        let eodM = ud.object(forKey: "eodMinute") as? Int ?? 0
        eodTime = cal.date(from: DateComponents(hour: eodH, minute: eodM)) ?? eodTime

        let eowH = ud.object(forKey: "eowHour") as? Int ?? 16
        let eowM = ud.object(forKey: "eowMinute") as? Int ?? 0
        eowTime = cal.date(from: DateComponents(hour: eowH, minute: eowM)) ?? eowTime
    }

    private func saveSettings() {
        let ud = UserDefaults.standard
        let cal = Calendar.current

        ud.set(timerNudge, forKey: "timerNudge")
        ud.set(bannerPosition.rawValue, forKey: "bannerPosition")
        ud.set(snoozeDuration, forKey: "snoozeDuration")
        ud.set(idleDetection, forKey: "idleDetection")
        ud.set(idleThreshold, forKey: "idleThreshold")
        ud.set(longTimerWarning, forKey: "longTimerWarning")
        ud.set(longTimerThreshold, forKey: "longTimerThreshold")
        ud.set(eodSummary, forKey: "eodSummary")
        ud.set(eowSummary, forKey: "eowSummary")
        ud.set(autoStopOnSleep, forKey: "autoStopOnSleep")

        let eodComps = cal.dateComponents([.hour, .minute], from: eodTime)
        ud.set(eodComps.hour ?? 16, forKey: "eodHour")
        ud.set(eodComps.minute ?? 0, forKey: "eodMinute")

        let eowComps = cal.dateComponents([.hour, .minute], from: eowTime)
        ud.set(eowComps.hour ?? 16, forKey: "eowHour")
        ud.set(eowComps.minute ?? 0, forKey: "eowMinute")

        // Update AppState
        appState.settings.timerNudgeEnabled = timerNudge
        appState.settings.bannerPosition = bannerPosition
        appState.settings.snoozeDuration = snoozeDuration * 60
        appState.settings.idleDetectionEnabled = idleDetection
        appState.settings.idleThreshold = idleThreshold * 60
        appState.settings.longTimerWarningEnabled = longTimerWarning
        appState.settings.longTimerThreshold = longTimerThreshold * 3600
        appState.settings.eodSummaryEnabled = eodSummary
        appState.settings.eodSummaryTime = eodComps
        appState.settings.eowSummaryEnabled = eowSummary
        appState.settings.eowSummaryTime = eowComps
        appState.settings.autoStopOnSleep = autoStopOnSleep
    }
}
