//
//  ReportExporter+CSV.swift
//  HarvestPlus
//
//  CSV rendering for the four report periods. Each builder produces a flat,
//  spreadsheet-friendly layout: a summary block followed by per-day/week/month
//  breakdowns and the raw entries. Extracted from ReportExporter.swift.
//

import Foundation

extension ReportExporter {

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

    // MARK: - CSV Formatting Helpers

    private static func formatCSVHours(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }

    private static func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") || string.contains("\r") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
}
