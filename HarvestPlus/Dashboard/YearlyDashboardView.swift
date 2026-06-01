//
//  YearlyDashboardView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//
//  The Yearly dashboard tab: year totals, the month-by-month breakdown, the
//  year heat-map, and the cumulative-pace chart.
//

import SwiftUI

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let yearlyMediumDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()

private let yearlyShortWeekdayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, d MMM"
    return f
}()

// MARK: - Yearly Dashboard View

struct YearlyDashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var entries: [TimeEntry] = []
    @State private var previousEntries: [TimeEntry] = []
    @State private var allDaySummaries: [DaySummary] = []
    @State private var previousDaySummaries: [DaySummary] = []
    @State private var isLoading: Bool = false

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var yearDates: (first: Date, last: Date) {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
        let last = cal.date(from: DateComponents(year: selectedYear, month: 12, day: 31))!
        return (first, last)
    }

    /// When viewing the current (in-progress) year, cap the prior year's range
    /// at the same month/day we're at today so totals compare like-for-like.
    /// Without this, Jan–Apr of the current year would be measured against
    /// Jan–Dec of last year and will always look smaller.
    ///
    /// For fully-elapsed past years (`selectedYear < currentYear`), use the
    /// full year as before.
    private var previousYearDates: (first: Date, last: Date) {
        let cal = Calendar.current
        let first = cal.date(from: DateComponents(year: selectedYear - 1, month: 1, day: 1))!
        let last: Date = {
            guard selectedYear == currentYear else {
                return cal.date(from: DateComponents(year: selectedYear - 1, month: 12, day: 31))!
            }
            let today = Date()
            let m = cal.component(.month, from: today)
            let d = cal.component(.day, from: today)
            return Self.clampedDate(year: selectedYear - 1, month: m, day: d, calendar: cal)
        }()
        return (first, last)
    }

    /// True when we're looking at an in-progress period (current year) and
    /// comparing against a truncated slice of the prior year. Drives the
    /// "YTD" / "so far" label suffixes.
    private var isPartialPeriodComparison: Bool {
        selectedYear == currentYear
    }

    /// Build a date for `year/month/day`, clamping `day` to the target month's
    /// length so Feb 29 → Feb 28 in a non-leap year rather than rolling into March.
    private static func clampedDate(year: Int, month: Int, day: Int, calendar cal: Calendar) -> Date {
        let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)!
        let clampedDay = min(day, range.count)
        return cal.date(from: DateComponents(year: year, month: month, day: clampedDay))!
    }

    /// Fetch timestamp of the entries in `entries` – used as `polledAt`
    /// for live extrapolation. See `AppState.fetchedAt(from:to:)`.
    private var entriesFetchedAt: Date? {
        appState.fetchedAt(from: yearDates.first, to: yearDates.last)
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
                // Year navigation
                yearNavigation

                // Smart Insights
                SmartInsightsCard(insights: yearlyInsights)

                // Summary cards
                HStack(spacing: 12) {
                    yearlyMetricCards
                }

                // Monthly bar chart
                monthlyBarChart

                // Cumulative overtime chart (informational)
                cumulativeOvertimeChart

                // Project composition
                projectCompositionSection

                // Project trends (vs last year)
                if !currentProjects.isEmpty || !previousProjects.isEmpty {
                    ProjectTrendsCard(
                        trends: DashboardMetrics.projectTrends(current: currentProjects, previous: previousProjects),
                        comparisonLabel: isPartialPeriodComparison
                            ? "vs \(selectedYear - 1) YTD"
                            : "vs \(selectedYear - 1)",
                        maxRows: 8
                    )
                }

                // Year heatmap
                yearHeatmap

                // Highlights (streak + vacation tally)
                highlightsSection

                // Month breakdown
                monthBreakdown
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadEntries() }
        .onChange(of: selectedYear) { _, _ in loadEntries() }
    }

    // MARK: - Year Navigation

    private var yearNavigation: some View {
        HStack {
            Button {
                selectedYear -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previous year (⌘←)")
            .accessibilityLabel("Previous year")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Spacer()

            Text(String(selectedYear))
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            HStack(spacing: 12) {
                if selectedYear != currentYear {
                    Button("This Year") {
                        selectedYear = currentYear
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.harvestOrange)
                    .help("Jump to this year (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)
                }

                Button {
                    selectedYear += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedYear >= currentYear)
                .opacity(selectedYear >= currentYear ? 0.3 : 1)
                .help("Next year (⌘→)")
                .accessibilityLabel("Next year")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }

    // MARK: - Insights

    private var yearlyInsights: [DashboardInsight] {
        // When this year is in progress we compare against last year's first
        // N days only – reflect that in the label so the user knows what
        // "+12% vs last year YTD" is actually comparing.
        let label = isPartialPeriodComparison ? "last year YTD" : "last year"
        var insights = DashboardMetrics.generatePeriodInsights(
            days: allDaySummaries,
            entries: entries,
            previousDays: previousDaySummaries.isEmpty ? nil : previousDaySummaries,
            previousEntries: previousEntries.isEmpty ? nil : previousEntries,
            meetings: nil,
            periodLabel: label,
            limit: 4
        )

        let months = monthSummaries

        // Active months
        let activeMonths = months.filter { $0.actual > 0.1 }.count
        if activeMonths > 0 && activeMonths < 12 {
            insights.append(DashboardInsight(
                icon: "calendar.badge.clock",
                text: "Active in \(activeMonths) of 12 months",
                accent: Color(red: 0.20, green: 0.60, blue: 0.86)
            ))
        }

        return Array(insights.prefix(5))
    }

    // MARK: - Summary Cards

    private var yearlyMetricCards: some View {
        let totals = yearTotals
        let previousTotal = previousDaySummaries.reduce(0) { $0 + $1.actual }
        let activeMonths = monthSummaries.filter { $0.actual > 0.1 }.count
        let avgPerActiveMonth = activeMonths > 0 ? totals.actual / Double(activeMonths) : 0

        let deltaPercent = DashboardMetrics.percentChange(
            current: totals.actual,
            previous: previousTotal
        )

        // Sparkline: monthly totals
        let sparkline = monthSummaries.map(\.actual)

        return Group {
            MetricCard(
                title: "Logged",
                value: TimeFormat.clock(totals.actual),
                icon: "clock.fill",
                color: AppColor.harvestOrange,
                deltaPercent: deltaPercent,
                sparkline: sparkline,
                tooltip: isPartialPeriodComparison
                    ? "Total hours logged this year. Δ% compares against the same Jan 1–today window of \(selectedYear - 1)."
                    : "Total hours logged this year"
            )

            MetricCard(
                title: "Avg / Month",
                value: TimeFormat.clock(avgPerActiveMonth),
                icon: "chart.bar.fill",
                color: Color(red: 0.20, green: 0.60, blue: 0.86),
                tooltip: "Average hours across active months"
            )

            MetricCard(
                title: "Days Worked",
                value: "\(totals.daysWorked)",
                icon: "calendar",
                color: AppColor.harvestGreen,
                tooltip: "Days where you logged any hours"
            )

            MetricCard(
                title: "Projects",
                value: "\(currentProjects.count)",
                icon: "briefcase.fill",
                color: Color(red: 0.61, green: 0.35, blue: 0.71),
                tooltip: "Distinct projects worked on this year"
            )
        }
    }

    // MARK: - Monthly Bar Chart

    private var monthlyBarChart: some View {
        let months = monthSummaries

        let bars: [DashboardBarChart.Bar] = months.enumerated().map { index, month in
            let isCurrent = isCurrentMonth(index + 1)
            return DashboardBarChart.Bar(
                id: index,
                value: month.actual,
                color: monthBarColor(hasHours: month.actual > 0),
                tooltip: "\(fullMonthName(index)): \(TimeFormat.clock(month.actual))",
                axisLabel: shortMonthName(index),
                axisLabelColor: isCurrent ? AppColor.harvestOrange : .secondary,
                axisLabelBold: isCurrent
            )
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Monthly Hours")
                .font(.headline)

            DashboardBarChart(
                bars: bars,
                barSpacing: 6,
                cornerRadius: 3,
                axisLabelFont: .system(size: 9)
            )
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    private func monthBarColor(hasHours: Bool) -> Color {
        if !hasHours { return Color(.separatorColor).opacity(0.2) }
        return AppColor.harvestOrange.opacity(0.55)
    }

    // MARK: - Cumulative Overtime Chart

    private var cumulativeOvertimeChart: some View {
        let endDate = selectedYear == currentYear
            ? Date()
            : yearDates.last
        let visibleDays = allDaySummaries.filter { $0.date <= endDate }
        let data = OvertimeCalculator.cumulativePace(
            from: visibleDays,
            schedule: appState.settings.workSchedule
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cumulative Pace")
                    .font(.headline)
                Spacer()
                PaceStatusCaption(latest: data.last?.cumulative, periodNoun: "this year")
            }

            CumulativePaceChart(data: data) {
                // Year view gets 12 evenly-distributed month labels so users
                // can place a hovered point in its calendar month.
                HStack {
                    ForEach(0..<12, id: \.self) { i in
                        Text(shortMonthName(i))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
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

            ProjectCompositionBar(projects: currentProjects, height: 32)
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Year Heatmap (GitHub-style)

    private var yearHeatmap: some View {
        let endDate = selectedYear == currentYear ? Date() : yearDates.last
        let allDays = allDaySummaries.filter { $0.date <= endDate }
        let maxHours = max(allDays.map(\.actual).max() ?? 8, 0.5)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.headline)

            // Weeks as columns, days as rows (Mon=top, Sun=bottom)
            let weeks = groupByWeeks(allDays)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 2) {
                    // Day labels
                    VStack(spacing: 2) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .frame(width: 10, height: 12)
                        }
                    }

                    ForEach(Array(weeks.enumerated()), id: \.element.first?.date) { _, week in
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                if dayIndex < week.count {
                                    let day = week[dayIndex]
                                    let intensity = maxHours > 0 ? day.actual / maxHours : 0

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(DashboardChartColor.heatmap(intensity: intensity, isNonWorking: day.isNonWorkingDay, minWorkedOpacity: 0.15))
                                        .frame(width: 12, height: 12)
                                        .help(heatmapTooltip(day: day))
                                } else {
                                    Color.clear.frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                Text("Less").font(.caption2).foregroundStyle(.tertiary)
                ForEach([0.15, 0.3, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.harvestOrange.opacity(level))
                        .frame(width: 12, height: 12)
                }
                Text("More").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Highlights

    private var highlightsSection: some View {
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
                    label: "Longest streak",
                    value: "\(longestStreak) days",
                    subtitle: "consecutive logged"
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
                    value: TimeFormat.days(cat.days),
                    subtitle: nil
                )
                .padding(AppSpacing.lg - 2)
                .frame(maxWidth: .infinity)
                .harvestSurface(cornerRadius: AppRadius.md)
            }
        }
    }


    // MARK: - Month Breakdown

    private var monthBreakdown: some View {
        let months = monthSummaries
        let maxActual = max(months.map(\.actual).max() ?? 0.1, 0.1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Month by Month")
                .font(.headline)

            ForEach(Array(months.enumerated()), id: \.element.month) { index, month in
                HStack {
                    Text(fullMonthName(index))
                        .font(.callout)
                        .fontWeight(isCurrentMonth(index + 1) ? .bold : .regular)
                        .foregroundStyle(isCurrentMonth(index + 1) ? .primary : .secondary)
                        .frame(width: 90, alignment: .leading)

                    // Bar proportional to best-month
                    GeometryReader { geo in
                        let barWidth = month.actual > 0 ? geo.size.width * (month.actual / maxActual) : 0

                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColor.harvestOrange.opacity(isCurrentMonth(index + 1) ? 1.0 : 0.7))
                            .frame(width: max(0, barWidth), height: 16)
                    }
                    .frame(height: 16)

                    Text(TimeFormat.clock(month.actual))
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)

                    // Show days active in that month
                    let daysInMonth = allDaySummaries.filter {
                        Calendar.current.component(.month, from: $0.date) == month.month && $0.actual > 0
                    }
                    Text(daysInMonth.isEmpty ? "" : "\(daysInMonth.count)d")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 35, alignment: .trailing)
                }

                if index < 11 {
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
        let dates = yearDates
        let prev = previousYearDates
        let year = selectedYear

        Task {
            async let current = appState.fetchEntries(from: dates.first, to: dates.last)
            async let previous = appState.fetchEntries(from: prev.first, to: prev.last)

            entries = await current
            previousEntries = await previous

            // Compute all day summaries in a single batch pass (O(entries + days))
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
            let months = monthSummaries.map { (month: $0.month, actual: $0.actual, expected: $0.expected) }
            appState.pendingExportPeriod = .yearly(year: year, months: months, entries: entries)
        }
    }

    // MARK: - Computed Data

    private struct MonthData {
        let month: Int
        let actual: Double
        let expected: Double
        var delta: Double { actual - expected }
    }

    private var monthSummaries: [MonthData] {
        let cal = Calendar.current
        return (1...12).map { month in
            let monthDays = allDaySummaries.filter { cal.component(.month, from: $0.date) == month }
            let actual = monthDays.reduce(0) { $0 + $1.actual }
            let expected = monthDays.reduce(0) { $0 + $1.expected }
            return MonthData(month: month, actual: actual, expected: expected)
        }
    }

    private var yearTotals: (actual: Double, expected: Double, delta: Double, daysWorked: Int) {
        let months = monthSummaries
        let actual = months.reduce(0) { $0 + $1.actual }
        let expected = months.reduce(0) { $0 + $1.expected }

        let endDate = selectedYear == currentYear ? Date() : yearDates.last
        let daysWorked = allDaySummaries.filter { $0.date <= endDate && $0.actual > 0 }.count

        return (actual, expected, actual - expected, daysWorked)
    }

    // MARK: - Heatmap Helpers

    private func groupByWeeks(_ days: [DaySummary]) -> [[DaySummary]] {
        let cal = Calendar.current
        var weeks: [[DaySummary]] = []
        var currentWeek: [DaySummary] = []

        for day in days {
            let weekday = cal.component(.weekday, from: day.date)
            let isoWeekday = weekday == 1 ? 7 : weekday - 1  // Mon=1, Sun=7

            if isoWeekday == 1 && !currentWeek.isEmpty {
                weeks.append(currentWeek)
                currentWeek = []
            }

            // Pad first week with empties
            if weeks.isEmpty && currentWeek.isEmpty && isoWeekday > 1 {
                for _ in 1..<isoWeekday {
                    currentWeek.append(DaySummary(
                        date: day.date, expected: 0, actual: 0,
                        holidayHours: 0, isNonWorkingDay: true
                    ))
                }
            }

            currentWeek.append(day)
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }

        return weeks
    }


    private func heatmapTooltip(day: DaySummary) -> String {
        let dateStr = yearlyMediumDateFormatter.string(from: day.date)
        if day.isNonWorkingDay && day.actual == 0 { return dateStr }
        return "\(dateStr) – \(TimeFormat.clock(day.actual))"
    }

    // MARK: - Helpers

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                               "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private let fullMonthNames = ["January", "February", "March", "April", "May", "June",
                                   "July", "August", "September", "October", "November", "December"]

    private func shortMonthName(_ index: Int) -> String {
        monthNames[index]
    }

    private func fullMonthName(_ index: Int) -> String {
        fullMonthNames[index]
    }

    private func isCurrentMonth(_ month: Int) -> Bool {
        selectedYear == currentYear && month == Calendar.current.component(.month, from: Date())
    }

    private func dayLabel(for date: Date) -> String {
        return yearlyShortWeekdayDateFormatter.string(from: date)
    }
}
