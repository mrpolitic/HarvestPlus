//
//  ReportExporter.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Period

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

// MARK: - Export File Document (for SwiftUI .fileExporter)

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.pdf, .commaSeparatedText]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Report Exporter

enum ReportExporter {

    // MARK: - CSV Export

    static func exportCSV(period: ExportPeriod) -> String {
        switch period {
        case .daily(let date, let entries, let summary):
            return buildDailyCSV(date: date, entries: entries, summary: summary)
        case .weekly(let summary, let entries):
            return buildWeeklyCSV(summary: summary, entries: entries)
        case .monthly(let summary, let entries):
            return buildMonthlyCSV(summary: summary, entries: entries)
        case .yearly(let year, let months, let entries):
            return buildYearlyCSV(year: year, months: months, entries: entries)
        }
    }

    // MARK: - PDF Export

    static func exportPDF(period: ExportPeriod, paperSize: PaperSize) -> Data? {
        let pageSize: CGSize
        switch paperSize {
        case .a4:
            pageSize = CGSize(width: 595, height: 842)  // A4 at 72 dpi
        case .letter:
            pageSize = CGSize(width: 612, height: 792)
        }

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - margin * 2

        let sections = buildPDFSections(period: period, contentWidth: contentWidth)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var currentY: CGFloat = margin
        var isFirstPage = true

        func beginPage() {
            context.beginPDFPage(nil)
            currentY = margin
            isFirstPage = false
        }

        func endPage() {
            context.endPDFPage()
        }

        // Print-safe colors (system colors like .labelColor resolve to white in dark mode)
        let pdfBlack = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let pdfGray = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        let pdfLightGray = NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.6, alpha: 1)

        beginPage()

