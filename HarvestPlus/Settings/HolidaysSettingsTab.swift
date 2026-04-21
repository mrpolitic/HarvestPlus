//
//  HolidaysSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import SwiftUI

// MARK: - Holiday Item

struct HolidayItem: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    var isEnabled: Bool
}

// MARK: - Holidays Settings Tab

struct HolidaysSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var holidays: [HolidayItem] = []
    @State private var icsURL: String = ""
    @State private var customDates: [Date] = []
    @State private var holidayTaskNames: String = "Holiday, Holiday (feriefridag)"
    @State private var newCustomDate: Date = Date()

    private var yearRange: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 1)...(current + 2))
    }

    var body: some View {
        Form {
            Section {
                ForEach($holidays) { $holiday in
                    Toggle(isOn: $holiday.isEnabled) {
                        HStack {
                            Text(holiday.name)
                            Spacer()
                            Text(formatDate(holiday.date))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: holiday.isEnabled) { _, _ in saveHolidayToggles() }
                }
            } header: {
                HStack {
                    Text("Danish Public Holidays")
                    Spacer()
                    Picker("", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedYear) { _, _ in rebuildHolidays() }
                }
            }

            Section("External Calendar") {
                TextField("Holiday .ics URL", text: $icsURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: icsURL) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "holidayICSUrl")
                        appState.settings.holidayICSUrl = newValue
                    }

                Text("Paste a URL to an .ics calendar feed for additional non-working days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Non-Working Days") {
                ForEach(customDates, id: \.self) { date in
                    HStack {
                        Text(formatDate(date))
                        Spacer()
                        Button {
                            customDates.removeAll { $0 == date }
                            saveCustomDates()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    DatePicker("Add date", selection: $newCustomDate, displayedComponents: .date)
                        .labelsHidden()

                    Button("Add") {
                        let startOfDay = Calendar.current.startOfDay(for: newCustomDate)
                        if !customDates.contains(startOfDay) {
                            customDates.append(startOfDay)
                            customDates.sort()
                            saveCustomDates()
                        }
                    }
                }
            }

            Section("Holiday Task Names") {
                TextField("Comma-separated task names", text: $holidayTaskNames)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: holidayTaskNames) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "holidayTaskNames")
                        appState.settings.holidayTaskNames = newValue
                    }

                Text("Time entries with these task names are treated as vacation/holiday hours. Case-insensitive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Holiday Rebuild

    private func rebuildHolidays() {
        holidays = HolidayEngine.danishHolidays(year: selectedYear)
        let disabledNames = UserDefaults.standard.stringArray(forKey: "disabledHolidays") ?? []
        for i in holidays.indices {
            if disabledNames.contains(holidays[i].name) {
                holidays[i].isEnabled = false
            }
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let ud = UserDefaults.standard
        icsURL = ud.string(forKey: "holidayICSUrl") ?? ""
        holidayTaskNames = ud.string(forKey: "holidayTaskNames") ?? "Holiday, Holiday (feriefridag)"

        // Build holidays for selected year and restore toggle states
        rebuildHolidays()

        // Load custom dates
        let dateStrings = ud.stringArray(forKey: "customNonWorkingDates") ?? []
        let formatter = ISO8601DateFormatter()
        customDates = dateStrings.compactMap { formatter.date(from: $0) }.sorted()
    }

    private func saveHolidayToggles() {
        let disabledNames = holidays.filter { !$0.isEnabled }.map { $0.name }
        UserDefaults.standard.set(disabledNames, forKey: "disabledHolidays")
        HolidayEngine.invalidateCache()
    }

    private func saveCustomDates() {
        let formatter = ISO8601DateFormatter()
        let dateStrings = customDates.map { formatter.string(from: $0) }
        UserDefaults.standard.set(dateStrings, forKey: "customNonWorkingDates")
        HolidayEngine.invalidateCache()
    }
}
