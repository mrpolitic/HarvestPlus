//
//  ReportExporter.swift
//  HarvestPlus
//
//  Renders the daily / weekly / monthly / yearly reports to CSV or PDF. This
//  file defines the input type (`ExportPeriod`) and the `ReportExporter`
//  namespace; the rendering itself lives alongside in:
//    - ReportExporter+CSV.swift – `exportCSV` + the CSV builders
//    - ReportExporter+PDF.swift – `exportPDF` + the PDF layout / builders
//  The save panel that calls these lives in DashboardView.
//
//  Created by Razvan Politic on 15/04/2026.
//

import Foundation

// MARK: - Export Period

/// Which report to render, bundled with its pre-computed summaries and the
/// raw entries that back it. Built by the dashboard tab before export.
enum ExportPeriod {
    case daily(date: Date, entries: [TimeEntry], summary: DaySummary)
    case weekly(summary: WeekSummary, entries: [TimeEntry])
    case monthly(summary: MonthSummary, entries: [TimeEntry])
    case yearly(year: Int, months: [(month: Int, actual: Double, expected: Double)], entries: [TimeEntry])

    var filename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch self {
        case .daily(let date, _, _):
            f.dateFormat = "yyyy-MM-dd"
            return "HarvestPlus_\(f.string(from: date))"
        case .weekly(let summary, _):
            f.dateFormat = "yyyy-MM-dd"
            return "HarvestPlus_W\(summary.weekNumber)_\(f.string(from: summary.startDate))"
        case .monthly(let summary, _):
            return "HarvestPlus_\(summary.year)-\(String(format: "%02d", summary.month))"
        case .yearly(let year, _, _):
            return "HarvestPlus_\(year)"
        }
    }
}

// MARK: - Report Exporter

/// Namespace for the report renderers. The CSV and PDF implementations are
/// in `ReportExporter+CSV.swift` and `ReportExporter+PDF.swift`.
enum ReportExporter {}
