//
//  ExportSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import SwiftUI

// MARK: - Export Settings Tab

struct ExportSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var defaultFormat: ExportFormat = .pdf
    @State private var paperSize: PaperSize = .a4
    @State private var projectNameRegex: String = "\\[\\d+\\]\\s*"

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

            Section("Project Name Display") {
                TextField("Regex to strip from project names", text: $projectNameRegex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Text("This regex is applied to project names before display. Default strips bracket codes like [000025].")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
        .onChange(of: defaultFormat) { _, _ in saveSettings() }
        .onChange(of: paperSize) { _, _ in saveSettings() }
        .onChange(of: projectNameRegex) { _, _ in saveSettings() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let ud = UserDefaults.standard
        defaultFormat = ExportFormat(rawValue: ud.string(forKey: "defaultExportFormat") ?? "PDF") ?? .pdf
        paperSize = PaperSize(rawValue: ud.string(forKey: "pdfPaperSize") ?? "A4") ?? .a4
        projectNameRegex = ud.string(forKey: "projectNameDisplayRegex") ?? "\\[\\d+\\]\\s*"
    }

    private func saveSettings() {
        let ud = UserDefaults.standard
        ud.set(defaultFormat.rawValue, forKey: "defaultExportFormat")
        ud.set(paperSize.rawValue, forKey: "pdfPaperSize")
        ud.set(projectNameRegex, forKey: "projectNameDisplayRegex")

        appState.settings.defaultExportFormat = defaultFormat
        appState.settings.pdfPaperSize = paperSize
        appState.settings.projectNameDisplayRegex = projectNameRegex
    }
}
