//
//  MonthlyDashboardView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//
//  The Monthly dashboard tab: month totals vs. target, the week-by-week
//  breakdown, the day heat-map, and the cumulative-pace chart.
//

import SwiftUI

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let monthlyMediumDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()

private let monthlyMonthNameFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM"
    return f
}()

private let monthlyDayMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f
}()

private let monthlyShortWeekdayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, d MMM"
    return f
}()

// MARK: - Monthly Dashboard View

struct MonthlyDashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var monthOffset: Int = 0  // 0 = current month
    @State private var entries: [TimeEntry] = []
    @State private var previousEntries: [TimeEntry] = []
    @State private var allDaySummaries: [DaySummary] = []
    @State private var previousDaySummaries: [DaySummary] = []
    @State private var isLoading: Bool = false

    private var monthDates: (first: Date, last: Date, month: Int, year: Int) {
        let cal = Calendar.current
        let today = Date()
        let shifted = cal.date(byAdding: .month, value: monthOffset, to: today)!
        let comps = cal.dateComponents([.year, .month], from: shifted)
        let first = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: first)!
        let last = cal.date(byAdding: .day, value: range.count - 1, to: first)!
        return (first, last, comps.month!, comps.year!)
    }

    /// When viewing the current (in-progress) month, cap the prior month's
    /// range at today's day-of-month so totals compare like-for-like. Apr 1–21
    /// of this month vs Mar 1–21 of last month – not Apr 1–21 vs full March,
    /// which would always make "this month" look smaller.
    ///
    /// Clamps when the previous month is shorter (e.g., today is Mar 31,
    /// previous month is February → previous range ends on Feb 28/29).
    private var previousMonthDates: (first: Date, last: Date) {
        let cal = Calendar.current
        let prevFirst = cal.date(byAdding: .month, value: -1, to: monthDates.first)!
        let prevRange = cal.range(of: .day, in: .month, for: prevFirst)!

        let prevLast: Date
        if monthOffset == 0 {
            let todayDay = cal.component(.day, from: Date())
            let clampedDay = min(todayDay, prevRange.count)
            prevLast = cal.date(byAdding: .day, value: clampedDay - 1, to: prevFirst)!
        } else {
            prevLast = cal.date(byAdding: .day, value: prevRange.count - 1, to: prevFirst)!
        }
        return (prevFirst, prevLast)
    }

    /// True when we're looking at the in-progress month; drives "so far"
    /// label suffixes on insight and trend cards.
    private var isPartialPeriodComparison: Bool {
        monthOffset == 0
    }

    private var monthSummary: MonthSummary {
        let weeks = OvertimeCalculator.weekSummaries(from: allDaySummaries)
        return MonthSummary(month: monthDates.month, year: monthDates.year, weeks: weeks)
    }

    private var cumulativeData: [(date: Date, cumulative: Double)] {
        let today = Calendar.current.startOfDay(for: Date())
        let upToToday = allDaySummaries.filter { $0.date <= today }
        return OvertimeCalculator.cumulativePace(
            from: upToToday,
            schedule: appState.settings.workSchedule
        )
    }

    /// Fetch timestamp of the entries in `entries` – used as `polledAt`
    /// for live extrapolation. See `AppState.fetchedAt(from:to:)`.
    private var entriesFetchedAt: Date? {
        appState.fetchedAt(from: monthDates.first, to: monthDates.last)
    }

    private var currentProjects: [ProjectSummary] {
        DashboardMetrics.projectHours(
            from: entries,
            polledAt: entriesFetchedAt,
            cutoff: appState.settings.reportStartDate
        )
    }

    private var previousProjects: [ProjectSummary] {
        DashboardMetrics.projectHours(from: previousEntries, polledAt: nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Month navigation
                monthNavigation

                // Smart Insights
                SmartInsightsCard(insights: monthlyInsights)

                // Summary cards
                HStack(spacing: 12) {
                    monthlyMetricCards
                }

                // Cumulative overtime chart (existing – target-based, but informational)
                cumulativeOvertimeChart

                // Project composition (new)
                projectCompositionSection

                // Project trends (new)
                if !currentProjects.isEmpty || !previousProjects.isEmpty {
                    ProjectTrendsCard(
                        trends: DashboardMetrics.projectTrends(current: currentProjects, previous: previousProjects),
                        comparisonLabel: isPartialPeriodComparison
                            ? "vs last month so far"
                            : "vs last month",
                        maxRows: 6
                    )
                }

                // Heatmap grid
                heatmapGrid

                // Highlights (streak + vacation tally)
                highlightsSection

                // Week breakdown
                weekBreakdown
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadEntries() }
        .onChange(of: monthOffset) { _, _ in loadEntries() }
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                monthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previous month (⌘←)")
            .accessibilityLabel("Previous month")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Spacer()

            VStack(spacing: 2) {
                Text(monthLabel)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(monthDates.year))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if monthOffset != 0 {
                    Button("This Month") {
                        monthOffset = 0
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.harvestOrange)
                    .help("Jump to this month (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)
                }

                Button {
                    monthOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(monthOffset >= 0)
                .opacity(monthOffset >= 0 ? 0.3 : 1)
                .help("Next month (⌘→)")
                .accessibilityLabel("Next month")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }

    // MARK: - Insights

    private var monthlyInsights: [DashboardInsight] {
        // See `previousMonthDates` – when the month is in progress, the prior
        // month's data is truncated to the same day-of-month for a fair
        // comparison. Label change reflects that.
        let label = isPartialPeriodComparison ? "last month so far" : "last month"
        return DashboardMetrics.generatePeriodInsights(
            days: allDaySummaries,
            entries: entries,
            previousDays: previousDaySummaries,
            previousEntries: previousEntries,
            meetings: nil,
            periodLabel: label,
            limit: 5
        )
    }

    // MARK: - Summary Cards

    private var monthlyMetricCards: some View {
        let actualTotal = allDaySummaries.reduce(0) { $0 + $1.actual }
        let previousTotal = previousDaySummaries.reduce(0) { $0 + $1.actual }
        let daysWorked = allDaySummaries.filter { $0.actual > 0 }.count
        let avgPerDay = daysWorked > 0 ? actualTotal / Double(daysWorked) : 0

        let deltaPercent = DashboardMetrics.percentChange(
            current: actualTotal,
            previous: previousTotal
        )

        // Sparkline: daily hours over the month
        let sparkline = DashboardMetrics.sparklineSeries(from: allDaySummaries)

        return Group {
            MetricCard(
                title: "Logged",
                value: TimeFormat.clock(actualTotal),
                icon: "clock.fill",
                color: AppColor.harvestOrange,
                deltaPercent: deltaPercent,
                sparkline: sparkline,
                tooltip: isPartialPeriodComparison
                    ? "Total hours logged this month. Δ% compares against the first \(Calendar.current.component(.day, from: Date())) days of last month."
                    : "Total hours logged this month"
            )

            MetricCard(
                title: "Avg / Day",
                value: TimeFormat.clock(avgPerDay),
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
                tooltip: "Distinct projects worked on this month"
            )
        }
    }

    // MARK: - Cumulative Overtime Chart

    private var cumulativeOvertimeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cumulative Pace")
                    .font(.headline)
                Spacer()
                PaceStatusCaption(latest: cumulativeData.last?.cumulative, periodNoun: "this month")
            }

            CumulativePaceChart(data: cumulativeData) {
                HStack {
                    Text(formatDateShort(monthDates.first))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let last = cumulativeData.last {
                        Text(formatDateShort(last.date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Project Composition

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

    // MARK: - Heatmap Grid

    private var heatmapGrid: some View {
        let cal = Calendar.current
        let allDays = allDaySummaries
        let maxHours = max(allDays.map(\.actual).max() ?? 8, 0.5)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Daily Heatmap")
                .font(.headline)

            // Calendar-style grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                // Header
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                // Leading empty cells
                let firstWeekday = cal.component(.weekday, from: monthDates.first)
                let isoWeekday = firstWeekday == 1 ? 7 : firstWeekday - 1  // Mon=1
                ForEach(0..<(isoWeekday - 1), id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }

                // Day cells
                ForEach(Array(allDays.enumerated()), id: \.element.date) { index, day in
                    let dayNum = index + 1
                    let intensity = maxHours > 0 ? day.actual / maxHours : 0

                    VStack(spacing: 1) {
                        Text("\(dayNum)")
                            .font(.caption2)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? AppColor.harvestOrange : .secondary)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(DashboardChartColor.heatmap(intensity: intensity, isNonWorking: day.isNonWorkingDay, minWorkedOpacity: 0.2))
                            .frame(height: 20)
                    }
                    .frame(height: 36)
                    .help(heatmapTooltip(day: day))
                }
            }

            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor).opacity(0.15)).frame(width: 12, height: 12)
                    Text("No hours").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColor.harvestOrange.opacity(0.3)).frame(width: 12, height: 12)
                    Text("Light").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColor.harvestOrange.opacity(0.7)).frame(width: 12, height: 12)
                    Text("Medium").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColor.harvestOrange).frame(width: 12, height: 12)
                    Text("Heavy").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }


    private func heatmapTooltip(day: DaySummary) -> String {
        let dateStr = monthlyMediumDateFormatter.string(from: day.date)
        if day.isNonWorkingDay && day.actual == 0 {
            return "\(dateStr) – Non-working day"
        }
        return "\(dateStr) – \(TimeFormat.clock(day.actual))"
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        let currentStreak = DashboardMetrics.currentWorkingStreak(from: allDaySummaries)
        let longestStreak = DashboardMetrics.longestWorkingStreak(from: allDaySummaries)
        let timeOffByCategory = DashboardMetrics.holidayDaysByTaskName(
            entries: entries,
            schedule: appState.settings.workSchedule,
            settings: appState.settings
        )

        return HStack(spacing: 12) {
            if longestStreak > 0 {
                HighlightRow(
                    icon: "flame.fill",
                    iconColor: AppColor.harvestRed,
                    label: currentStreak > 0 ? "Current streak" : "Longest streak",
                    value: "\(currentStreak > 0 ? currentStreak : longestStreak) days",
                    subtitle: currentStreak > 0 && currentStreak != longestStreak
                        ? "longest: \(longestStreak)"
                        : "consecutive logged"
                )
                .padding(AppSpacing.lg - 2)
                .frame(maxWidth: .infinity)
                .harvestSurface(cornerRadius: AppRadius.md)
            }

            ForEach(timeOffByCategory) { cat in
                HighlightRow(
                    icon: "sun.max.fill",
                    iconColor: Color(red: 0.61, green: 0.35, blue: 0.71),
                    label: cat.taskName,
                    // Decimal days against each day's actual target – see
                    // DashboardMetrics.holidayDaysByTaskName.
                    value: TimeFormat.days(cat.days),
                    subtitle: nil
                )
                .padding(AppSpacing.lg - 2)
                .frame(maxWidth: .infinity)
                .harvestSurface(cornerRadius: AppRadius.md)
            }
        }
    }

    // MARK: - Week Breakdown

    private var weekBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Week by Week")
                .font(.headline)

            ForEach(Array(monthSummary.weeks.enumerated()), id: \.element.startDate) { index, week in
                HStack {
                    Text("W\(week.weekNumber)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .leading)

                    Text(weekDateRangeShort(week))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)

                    // Progress bar (vs max week)
                    GeometryReader { geo in
                        let maxVal = max(monthSummary.weeks.map(\.actualTotal).max() ?? 0.1, 0.1)
                        let barWidth = week.actualTotal > 0 ? geo.size.width * (week.actualTotal / maxVal) : 0

                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColor.harvestOrange)
                            .frame(width: max(0, barWidth), height: 16)
                    }
                    .frame(height: 16)

                    Text(TimeFormat.clock(week.actualTotal))
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)

                    let daysActive = week.days.filter { $0.actual > 0 }.count
                    Text("\(daysActive)d")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, alignment: .trailing)
                }

                if index < monthSummary.weeks.count - 1 {
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
        let dates = monthDates
        let prev = previousMonthDates
        Task {
            async let current = appState.fetchEntries(from: dates.first, to: dates.last)
            async let previous = appState.fetchEntries(from: prev.first, to: prev.last)

            entries = await current
            previousEntries = await previous

            // Compute all day summaries in a single batch pass. Live
            // extrapolation uses this fetch's timestamp so the dashboard
            // numbers track the popover exactly.
            allDaySummaries = OvertimeCalculator.daySummaries(
                from: dates.first,
                to: dates.last,
                entries: entries,
                settings: appState.settings,
                polledAt: appState.fetchedAt(from: dates.first, to: dates.last)
            )
            previousDaySummaries = OvertimeCalculator.daySummaries(
                from: prev.first,
                to: prev.last,
                entries: previousEntries,
                settings: appState.settings
            )

            isLoading = false
            appState.pendingExportPeriod = .monthly(summary: monthSummary, entries: entries)
        }
    }

    // MARK: - Helpers

    private var monthLabel: String {
        return monthlyMonthNameFormatter.string(from: monthDates.first)
    }

    private func weekDateRangeShort(_ week: WeekSummary) -> String {
        return "\(monthlyDayMonthFormatter.string(from: week.startDate)) – \(monthlyDayMonthFormatter.string(from: week.endDate))"
    }

    private func formatDateShort(_ date: Date) -> String {
        return monthlyDayMonthFormatter.string(from: date)
    }

    private func dayLabel(for date: Date) -> String {
        return monthlyShortWeekdayDateFormatter.string(from: date)
    }

}
