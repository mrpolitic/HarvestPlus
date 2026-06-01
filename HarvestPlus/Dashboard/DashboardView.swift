//
//  DashboardView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The dashboard window shell: the segmented Daily / Weekly / Monthly /
//  Yearly tab switcher and the export button that hangs off it.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Dashboard Tab

enum DashboardTab: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: DashboardTab = .daily
    @State private var exportError: String?
    @State private var showExportError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar + export button
            HStack {
                Spacer()

                Picker("View", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)

                Spacer()

                // Export menu
                Menu {
                    Button {
                        performExport(format: .pdf)
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }

                    Button {
                        performExport(format: .csv)
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 44, height: 28)
                .help("Export report")
                .accessibilityLabel("Export report")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab content – no bindings, children write to appState.pendingExportPeriod
            switch selectedTab {
            case .daily:
                DailyDashboardView()
                    .environmentObject(appState)
            case .weekly:
                WeeklyDashboardView()
                    .environmentObject(appState)
            case .monthly:
                MonthlyDashboardView()
                    .environmentObject(appState)
            case .yearly:
                YearlyDashboardView()
                    .environmentObject(appState)
            }
        }
        .frame(minWidth: 680, idealWidth: 680, minHeight: 500, idealHeight: 720)
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // MARK: - Export (save panel first → background generation → write → reveal)

    private func performExport(format: ExportFormat) {
        guard let period = appState.pendingExportPeriod else {
            exportError = "No data to export. Switch to a tab and wait for it to load."
            showExportError = true
            return
        }

        let paperSize = appState.settings.pdfPaperSize
        let ext: String
        let contentType: UTType

        switch format {
        case .pdf:
            ext = "pdf"
            contentType = .pdf
        case .csv:
            ext = "csv"
            contentType = .commaSeparatedText
        }

        // Show save panel FIRST – no data generation yet, so UI responds instantly.
        // Must activate the app since menu bar apps can lose focus when the menu closes.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(period.filename).\(ext)"
        panel.allowedContentTypes = [contentType]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        // User picked a location – now generate off the main thread so
        // any PDF rendering time doesn't produce a spinning cursor.
        DispatchQueue.global(qos: .userInitiated).async {
            let fileData: Data?
            switch format {
            case .pdf:
                fileData = ReportExporter.exportPDF(period: period, paperSize: paperSize)
            case .csv:
                fileData = ReportExporter.exportCSV(period: period).data(using: .utf8)
            }

            guard let data = fileData else {
                DispatchQueue.main.async {
                    exportError = "Failed to generate \(ext.uppercased()) data."
                    showExportError = true
                }
                return
            }

            do {
                try data.write(to: url)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                DispatchQueue.main.async {
                    exportError = "Failed to write file: \(error.localizedDescription)"
                    showExportError = true
                }
            }
        }
    }
}
