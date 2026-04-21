//
//  WeeklyDashboardView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//

import SwiftUI

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let weeklyDayMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f
}()

private let weeklyLongDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMM"
    return f
}()

private let weeklyShortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d/M"
    return f
}()

// MARK: - Weekly Dashboard View

struct WeeklyDashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var weekOffset: Int = 0  // 0 = current week, -1 = last week, etc.
    @State private var entries: [TimeEntry] = []
    @State private var previousEntries: [TimeEntry] = []
    @State private var isLoading: Bool = false

    private var weekDates: (monday: Date, sunday: Date) {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let shifted = cal.date(byAdding: .weekOfYear, value: weekOffset, to: today)!
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: shifted))!
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        return (monday, sunday)
    }

    /// When viewing the in-progress week, cap the prior week at the same
    /// weekday as today so totals compare like-for-like. If today is Tuesday,
    /// compare Mon–Tue of this week vs Mon–Tue of last week — not Mon–Tue vs
    /// full Mon–Sun, which would always make "this week" look smaller.
    ///
    /// For historic weeks, `end` is the full Sunday.
    private var previousWeekDates: (monday: Date, end: Date) {
        let cal = Calendar(identifier: .iso8601)
        let monday = cal.date(byAdding: .weekOfYear, value: -1, to: weekDates.monday)!

        let endOffset: Int
        if weekOffset == 0 {
            // `ordinality(of: .day, in: .weekOfYear, ...)` with the ISO8601
            // calendar (Monday-first) returns Mon=1..Sun=7. Subtract 1 to get
            // the Monday-relative day offset (Mon=0, Tue=1, ..., Sun=6).
            let ordinal = cal.ordinality(of: .day, in: .weekOfYear, for: Date()) ?? 1
            endOffset = max(0, min(6, ordinal - 1))
        } else {
            endOffset = 6
        }
        let end = cal.date(byAdding: .day, value: endOffset, to: monday)!
        return (monday, end)
    }

    /// True when we're looking at the in-progress week; drives "so far"
    /// label suffixes on insight and trend cards.
    private var isPartialPeriodComparison: Bool {
        weekOffset == 0
    }

    private var weekSummary: WeekSummary {
        OvertimeCalculator.weekSummary(
            containing: weekDates.monday,
            entries: entries,
            settings: appState.settings
        )
    }

    private var previousWeekSummary: WeekSummary {
        OvertimeCalculator.weekSummary(
            containing: previousWeekDates.monday,
            entries: previousEntries,
            settings: appState.settings
        )
    }

    private var currentProjects: [ProjectSummary] {
        DashboardMetrics.projectHours(from: entries)
    }

    private var previousProjects: [ProjectSummary] {
        DashboardMetrics.projectHours(from: previousEntries)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Week navigation
                weekNavigation

                // Smart Insights
                SmartInsightsCard(insights: weeklyInsights)

                // Summary cards (adapted: no "Target", delta and sparkline instead)
                HStack(spacing: 12) {
                    weeklyMetricCards
                }

                // Daily bar chart
                dailyBarChart

                // Project composition
                projectCompositionSection

                // Project trends
                if !currentProjects.isEmpty || !previousProjects.isEmpty {
                    ProjectTrendsCard(
                        trends: DashboardMetrics.projectTrends(current: currentProjects, previous: previousProjects),
                        comparisonLabel: isPartialPeriodComparison
                            ? "vs last week so far"
                            : "vs last week",
                        maxRows: 6
                    )
                }

                // Highlights (lightest day)
                highlightsSection

                // Day-by-day breakdown
                dayBreakdown
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadEntries() }
        .onChange(of: weekOffset) { _, _ in loadEntries() }
    }

    // MARK: - Week Navigation

    private var weekNavigation: some View {
        HStack {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previous week (⌘←)")
            .accessibilityLabel("Previous week")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Spacer()

            VStack(spacing: 2) {
                Text(weekLabel)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(weekDateRange)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if weekOffset != 0 {
                    Button("This Week") {
                        weekOffset = 0
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.harvestOrange)
                    .help("Jump to this week (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)
                }

                Button {
                    weekOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(weekOffset >= 0)
                .opacity(weekOffset >= 0 ? 0.3 : 1)
                .help("Next week (⌘→)")
                .accessibilityLabel("Next week")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }

    // MARK: - Insights

    private var weeklyInsights: [DashboardInsight] {
        // See `previousWeekDates` — when viewing the in-progress week, the
        // prior week's data is truncated to the same weekday range.
        let label = isPartialPeriodComparison ? "last week so far" : "last week"
        return DashboardMetrics.generatePeriodInsights(
            days: weekSummary.days,
            entries: entries,
            previousDays: previousWeekSummary.days,
            previousEntries: previousEntries,
            meetings: nil,
            periodLabel: label,
            limit: 4
        )
    }

    // MARK: - Summary Cards

    private var weeklyMetricCards: some View {
        let ws = weekSummary
        let pws = previousWeekSummary
        let daysWorked = ws.days.filter { $0.actual > 0 }.count
        let avgPerDay = daysWorked > 0 ? ws.actualTotal / Double(daysWorked) : 0

        let deltaPercent = DashboardMetrics.percentChange(
            current: ws.actualTotal,
            previous: pws.actualTotal
        )

        let sparkline = DashboardMetrics.sparklineSeries(from: ws.days)

        return Group {
            MetricCard(
                title: "Logged",
                value: formatHoursCompact(ws.actualTotal),
                icon: "clock.fill",
                color: AppColor.harvestOrange,
                deltaPercent: deltaPercent,
                sparkline: sparkline,
                tooltip: isPartialPeriodComparison
                    ? "Total hours logged this week. Δ% compares against the same Mon–today window of last week."
                    : "Total hours logged this week"
            )

            MetricCard(
                title: "Avg / Day",
                value: formatHoursCompact(avgPerDay),
                icon: "chart.bar.fill",
                color: Color(red: 0.20, green: 0.60, blue: 0.86),
                tooltip: "Average hours across days worked"
            )

            MetricCard(
                title: "Days Worked",
                value: "\(daysWorked)",
                icon: "calendar",
                color: AppColor.harvestGreen,
                tooltip: "Days where you logged any hours"
            )

            MetricCard(
                title: "Projects",
                value: "\(currentProjects.count)",
                icon: "briefcase.fill",
                color: Color(red: 0.61, green: 0.35, blue: 0.71),
                tooltip: "Distinct projects worked on this week"
            )
        }
    }

    // MARK: - Daily Bar Chart

    private var dailyBarChart: some View {
        let days = weekSummary.days

        // Map DaySummary → DashboardBarChart.Bar. The shared chart owns the
        // Y-axis scale + gridlines; this view just decides how each bar is
        // colored and whether today's label should be highlighted.
        let bars: [DashboardBarChart.Bar] = days.enumerated().map { index, day in
            let today = isToday(day.date)
            return DashboardBarChart.Bar(
                id: index,
                value: day.actual,
                color: barColor(for: day),
                tooltip: "\(fullDayName(index)): \(formatHoursCompact(day.actual))",
                axisLabel: shortDayName(index),
                axisLabelColor: today ? AppColor.harvestOrange : .secondary,
                axisLabelBold: today
            )
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Hours")
                    .font(.headline)

                Spacer()

                let entriesPerDay = DashboardMetrics.entriesPerWorkingDay(entries: entries, days: days)
                if entriesPerDay > 0 {
                    let focus = DashboardMetrics.focusLabel(entriesPerDay: entriesPerDay)
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(focus.color)
                        Text("\(focus.label) · \(String(format: "%.1f", entriesPerDay)) entries/day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help("Average entries per working day — lower means more focused, higher means more context switches")
                }
            }

            DashboardBarChart(bars: bars)
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    private func barColor(for day: DaySummary) -> Color {
        if day.actual == 0 && day.isNonWorkingDay {
            return Color(.separatorColor).opacity(0.3)
        }
        return AppColor.harvestOrange.opacity(day.actual > 0 ? 0.55 : 0.15)
    }

    // MARK: - Project Composition Section

    private var projectCompositionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Project Mix")
                    .font(.headline)
                Spacer()
                Text("\(currentProjects.count) project\(currentProjects.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProjectCompositionBar(projects: currentProjects, height: 28)
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Highlights Section (Lightest day)

    private var highlightsSection: some View {
        let days = weekSummary.days
        let lightest = DashboardMetrics.fewestHoursDay(from: days)

        return Group {
            if let lightest = lightest {
                HStack(spacing: 12) {
                    HighlightRow(
                        icon: "leaf.fill",
                        iconColor: AppColor.harvestGreen,
                        label: "Lightest day",
                        value: formatHoursCompact(lightest.actual),
                        subtitle: dayLabel(for: lightest.date)
                    )
                    .padding(AppSpacing.lg - 2)
                    .frame(maxWidth: .infinity)
                    .harvestSurface(cornerRadius: AppRadius.md)
                }
            }
        }
    }

    // MARK: - Day Breakdown

    private var dayBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day by Day")
                .font(.headline)

            ForEach(Array(weekSummary.days.enumerated()), id: \.element.date) { index, day in
                HStack {
                    Text(dayName(index))
                        .font(.callout)
                        .fontWeight(isToday(day.date) ? .bold : .regular)
                        .foregroundStyle(isToday(day.date) ? .primary : .secondary)
                        .frame(width: 90, alignment: .leading)

                    Text(formatDateShort(day.date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 60, alignment: .leading)

                    // Mini progress bar (proportional to max day in the week)
                    GeometryReader { geo in
                        let maxVal = max(weekSummary.days.map(\.actual).max() ?? 0.1, 0.1)
                        let barWidth = day.actual > 0 ? geo.size.width * (day.actual / maxVal) : 0

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                day.isNonWorkingDay && day.actual == 0
                                    ? Color(.separatorColor).opacity(0.25)
                                    : AppColor.harvestOrange
                            )
                            .frame(width: max(0, barWidth), height: 14)
                    }
                    .frame(height: 14)

                    // Hours
                    Text(formatHoursCompact(day.actual))
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)

                    // Entries count for that day
                    let dayEntries = entries.filter { entry in
                        guard let d = OvertimeCalculator.parseSpentDate(entry.spentDate) else { return false }
                        return Calendar.current.isDate(d, inSameDayAs: day.date)
                    }
                    Text(dayEntries.isEmpty ? "" : "\(dayEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 75, alignment: .trailing)
                }

                if index < 6 {
                    Divider()
                }
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Data Loading

    private func loadEntries() {
        isLoading = true
        let dates = weekDates
        let prev = previousWeekDates
        Task {
            async let current = appState.fetchEntries(from: dates.monday, to: dates.sunday)
            async let previous = appState.fetchEntries(from: prev.monday, to: prev.end)

            entries = await current
            previousEntries = await previous
            isLoading = false
            appState.pendingExportPeriod = .weekly(summary: weekSummary, entries: entries)
        }
    }

    // MARK: - Helpers

    private var weekLabel: String {
        if weekOffset == 0 { return "This Week" }
        if weekOffset == -1 { return "Last Week" }
        let cal = Calendar(identifier: .iso8601)
        let weekNum = cal.component(.weekOfYear, from: weekDates.monday)
        return "Week \(weekNum)"
    }

    private var weekDateRange: String {
        return "\(weeklyDayMonthFormatter.string(from: weekDates.monday)) – \(weeklyDayMonthFormatter.string(from: weekDates.sunday))"
    }

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func dayName(_ index: Int) -> String {
        dayNames[index]
    }

    private func fullDayName(_ index: Int) -> String {
        dayNames[index]
    }

    private func shortDayName(_ index: Int) -> String {
        shortDayNames[index]
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayLabel(for date: Date) -> String {
        return weeklyLongDayFormatter.string(from: date)
    }

    private func formatDateShort(_ date: Date) -> String {
        return weeklyShortDateFormatter.string(from: date)
    }

    private func formatHoursCompact(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return String(format: "%d:%02d", h, m)
    }
}
