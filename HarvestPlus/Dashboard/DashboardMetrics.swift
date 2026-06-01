//
//  DashboardMetrics.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 21/04/2026.
//
//  Shared computations used by all dashboard views (Daily / Weekly / Monthly / Yearly).
//  These functions are intentionally decoupled from the "target" concept – they derive
//  insights from logged data alone so they remain meaningful for users who don't
//  enforce daily hour targets.

import Foundation
import SwiftUI

// MARK: - Project Summary

struct ProjectSummary: Identifiable {
    let id: Int          // project.id from Harvest
    let name: String
    let hours: Double
}

// MARK: - Project Trend

struct ProjectTrend: Identifiable {
    let id: Int
    let name: String
    let currentHours: Double
    let previousHours: Double

    /// Percent change from previous to current. `nil` means no previous data to compare.
    var percentChange: Double? {
        guard previousHours > 0.01 else { return nil }
        return (currentHours - previousHours) / previousHours * 100
    }

    enum Direction {
        case up, down, steady, new, gone

        var symbol: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .steady: return "arrow.right"
            case .new: return "sparkle"
            case .gone: return "xmark"
            }
        }

        var color: Color {
            switch self {
            case .up: return Color(red: 0.20, green: 0.70, blue: 0.40)
            case .down: return AppColor.harvestRed
            case .steady: return .secondary
            case .new: return AppColor.harvestOrange
            case .gone: return Color.secondary.opacity(0.5)
            }
        }
    }

    var direction: Direction {
        if previousHours < 0.01 && currentHours > 0.01 { return .new }
        if currentHours < 0.01 && previousHours > 0.01 { return .gone }
        guard let change = percentChange else { return .steady }
        if change >= 10 { return .up }
        if change <= -10 { return .down }
        return .steady
    }
}

// MARK: - Insight

struct DashboardInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let accent: Color
}

/// Day-only formatter for parsing `entry.spentDate`'s "yyyy-MM-dd" form
/// when filtering by the report-start-date cutoff. Hoisted to file scope
/// so it isn't re-allocated per entry in tight loops.
private let projectHoursDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    return f
}()

// MARK: - Dashboard Metrics

struct DashboardMetrics {

    // MARK: - Project Aggregation

    /// Aggregate entries by project, including running-timer elapsed time.
    /// Sorted high-to-low by hours. Live elapsed is extrapolated from
    /// `polledAt` (see TimeEntry.liveHours). Pass `nil` for historical
    /// periods where no running timer can exist.
    ///
    /// If `cutoff` is set, entries dated strictly before that day are
    /// excluded – same semantics as `OvertimeCalculator`'s reportStartDate
    /// handling.
    static func projectHours(
        from entries: [TimeEntry],
        polledAt: Date? = nil,
        cutoff: Date? = nil
    ) -> [ProjectSummary] {
        var grouped: [Int: (name: String, hours: Double)] = [:]
        let now = Date()
        let cutoffDay = cutoff.map { Calendar.current.startOfDay(for: $0) }
        for entry in entries {
            if let cutoffDay,
               let entryDate = projectHoursDateFormatter.date(from: entry.spentDate),
               Calendar.current.startOfDay(for: entryDate) < cutoffDay {
                continue
            }
            let hours = entry.liveHours(now: now, polledAt: polledAt)
            // `default:` seeds with (name, 0) on first sight and we add in place –
            // one hash lookup per entry instead of two (previous `!= nil` check
            // + force-unwrap write).
            grouped[entry.project.id, default: (name: entry.displayProjectName, hours: 0)].hours += hours
        }
        return grouped
            .map { ProjectSummary(id: $0.key, name: $0.value.name, hours: $0.value.hours) }
            .sorted { $0.hours > $1.hours }
    }

    // MARK: - Lightest Day

    /// Day with the fewest hours – among working days that had SOME logged time.
    /// Returns nil if no working day had entries.
    static func fewestHoursDay(from days: [DaySummary]) -> DaySummary? {
        let working = days.filter { !$0.isNonWorkingDay && $0.actual > 0 }
        return working.min { $0.actual < $1.actual }
    }

