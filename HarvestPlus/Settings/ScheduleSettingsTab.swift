//
//  ScheduleSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Work-schedule settings: start / end times, the per-weekday hour targets,
//  and lunch duration / window.
//

import SwiftUI

// MARK: - Schedule Settings Tab

struct ScheduleSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var workStart: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    @State private var workEnd: Date = Calendar.current.date(from: DateComponents(hour: 16, minute: 0)) ?? Date()
    @State private var targetMon: Double = 7.5
    @State private var targetTue: Double = 7.5
    @State private var targetWed: Double = 7.5
    @State private var targetThu: Double = 7.5
    @State private var targetFri: Double = 7.0
    @State private var targetSat: Double = 0.0
    @State private var targetSun: Double = 0.0

    private let targetOptions = stride(from: 0.0, through: 10.0, by: 0.5).map { $0 }

    var body: some View {
        Form {
            Section("Work Hours") {
                DatePicker("Start Time", selection: $workStart, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .onChange(of: workStart) { _, _ in saveSettings() }

                DatePicker("End Time", selection: $workEnd, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .onChange(of: workEnd) { _, _ in saveSettings() }
            }

            Section("Work Day") {
                dayTargetRow("Monday", target: $targetMon)
                dayTargetRow("Tuesday", target: $targetTue)
                dayTargetRow("Wednesday", target: $targetWed)
                dayTargetRow("Thursday", target: $targetThu)
                dayTargetRow("Friday", target: $targetFri)
                dayTargetRow("Saturday", target: $targetSat)
                dayTargetRow("Sunday", target: $targetSun)

                HStack {
                    Text("Weekly Total")
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1fh", weeklyTotal))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    // MARK: - Day Target Row

    private func dayTargetRow(_ label: String, target: Binding<Double>) -> some View {
        Picker(label, selection: target) {
            ForEach(targetOptions, id: \.self) { t in
                Text(String(format: "%.1fh", t)).tag(t)
            }
        }
        .onChange(of: target.wrappedValue) { _, _ in saveSettings() }
    }

    private var weeklyTotal: Double {
        targetMon + targetTue + targetWed + targetThu + targetFri + targetSat + targetSun
    }

    /// Round a target to the nearest 0.5h and clamp to 0...10 — the range the
    /// picker offers — so the Picker's selection always matches an option tag.
    /// Without this an off-grid stored value (hand-edited default, a future
    /// schedule import) would leave the picker rendering blank.
    private func snapTarget(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 10)
        return (clamped * 2).rounded() / 2
    }

    // MARK: - Persistence

    private func loadSettings() {
        let ud = UserDefaults.standard
        let cal = Calendar.current

        let startH = ud.object(forKey: "workStartHour") as? Int ?? 8
        let startM = ud.object(forKey: "workStartMinute") as? Int ?? 0
        workStart = cal.date(from: DateComponents(hour: startH, minute: startM)) ?? workStart

        let endH = ud.object(forKey: "workEndHour") as? Int ?? 16
        let endM = ud.object(forKey: "workEndMinute") as? Int ?? 0
        workEnd = cal.date(from: DateComponents(hour: endH, minute: endM)) ?? workEnd

        targetMon = snapTarget(ud.object(forKey: "targetMon") as? Double ?? 7.5)
        targetTue = snapTarget(ud.object(forKey: "targetTue") as? Double ?? 7.5)
        targetWed = snapTarget(ud.object(forKey: "targetWed") as? Double ?? 7.5)
        targetThu = snapTarget(ud.object(forKey: "targetThu") as? Double ?? 7.5)
        targetFri = snapTarget(ud.object(forKey: "targetFri") as? Double ?? 7.0)
        targetSat = snapTarget(ud.object(forKey: "targetSat") as? Double ?? 0.0)
        targetSun = snapTarget(ud.object(forKey: "targetSun") as? Double ?? 0.0)
    }

    private func saveSettings() {
        let ud = UserDefaults.standard
        let cal = Calendar.current

        let startComps = cal.dateComponents([.hour, .minute], from: workStart)
        ud.set(startComps.hour ?? 8, forKey: "workStartHour")
        ud.set(startComps.minute ?? 0, forKey: "workStartMinute")

        let endComps = cal.dateComponents([.hour, .minute], from: workEnd)
        ud.set(endComps.hour ?? 16, forKey: "workEndHour")
        ud.set(endComps.minute ?? 0, forKey: "workEndMinute")

        ud.set(targetMon, forKey: "targetMon")
        ud.set(targetTue, forKey: "targetTue")
        ud.set(targetWed, forKey: "targetWed")
        ud.set(targetThu, forKey: "targetThu")
        ud.set(targetFri, forKey: "targetFri")
        ud.set(targetSat, forKey: "targetSat")
        ud.set(targetSun, forKey: "targetSun")

        // Update AppState
        appState.settings.workSchedule.workStartTime = startComps
        appState.settings.workSchedule.workEndTime = endComps
        appState.settings.workSchedule.targetMon = targetMon
        appState.settings.workSchedule.targetTue = targetTue
        appState.settings.workSchedule.targetWed = targetWed
        appState.settings.workSchedule.targetThu = targetThu
        appState.settings.workSchedule.targetFri = targetFri
        appState.settings.workSchedule.targetSat = targetSat
        appState.settings.workSchedule.targetSun = targetSun
    }
}