        // Title
        let title = pdfTitle(for: period)
        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: pdfBlack
        ]
        let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
        let titleSize = titleStr.size()
        let titleRect = CGRect(x: margin, y: pageSize.height - margin - titleSize.height, width: contentWidth, height: titleSize.height)
        drawAttributedString(titleStr, in: titleRect, context: context, pageHeight: pageSize.height)
        currentY += titleSize.height + 8

        // Subtitle (date range)
        let subtitle = pdfSubtitle(for: period)
        let subtitleFont = NSFont.systemFont(ofSize: 11)
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: pdfGray
        ]
        let subtitleStr = NSAttributedString(string: subtitle, attributes: subtitleAttrs)
        let subtitleSize = subtitleStr.size()
        let subtitleRect = CGRect(x: margin, y: pageSize.height - margin - currentY - subtitleSize.height, width: contentWidth, height: subtitleSize.height)
        drawAttributedString(subtitleStr, in: subtitleRect, context: context, pageHeight: pageSize.height)
        currentY += subtitleSize.height + 20

        // Draw sections
        for section in sections {
            let sectionHeight = section.estimatedHeight

            // Check if we need a new page
            if currentY + sectionHeight > pageSize.height - margin && !isFirstPage {
                endPage()
                beginPage()
            }

            let sectionY = pageSize.height - margin - currentY

            // Section header
            let headerFont = NSFont.boldSystemFont(ofSize: 13)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: pdfBlack
            ]
            let headerStr = NSAttributedString(string: section.title, attributes: headerAttrs)
            let headerRect = CGRect(x: margin, y: sectionY - 16, width: contentWidth, height: 16)
            drawAttributedString(headerStr, in: headerRect, context: context, pageHeight: pageSize.height)
            currentY += 24

            // Section rows
            let rowFont = NSFont.systemFont(ofSize: 10)
            let rowBoldFont = NSFont.boldSystemFont(ofSize: 10)
            let rowHeight: CGFloat = 18

            for row in section.rows {
                if currentY + rowHeight > pageSize.height - margin {
                    endPage()
                    beginPage()
                }

                let rowY = pageSize.height - margin - currentY

                // Draw columns
                var colX = margin
                for (colIndex, col) in row.enumerated() {
                    let colWidth = section.columnWidths[colIndex] * contentWidth
                    let font = col.isBold ? rowBoldFont : rowFont
                    let color = col.color ?? pdfBlack
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color
                    ]
                    let str = NSAttributedString(string: col.text, attributes: attrs)
                    let rect = CGRect(x: colX, y: rowY - rowHeight, width: colWidth, height: rowHeight)
                    drawAttributedString(str, in: rect, context: context, pageHeight: pageSize.height)
                    colX += colWidth
                }

                currentY += rowHeight
            }

            currentY += 16  // Section spacing
        }

        // Footer
        let footerFont = NSFont.systemFont(ofSize: 8)
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: pdfLightGray
        ]
        let footerText = "Generated by HarvestPlus on \(formattedNow())"
        let footerStr = NSAttributedString(string: footerText, attributes: footerAttrs)
        let footerRect = CGRect(x: margin, y: margin - 12, width: contentWidth, height: 12)
        drawAttributedString(footerStr, in: footerRect, context: context, pageHeight: pageSize.height)

        endPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Save Dialog

    static func showSaveDialog(period: ExportPeriod, format: ExportFormat, paperSize: PaperSize) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(period.filename).\(format.rawValue.lowercased())"

        switch format {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Run export off the main thread so the UI stays responsive
            DispatchQueue.global(qos: .userInitiated).async {
                switch format {
                case .csv:
                    let csv = exportCSV(period: period)
                    try? csv.data(using: .utf8)?.write(to: url)
                case .pdf:
                    if let data = exportPDF(period: period, paperSize: paperSize) {
                        try? data.write(to: url)
                    }
                }

                // Reveal the exported file in Finder
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    // MARK: - PDF Drawing Helpers

    private static func drawAttributedString(_ str: NSAttributedString, in rect: CGRect, context: CGContext, pageHeight: CGFloat) {
        let framesetter = CTFramesetterCreateWithAttributedString(str as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, str.length), path, nil)

        context.saveGState()
        // Core Text draws in flipped coordinates for PDF
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    // MARK: - CSV Builders

    private static func buildDailyCSV(date: Date, entries: [TimeEntry], summary: DaySummary) -> String {
        var lines: [String] = []
        let f = DateFormatter()
        f.dateStyle = .long

        lines.append("Daily Report - \(f.string(from: date))")
        lines.append("")
        lines.append("Summary")
        lines.append("Logged,\(formatCSVHours(summary.actual))")
        lines.append("Expected,\(formatCSVHours(summary.expected))")
        lines.append("Delta,\(formatCSVHours(summary.delta))")
        lines.append("")
        lines.append("Project,Task,Notes,Hours,Running")

        for entry in entries {
            let project = csvEscape(entry.displayProjectName)
            let task = csvEscape(entry.task.name)
            let notes = csvEscape(entry.notes ?? "")
            let hours = String(format: "%.2f", entry.hours)
            let running = entry.isRunning ? "Yes" : "No"
            lines.append("\(project),\(task),\(notes),\(hours),\(running)")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildWeeklyCSV(summary: WeekSummary, entries: [TimeEntry]) -> String {
        var lines: [String] = []
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"

        lines.append("Weekly Report - Week \(summary.weekNumber)")
        lines.append("\(f.string(from: summary.startDate)) to \(f.string(from: summary.endDate))")
        lines.append("")
        lines.append("Summary")
        lines.append("Logged,\(formatCSVHours(summary.actualTotal))")
        lines.append("Expected,\(formatCSVHours(summary.expectedTotal))")
        lines.append("Delta,\(formatCSVHours(summary.delta))")
        lines.append("")
        lines.append("Day by Day")
        lines.append("Date,Day,Logged,Expected,Delta")

        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (index, day) in summary.days.enumerated() {
            let dayF = DateFormatter()
            dayF.dateFormat = "yyyy-MM-dd"
            let name = index < dayNames.count ? dayNames[index] : ""
            lines.append("\(dayF.string(from: day.date)),\(name),\(formatCSVHours(day.actual)),\(formatCSVHours(day.expected)),\(formatCSVHours(day.delta))")
        }

        lines.append("")
        lines.append("Entries")
        lines.append("Date,Project,Task,Notes,Hours")

        for entry in entries {
            let project = csvEscape(entry.displayProjectName)
            let task = csvEscape(entry.task.name)
            let notes = csvEscape(entry.notes ?? "")
            lines.append("\(entry.spentDate),\(project),\(task),\(notes),\(String(format: "%.2f", entry.hours))")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildMonthlyCSV(summary: MonthSummary, entries: [TimeEntry]) -> String {
        var lines: [String] = []
        let monthNames = ["January", "February", "March", "April", "May", "June",
                           "July", "August", "September", "October", "November", "December"]
        let monthName = summary.month >= 1 && summary.month <= 12 ? monthNames[summary.month - 1] : ""

        lines.append("Monthly Report - \(monthName) \(summary.year)")
        lines.append("")
        lines.append("Summary")
        lines.append("Logged,\(formatCSVHours(summary.actualTotal))")
        lines.append("Expected,\(formatCSVHours(summary.expectedTotal))")
        lines.append("Delta,\(formatCSVHours(summary.delta))")
        lines.append("")
        lines.append("Week by Week")
        lines.append("Week,Start,End,Logged,Expected,Delta")

        for week in summary.weeks {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            lines.append("W\(week.weekNumber),\(f.string(from: week.startDate)),\(f.string(from: week.endDate)),\(formatCSVHours(week.actualTotal)),\(formatCSVHours(week.expectedTotal)),\(formatCSVHours(week.delta))")
        }

        lines.append("")
        lines.append("Entries")
        lines.append("Date,Project,Task,Notes,Hours")

        for entry in entries {
            let project = csvEscape(entry.displayProjectName)
            let task = csvEscape(entry.task.name)
            let notes = csvEscape(entry.notes ?? "")
            lines.append("\(entry.spentDate),\(project),\(task),\(notes),\(String(format: "%.2f", entry.hours))")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildYearlyCSV(year: Int, months: [(month: Int, actual: Double, expected: Double)], entries: [TimeEntry]) -> String {
        var lines: [String] = []
        let monthNames = ["January", "February", "March", "April", "May", "June",
                           "July", "August", "September", "October", "November", "December"]

        let totalActual = months.reduce(0) { $0 + $1.actual }
        let totalExpected = months.reduce(0) { $0 + $1.expected }

        lines.append("Yearly Report - \(year)")
        lines.append("")
        lines.append("Summary")
        lines.append("Logged,\(formatCSVHours(totalActual))")
        lines.append("Expected,\(formatCSVHours(totalExpected))")
        lines.append("Delta,\(formatCSVHours(totalActual - totalExpected))")
        lines.append("")
        lines.append("Month by Month")
        lines.append("Month,Logged,Expected,Delta")

        for m in months {
            let name = m.month >= 1 && m.month <= 12 ? monthNames[m.month - 1] : ""
            lines.append("\(name),\(formatCSVHours(m.actual)),\(formatCSVHours(m.expected)),\(formatCSVHours(m.actual - m.expected))")
        }

        lines.append("")
        lines.append("Entries")
        lines.append("Date,Project,Task,Notes,Hours")

        for entry in entries {
            let project = csvEscape(entry.displayProjectName)
            let task = csvEscape(entry.task.name)
            let notes = csvEscape(entry.notes ?? "")
            lines.append("\(entry.spentDate),\(project),\(task),\(notes),\(String(format: "%.2f", entry.hours))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - PDF Section Builders

    private struct PDFSection {
        let title: String
        let columnWidths: [CGFloat]  // Fractions of content width
        let rows: [[PDFCell]]

        var estimatedHeight: CGFloat {
            CGFloat(rows.count) * 18 + 40  // row height + header + spacing
        }
    }

    private struct PDFCell {
        let text: String
        var isBold: Bool = false
        var color: NSColor? = nil
    }

    private static func buildPDFSections(period: ExportPeriod, contentWidth: CGFloat) -> [PDFSection] {
        switch period {
        case .daily(_, let entries, let summary):
            return buildDailyPDFSections(entries: entries, summary: summary)
        case .weekly(let summary, let entries):
            return buildWeeklyPDFSections(summary: summary, entries: entries)
        case .monthly(let summary, let entries):
            return buildMonthlyPDFSections(summary: summary, entries: entries)
        case .yearly(_, let months, let entries):
            return buildYearlyPDFSections(months: months, entries: entries)
        }
    }

    private static func buildDailyPDFSections(entries: [TimeEntry], summary: DaySummary) -> [PDFSection] {
        let summarySection = PDFSection(
            title: "Summary",
            columnWidths: [0.4, 0.6],
            rows: [
                [PDFCell(text: "Logged"), PDFCell(text: formatPDFHours(summary.actual), isBold: true)],
                [PDFCell(text: "Expected"), PDFCell(text: formatPDFHours(summary.expected))],
                [PDFCell(text: "Delta"), PDFCell(text: formatPDFHours(summary.delta), isBold: true,
                    color: summary.delta >= 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil)],
            ]
        )

        let entryRows: [[PDFCell]] = entries.map { entry in
            [
                PDFCell(text: entry.displayProjectName, isBold: true),
                PDFCell(text: entry.task.name),
                PDFCell(text: entry.notes ?? ""),
                PDFCell(text: String(format: "%.2fh", entry.hours)),
            ]
        }

        let entriesSection = PDFSection(
            title: "Time Entries",
            columnWidths: [0.25, 0.25, 0.35, 0.15],
            rows: [
                [PDFCell(text: "Project", isBold: true), PDFCell(text: "Task", isBold: true),
                 PDFCell(text: "Notes", isBold: true), PDFCell(text: "Hours", isBold: true)]
            ] + entryRows
        )

        return [summarySection, entriesSection]
    }

    private static func buildWeeklyPDFSections(summary: WeekSummary, entries: [TimeEntry]) -> [PDFSection] {
        let summarySection = PDFSection(
            title: "Summary",
            columnWidths: [0.4, 0.6],
            rows: [
                [PDFCell(text: "Logged"), PDFCell(text: formatPDFHours(summary.actualTotal), isBold: true)],
                [PDFCell(text: "Expected"), PDFCell(text: formatPDFHours(summary.expectedTotal))],
                [PDFCell(text: "Delta"), PDFCell(text: formatPDFHours(summary.delta), isBold: true,
                    color: summary.delta >= 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil)],
            ]
        )

        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let dayRows: [[PDFCell]] = summary.days.enumerated().map { index, day in
            let name = index < dayNames.count ? dayNames[index] : ""
            return [
                PDFCell(text: name),
                PDFCell(text: formatPDFHours(day.actual), isBold: day.actual > 0),
                PDFCell(text: formatPDFHours(day.expected)),
                PDFCell(text: formatPDFHours(day.delta),
                    color: day.delta >= 0 && day.expected > 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil),
            ]
        }

        let daysSection = PDFSection(
            title: "Day by Day",
            columnWidths: [0.3, 0.23, 0.23, 0.24],
            rows: [
                [PDFCell(text: "Day", isBold: true), PDFCell(text: "Logged", isBold: true),
                 PDFCell(text: "Expected", isBold: true), PDFCell(text: "Delta", isBold: true)]
            ] + dayRows
        )

        let entryRows: [[PDFCell]] = entries.map { entry in
            [
                PDFCell(text: entry.spentDate),
                PDFCell(text: entry.displayProjectName, isBold: true),
                PDFCell(text: entry.task.name),
                PDFCell(text: String(format: "%.2fh", entry.hours)),
            ]
        }

        let entriesSection = PDFSection(
            title: "Time Entries",
            columnWidths: [0.2, 0.3, 0.35, 0.15],
            rows: [
                [PDFCell(text: "Date", isBold: true), PDFCell(text: "Project", isBold: true),
                 PDFCell(text: "Task", isBold: true), PDFCell(text: "Hours", isBold: true)]
            ] + entryRows
        )

        return [summarySection, daysSection, entriesSection]
    }

    private static func buildMonthlyPDFSections(summary: MonthSummary, entries: [TimeEntry]) -> [PDFSection] {
        let summarySection = PDFSection(
            title: "Summary",
            columnWidths: [0.4, 0.6],
            rows: [
                [PDFCell(text: "Logged"), PDFCell(text: formatPDFHours(summary.actualTotal), isBold: true)],
                [PDFCell(text: "Expected"), PDFCell(text: formatPDFHours(summary.expectedTotal))],
                [PDFCell(text: "Delta"), PDFCell(text: formatPDFHours(summary.delta), isBold: true,
                    color: summary.delta >= 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil)],
            ]
        )

        let f = DateFormatter()
        f.dateFormat = "d MMM"
        let weekRows: [[PDFCell]] = summary.weeks.map { week in
            [
                PDFCell(text: "W\(week.weekNumber)"),
                PDFCell(text: "\(f.string(from: week.startDate)) – \(f.string(from: week.endDate))"),
                PDFCell(text: formatPDFHours(week.actualTotal), isBold: true),
                PDFCell(text: formatPDFHours(week.delta),
                    color: week.delta >= 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil),
            ]
        }

        let weeksSection = PDFSection(
            title: "Week by Week",
            columnWidths: [0.12, 0.38, 0.25, 0.25],
            rows: [
                [PDFCell(text: "Week", isBold: true), PDFCell(text: "Period", isBold: true),
                 PDFCell(text: "Logged", isBold: true), PDFCell(text: "Delta", isBold: true)]
            ] + weekRows
        )

        let entryRows: [[PDFCell]] = entries.prefix(200).map { entry in
            [
                PDFCell(text: entry.spentDate),
                PDFCell(text: entry.displayProjectName, isBold: true),
                PDFCell(text: entry.task.name),
                PDFCell(text: String(format: "%.2fh", entry.hours)),
            ]
        }

        let entriesSection = PDFSection(
            title: "Time Entries\(entries.count > 200 ? " (first 200)" : "")",
            columnWidths: [0.2, 0.3, 0.35, 0.15],
            rows: [
                [PDFCell(text: "Date", isBold: true), PDFCell(text: "Project", isBold: true),
                 PDFCell(text: "Task", isBold: true), PDFCell(text: "Hours", isBold: true)]
            ] + entryRows
        )

        return [summarySection, weeksSection, entriesSection]
    }

    private static func buildYearlyPDFSections(months: [(month: Int, actual: Double, expected: Double)], entries: [TimeEntry]) -> [PDFSection] {
        let totalActual = months.reduce(0) { $0 + $1.actual }
        let totalExpected = months.reduce(0) { $0 + $1.expected }
        let totalDelta = totalActual - totalExpected

        let summarySection = PDFSection(
            title: "Summary",
            columnWidths: [0.4, 0.6],
            rows: [
                [PDFCell(text: "Logged"), PDFCell(text: formatPDFHours(totalActual), isBold: true)],
                [PDFCell(text: "Expected"), PDFCell(text: formatPDFHours(totalExpected))],
                [PDFCell(text: "Delta"), PDFCell(text: formatPDFHours(totalDelta), isBold: true,
                    color: totalDelta >= 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil)],
            ]
        )

        let monthNames = ["January", "February", "March", "April", "May", "June",
                           "July", "August", "September", "October", "November", "December"]

        let monthRows: [[PDFCell]] = months.map { m in
            let name = m.month >= 1 && m.month <= 12 ? monthNames[m.month - 1] : ""
            let delta = m.actual - m.expected
            return [
                PDFCell(text: name),
                PDFCell(text: formatPDFHours(m.actual), isBold: m.actual > 0),
                PDFCell(text: formatPDFHours(m.expected)),
                PDFCell(text: formatPDFHours(delta),
                    color: delta >= 0 && m.expected > 0 ? NSColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1) : nil),
            ]
        }

        let monthsSection = PDFSection(
            title: "Month by Month",
            columnWidths: [0.3, 0.23, 0.23, 0.24],
            rows: [
                [PDFCell(text: "Month", isBold: true), PDFCell(text: "Logged", isBold: true),
                 PDFCell(text: "Expected", isBold: true), PDFCell(text: "Delta", isBold: true)]
            ] + monthRows
        )

        return [summarySection, monthsSection]
    }

    // MARK: - Formatting Helpers

    private static func formatCSVHours(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }

    private static func formatPDFHours(_ hours: Double) -> String {
        let sign = hours < 0 ? "-" : (hours > 0 ? "+" : "")
        let abs = abs(hours)
        let h = Int(abs)
        let m = Int((abs - Double(h)) * 60)
        if hours == 0 { return "0:00" }
        if sign == "+" { return String(format: "+%d:%02d", h, m) }
        if sign == "-" { return String(format: "-%d:%02d", h, m) }
        return String(format: "%d:%02d", h, m)
    }

    private static func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }

    private static func pdfTitle(for period: ExportPeriod) -> String {
        switch period {
        case .daily(let date, _, _):
            let f = DateFormatter()
            f.dateStyle = .long
            return "Daily Report — \(f.string(from: date))"
        case .weekly(let summary, _):
            return "Weekly Report — Week \(summary.weekNumber), \(summary.year)"
        case .monthly(let summary, _):
            let monthNames = ["January", "February", "March", "April", "May", "June",
                               "July", "August", "September", "October", "November", "December"]
            let name = summary.month >= 1 && summary.month <= 12 ? monthNames[summary.month - 1] : ""
            return "Monthly Report — \(name) \(summary.year)"
        case .yearly(let year, _, _):
            return "Yearly Report — \(year)"
        }
    }

    private static func pdfSubtitle(for period: ExportPeriod) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        switch period {
        case .daily(let date, _, _):
            return f.string(from: date)
        case .weekly(let summary, _):
            return "\(f.string(from: summary.startDate)) – \(f.string(from: summary.endDate))"
        case .monthly(let summary, _):
            let cal = Calendar.current
            let first = cal.date(from: DateComponents(year: summary.year, month: summary.month, day: 1))!
            let range = cal.range(of: .day, in: .month, for: first)!
            let last = cal.date(byAdding: .day, value: range.count - 1, to: first)!
            return "\(f.string(from: first)) – \(f.string(from: last))"
        case .yearly(let year, _, _):
            return "1 January \(year) – 31 December \(year)"
        }
    }

    private static func formattedNow() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }
}
