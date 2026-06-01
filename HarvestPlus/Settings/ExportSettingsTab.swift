//
//  ExportSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Export settings: default format (PDF / CSV), paper size, the
//  strip-`[code]`-prefixes toggle, and the report start-date cutoff.
//

import SwiftUI

// MARK: - Export Settings Tab

struct ExportSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var defaultFormat: ExportFormat = .pdf
    @State private var paperSize: PaperSize = .a4
    @State private var stripProjectPrefixCodes: Bool = true

    /// Toggle that decides whether `reportStartDate` is set or nil. Stored
    /// in @State so the DatePicker can show a sensible value (today) even
    /// when the cutoff is off – without committing it to settings.
    @State private var reportStartDateEnabled: Bool = false
    @State private var reportStartDate: Date = Date()

    var body: some View {
        Form {
            Section("Export Defaults") {
                Picker("Default Format", selection: $defaultFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Picker("PDF Paper Size", selection: $paperSize) {
                    ForEach(PaperSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
            }

            Section("Report Start Date") {
                Toggle("Exclude entries before a date", isOn: $reportStartDateEnabled)

                if reportStartDateEnabled {
                    DatePicker(
                        "Start date",
                        selection: $reportStartDate,
                        displayedComponents: .date
                    )
                }

                Text("Useful if you tracked time incorrectly for a stretch and want reports to start fresh from a specific date – historical entries stay in Harvest but are ignored in dashboards and PDFs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Project Name Display") {
                Toggle("Strip prefix codes from project names", isOn: $stripProjectPrefixCodes)

                Text("When on, leading bracket codes like “[000025]” or “[ACME-12]” are removed from project names before display in the popover, dashboards, and reports. The raw name is always preserved in Harvest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
        .onChange(of: defaultFormat) { _, _ in saveSettings() }
        .onChange(of: paperSize) { _, _ in saveSettings() }
        .onChange(of: stripProjectPrefixCodes) { _, _ in saveSettings() }
        .onChange(of: reportStartDateEnabled) { _, _ in saveSettings() }
        .onChange(of: reportStartDate) { _, _ in saveSettings() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let ud = UserDefaults.standard
        defaultFormat = ExportFormat(rawValue: ud.string(forKey: "defaultExportFormat") ?? "PDF") ?? .pdf
        paperSize = PaperSize(rawValue: ud.string(forKey: "pdfPaperSize") ?? "A4") ?? .a4
        stripProjectPrefixCodes = ud.object(forKey: "stripProjectPrefixCodes") as? Bool ?? true

        if let stored = appState.settings.reportStartDate {
            reportStartDateEnabled = true
            reportStartDate = stored
        } else {
            reportStartDateEnabled = false
            // leave reportStartDate at its default (today)
        }
    }

    private func saveSettings() {
        let ud = UserDefaults.standard
        ud.set(defaultFormat.rawValue, forKey: "defaultExportFormat")
        ud.set(paperSize.rawValue, forKey: "pdfPaperSize")
        ud.set(stripProjectPrefixCodes, forKey: "stripProjectPrefixCodes")
        // Old key from the regex-based version. Removed here so it doesn't
        // linger in users' UserDefaults.
        ud.removeObject(forKey: "projectNameDisplayRegex")

        if reportStartDateEnabled {
            let isoString = AppState.persistedDateFormatter.string(from: reportStartDate)
            ud.set(isoString, forKey: "reportStartDate")
            appState.settings.reportStartDate = reportStartDate
        } else {
            ud.removeObject(forKey: "reportStartDate")
            appState.settings.reportStartDate = nil
        }

        appState.settings.defaultExportFormat = defaultFormat
        appState.settings.pdfPaperSize = paperSize
        appState.settings.stripProjectPrefixCodes = stripProjectPrefixCodes
    }
}