    // MARK: - Streak

    /// Current streak of consecutive working-days (today going backwards) on which hours were logged.
    /// Non-working days are "skipped" – they neither continue nor break a streak.
    /// `days` must be sorted ascending by date.
    static func currentWorkingStreak(from days: [DaySummary]) -> Int {
        var streak = 0
        // Walk backwards from the last day
        for day in days.reversed() {
            if day.isNonWorkingDay { continue }
            if day.actual > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// Longest streak of consecutive working days with hours over the given range.
    static func longestWorkingStreak(from days: [DaySummary]) -> Int {
        var longest = 0
        var current = 0
        for day in days {
            if day.isNonWorkingDay { continue }
            if day.actual > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    // MARK: - Focus Score

    /// Average number of time entries per day-worked. Higher = more fragmented.
    /// Returns 0 if no days were worked.
    static func entriesPerWorkingDay(entries: [TimeEntry], days: [DaySummary]) -> Double {
        let daysWorked = days.filter { $0.actual > 0 && !$0.isNonWorkingDay }.count
        guard daysWorked > 0 else { return 0 }
        return Double(entries.count) / Double(daysWorked)
    }

    /// Qualitative label for an entries-per-day value.
    static func focusLabel(entriesPerDay: Double) -> (label: String, color: Color) {
        if entriesPerDay == 0 {
            return ("No data", .secondary)
        }
        if entriesPerDay <= 2.0 {
            return ("Focused", Color(red: 0.20, green: 0.70, blue: 0.40))
        }
        if entriesPerDay <= 4.5 {
            return ("Balanced", AppColor.harvestOrange)
        }
        return ("Fragmented", AppColor.harvestRed)
    }

    // MARK: - Comparison

    /// Percent change from previous to current. Returns nil if previous is ~0
    /// (change is "undefined" when there's nothing to compare against).
    static func percentChange(current: Double, previous: Double) -> Double? {
        guard previous > 0.01 else { return nil }
        return (current - previous) / previous * 100
    }

    /// Format a percent change as a signed string like "+12%" / "−8%".
    /// Rounds to whole percents. Returns "–" for nil.
    static func formatPercentChange(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        let rounded = Int(value.rounded())
        if rounded == 0 { return "0%" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(abs(rounded))%"
    }

    // MARK: - Meeting Load

    /// Total duration of meetings (in hours) that fall on the given day.
    static func meetingHours(meetings: [CalendarEvent]) -> Double {
        // Clamp each event at 0 – a malformed calendar event with end < start would
        // otherwise contribute negative hours to the meeting-load math.
        meetings.reduce(0) { $0 + max(0, Double($1.durationMinutes)) / 60.0 }
    }

    /// Percent of logged hours represented by meetings. `nil` if no hours logged.
    static func meetingLoadPercent(meetingHours: Double, loggedHours: Double) -> Double? {
        guard loggedHours > 0.01 else { return nil }
        return min(meetingHours / loggedHours * 100, 999)
    }

    // MARK: - Project Trends

    /// Compare current-period projects to previous-period projects.
    /// Returns a list of trends sorted by current hours desc. Includes projects present in either period.
    static func projectTrends(current: [ProjectSummary], previous: [ProjectSummary]) -> [ProjectTrend] {
        var previousMap: [Int: ProjectSummary] = [:]
        for p in previous { previousMap[p.id] = p }

        var currentMap: [Int: ProjectSummary] = [:]
        for p in current { currentMap[p.id] = p }

        let allIds = Set(previousMap.keys).union(currentMap.keys)

        return allIds.map { id -> ProjectTrend in
            let cur = currentMap[id]
            let prev = previousMap[id]
            return ProjectTrend(
                id: id,
                name: cur?.name ?? prev?.name ?? "Unknown",
                currentHours: cur?.hours ?? 0,
                previousHours: prev?.hours ?? 0
            )
        }
        .sorted { $0.currentHours > $1.currentHours }
    }

    // MARK: - Vacation / Holiday Tally

    /// Number of days in the range that count as "vacation / holiday" – either
    /// marked non-working AND had holiday hours, OR holiday-task hours logged.
    static func vacationDaysTaken(from days: [DaySummary]) -> Int {
        days.filter { $0.holidayHours > 0 }.count
    }

    /// Time off taken over the range, expressed in **days** with decimals
    /// (each spent-date's per-day target as the unit – a 7.5h holiday entry
    /// on a 7.5h-target day = 1.0 days), broken down per holiday task name
    /// (e.g., "Holiday" vs. "Holiday (feriefridag)" – and any other names
    /// the user has configured in `holidayTaskNames`). Used by the
    /// dashboards to show one tile per type instead of an aggregated
    /// "Time off" row.
    ///
    /// Each entry is converted to a fractional day against its own
    /// spent-date's target. Entries whose date has no expected hours
    /// (weekend / public holiday) contribute zero. Returns the list
    /// sorted by days descending so the biggest bucket is rendered first.
    struct HolidayCategoryDays: Identifiable {
        let taskName: String
        let days: Double
        var id: String { taskName }
    }

    static func holidayDaysByTaskName(
        entries: [TimeEntry],
        schedule: WorkSchedule,
        settings: AppSettings
    ) -> [HolidayCategoryDays] {
        // Parse the spentDate strings once; reusing the file-level
        // `projectHoursDateFormatter` already declared above.
        var byTask: [String: Double] = [:]
        for entry in entries {
            guard HolidayEngine.isHolidayTask(taskName: entry.task.name, settings: settings) else { continue }
            guard let date = projectHoursDateFormatter.date(from: entry.spentDate) else { continue }
            let target = schedule.dailyTarget(for: date)
            guard target > 0 else { continue }
            byTask[entry.task.name, default: 0] += entry.hours / target
        }
        return byTask
            .map { HolidayCategoryDays(taskName: $0.key, days: $0.value) }
            .sorted { $0.days > $1.days }
    }

    // MARK: - Sparkline Data

    /// Daily hours for the range, used as sparkline input. Returns values in date order.
    static func sparklineSeries(from days: [DaySummary]) -> [Double] {
        days.map { $0.actual }
    }

    // MARK: - Insight Generation

    /// Returns a short (max `limit`) list of auto-generated insight bullets for a period.
    /// Intentionally avoids any "target hit" framing – users don't enforce daily targets.
    static func generatePeriodInsights(
        days: [DaySummary],
        entries: [TimeEntry],
        previousDays: [DaySummary]?,
        previousEntries: [TimeEntry]?,
        meetings: [CalendarEvent]?,
        periodLabel: String,
        polledAt: Date? = nil,
        limit: Int = 4
    ) -> [DashboardInsight] {
        var insights: [DashboardInsight] = []

        let totalHours = days.reduce(0) { $0 + $1.actual }
        let previousTotal = previousDays?.reduce(0) { $0 + $1.actual }

        // 1. Period-over-period change
        if let prev = previousTotal,
           let change = percentChange(current: totalHours, previous: prev) {
            let rounded = Int(change.rounded())
            if abs(rounded) >= 3 {
                let arrow = rounded > 0 ? "↑" : "↓"
                let accent: Color = rounded > 0
                    ? Color(red: 0.20, green: 0.70, blue: 0.40)
                    : AppColor.harvestOrange
                insights.append(DashboardInsight(
                    icon: rounded > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                    text: "\(arrow) \(abs(rounded))% hours logged vs \(periodLabel)",
                    accent: accent
                ))
            } else if abs(rounded) < 3 {
                insights.append(DashboardInsight(
                    icon: "equal.circle",
                    text: "Hours logged steady vs \(periodLabel) (±\(abs(rounded))%)",
                    accent: .secondary
                ))
            }
        }

        // 2. Project trend – largest mover
        if let prevEntries = previousEntries {
            let curProjects = projectHours(from: entries, polledAt: polledAt)
            let prevProjects = projectHours(from: prevEntries)
            let trends = projectTrends(current: curProjects, previous: prevProjects)

            // Biggest mover (in absolute hours) excluding brand-new/gone
            let mover = trends
                .filter { $0.direction == .up || $0.direction == .down }
                .max { abs($0.currentHours - $0.previousHours) < abs($1.currentHours - $1.previousHours) }

            if let m = mover, let pct = m.percentChange {
                let arrow = pct > 0 ? "↑" : "↓"
                let color: Color = pct > 0
                    ? Color(red: 0.20, green: 0.70, blue: 0.40)
                    : AppColor.harvestRed
                let pctStr = "\(abs(Int(pct.rounded())))%"
                insights.append(DashboardInsight(
                    icon: "briefcase.fill",
                    text: "\(m.name) \(arrow) \(pctStr) vs \(periodLabel)",
                    accent: color
                ))
            } else if let newProject = trends.first(where: { $0.direction == .new }) {
                insights.append(DashboardInsight(
                    icon: "sparkles",
                    text: "New this period: \(newProject.name) (\(TimeFormat.clock(newProject.currentHours)))",
                    accent: AppColor.harvestOrange
                ))
            }
        }

        // 3. Streak
        let streak = currentWorkingStreak(from: days)
        if streak >= 3 {
            insights.append(DashboardInsight(
                icon: "flame.fill",
                text: "\(streak)-day logging streak",
                accent: AppColor.harvestOrange
            ))
        }

        // 4. Meeting load (if provided)
        if let meetings = meetings, !meetings.isEmpty, !entries.isEmpty {
            let mh = meetingHours(meetings: meetings)
            if let pct = meetingLoadPercent(meetingHours: mh, loggedHours: totalHours), pct > 20 {
                insights.append(DashboardInsight(
                    icon: "person.2.fill",
                    text: "\(Int(pct.rounded()))% of your hours overlapped with meetings",
                    accent: AppColor.meetingBlue
                ))
            }
        }

        // 5. Focus score (only for weekly+)
        if days.count > 1 {
            let epd = entriesPerWorkingDay(entries: entries, days: days)
            if epd > 0 {
                let focus = focusLabel(entriesPerDay: epd)
                let epdRounded = (epd * 10).rounded() / 10
                insights.append(DashboardInsight(
                    icon: focus.label == "Focused" ? "target" : "square.grid.2x2",
                    text: "\(focus.label) – \(epdRounded) entries/day on average",
                    accent: focus.color
                ))
            }
        }

        // 6. Vacation / holiday
        let vac = vacationDaysTaken(from: days)
        if vac > 0 {
            insights.append(DashboardInsight(
                icon: "sun.max.fill",
                text: "\(vac) holiday day\(vac == 1 ? "" : "s") in this period",
                accent: Color(red: 0.61, green: 0.35, blue: 0.71)
            ))
        }

        return Array(insights.prefix(limit))
    }

}

// MARK: - Deterministic Project Colors

/// Shared color palette for project rendering across dashboards.
/// Color is selected by `abs(projectId % colors.count)` so a project keeps the same color
/// regardless of ordering or view.
enum ProjectPalette {
    static let colors: [Color] = [
        AppColor.harvestOrange,
        Color(red: 0.20, green: 0.60, blue: 0.86),
        AppColor.harvestGreen,
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.95, green: 0.77, blue: 0.06),
        Color(red: 0.90, green: 0.49, blue: 0.13),
        Color(red: 0.00, green: 0.59, blue: 0.53),
        Color(red: 0.91, green: 0.44, blue: 0.56),
    ]

    static func color(for projectId: Int) -> Color {
        // `abs(projectId % count)`, not `abs(projectId) % count`: a project id of
        // Int.min would overflow-trap inside abs(). Harvest ids are positive, but
        // this keeps a stray negative/sentinel id from crashing the dashboards.
        colors[abs(projectId % colors.count)]
    }
}
