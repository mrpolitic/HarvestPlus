//
//  ReportExporter+PDF.swift
//  HarvestPlus
//
//  PDF rendering for the four report periods. The page layout (title,
//  subtitle, paginated sections, footer) lives in `exportPDF`; each period's
//  content is assembled as `PDFSection`s by the per-period builders, then
//  drawn with Core Text. Extracted from ReportExporter.swift.
//

import AppKit

extension ReportExporter {

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

    // MARK: - PDF Section Model

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

    // MARK: - PDF Section Builders

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
                PDFCell(text: formatDualHours(entry.hours)),
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
                PDFCell(text: formatDualHours(entry.hours)),
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
                PDFCell(text: formatDualHours(entry.hours)),
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

    // MARK: - PDF Formatting Helpers

    /// "H:MM (X.XXh)" – both formats side-by-side. Per feedback from
    /// Michael in Slack, the HH:mm format is more legible (matches Harvest's
    /// own UI), but the decimal is also kept so anyone doing arithmetic
    /// doesn't have to convert in their head. Used for entry rows and
    /// non-delta summary cells (Logged, Expected, etc.) where the value
    /// is always non-negative.
    private static func formatDualHours(_ hours: Double) -> String {
        let abs = Swift.abs(hours)
        let (h, m) = TimeFormat.hoursAndMinutes(abs)
        return String(format: "%d:%02d (%.2fh)", h, m, abs)
    }

    /// Same as `formatDualHours` but emits a leading +/- for non-zero
    /// values – used for Delta cells (overtime / undertime). Zero comes
    /// out unsigned as "0:00 (0.00h)" to keep the table tidy.
    private static func formatDualHoursSigned(_ hours: Double) -> String {
        if hours == 0 { return "0:00 (0.00h)" }
        let abs = Swift.abs(hours)
        let (h, m) = TimeFormat.hoursAndMinutes(abs)
        let sign = hours > 0 ? "+" : "-"
        return String(format: "%@%d:%02d (%@%.2fh)", sign, h, m, sign, abs)
    }

    /// Legacy unsigned/signed H:MM-only formatter. Kept as a thin shim
    /// over `formatDualHoursSigned` so existing call sites still compile;
    /// new code should prefer the dual-format helpers.
    private static func formatPDFHours(_ hours: Double) -> String {
        formatDualHoursSigned(hours)
    }

    private static func pdfTitle(for period: ExportPeriod) -> String {
        switch period {
        case .daily(let date, _, _):
            let f = DateFormatter()
            f.dateStyle = .long
            return "Daily Report: \(f.string(from: date))"
        case .weekly(let summary, _):
            return "Weekly Report: Week \(summary.weekNumber), \(summary.year)"
        case .monthly(let summary, _):
            let monthNames = ["January", "February", "March", "April", "May", "June",
                               "July", "August", "September", "October", "November", "December"]
            let name = summary.month >= 1 && summary.month <= 12 ? monthNames[summary.month - 1] : ""
            return "Monthly Report: \(name) \(summary.year)"
        case .yearly(let year, _, _):
            return "Yearly Report: \(year)"
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
