//
//  DailyDashboardView.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The Daily dashboard tab: today's hours vs. target, the timeline bar,
//  meetings, and the day's time entries.
//

import SwiftUI
import Combine

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let dailyMeetingTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private let dailyWeekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE"
    return f
}()

private let dailyLongDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .long
    return f
}()

// MARK: - Daily Dashboard View

struct DailyDashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedDate: Date = Date()
    @State private var entries: [TimeEntry] = []
    @State private var previousDayEntries: [TimeEntry] = []
    @State private var meetings: [CalendarEvent] = []
    @State private var isLoading: Bool = false
    @State private var meetingToLog: CalendarEvent?

    /// Wall-clock time when `entries` were last fetched from Harvest.
    /// Used as `polledAt` for live-elapsed extrapolation so the dashboard's
    /// running-timer contribution matches the popover's exactly. See
    /// `AppState.fetchedAt(from:to:)` for why this is preferable to
    /// `appState.lastPolledAt`.
    private var entriesFetchedAt: Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return appState.fetchedAt(from: start, to: end)
    }

    private var daySummary: DaySummary {
        OvertimeCalculator.daySummary(
            date: selectedDate,
            entries: entries,
            settings: appState.settings,
            polledAt: entriesFetchedAt
        )
    }

    private var previousDaySummary: DaySummary {
        let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        return OvertimeCalculator.daySummary(
            date: previousDate,
            entries: previousDayEntries,
            settings: appState.settings
            // No polledAt – previous-day entries are historical; nothing is running there.
        )
    }

    private var projects: [ProjectSummary] {
        DashboardMetrics.projectHours(
            from: entries,
            polledAt: entriesFetchedAt,
            cutoff: appState.settings.reportStartDate
        )
    }

    private var previousProjects: [ProjectSummary] {
        DashboardMetrics.projectHours(from: previousDayEntries, polledAt: nil)
    }

    private var meetingHours: Double {
        DashboardMetrics.meetingHours(meetings: meetings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Date navigation
                dateNavigation

                // Smart Insights – shown when there are any
                SmartInsightsCard(insights: dailyInsights)

                // Progress + Stats row
                HStack(spacing: 16) {
                    progressRing
                    statsColumn
                }
                .frame(maxHeight: 180)

                // Project mix (stacked bar + per-project list)
                dayCompositionSection

                // Project trends – only when we have a previous-day baseline
                if !previousProjects.isEmpty || !projects.isEmpty {
                    projectTrendsSection
                }

                // Meetings
                if !meetings.isEmpty {
                    meetingsSection
                }

                // Entry list
                entryListSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadEntries() }
        .onChange(of: selectedDate) { _, _ in loadEntries() }
        .sheet(item: $meetingToLog) { meeting in
            MeetingEntrySheet(meeting: meeting, onDismiss: { meetingToLog = nil })
                .environmentObject(appState)
        }
    }

    // MARK: - Date Navigation

    private var dateNavigation: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previous day (⌘←)")
            .accessibilityLabel("Previous day")
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Spacer()

            VStack(spacing: 2) {
                Text(dayLabel)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(dateLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if !Calendar.current.isDateInToday(selectedDate) {
                    Button("Today") {
                        selectedDate = Date()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.harvestOrange)
                    .help("Jump to today (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)
                }

                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1)
                .help("Next day (⌘→)")
                .accessibilityLabel("Next day")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }

    // MARK: - Insights

    private var dailyInsights: [DashboardInsight] {
        var results: [DashboardInsight] = []

        // 1. vs yesterday
        if let change = DashboardMetrics.percentChange(
            current: daySummary.actual,
            previous: previousDaySummary.actual
        ) {
            let rounded = Int(change.rounded())
            if abs(rounded) >= 3 {
                let arrow = rounded > 0 ? "↑" : "↓"
                let color: Color = rounded > 0
                    ? Color(red: 0.20, green: 0.70, blue: 0.40)
                    : AppColor.harvestOrange
                results.append(DashboardInsight(
                    icon: rounded > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                    text: "\(arrow) \(abs(rounded))% hours vs yesterday (\(TimeFormat.clock(previousDaySummary.actual)))",
                    accent: color
                ))
            }
        } else if daySummary.actual > 0 && previousDaySummary.actual == 0 {
            // New activity after an idle day
            results.append(DashboardInsight(
                icon: "sparkles",
                text: "Fresh start – nothing logged yesterday",
                accent: AppColor.harvestOrange
            ))
        }

        // 2. Meeting load
        if !meetings.isEmpty {
            let mh = meetingHours
            if let pct = DashboardMetrics.meetingLoadPercent(
                meetingHours: mh,
                loggedHours: daySummary.actual
            ), pct > 10 {
                let roundedPct = Int(pct.rounded())
                results.append(DashboardInsight(
                    icon: "person.2.fill",
                    text: "\(roundedPct)% of today overlaps with \(meetings.count) meeting\(meetings.count == 1 ? "" : "s")",
                    accent: AppColor.meetingBlue
                ))
            } else if daySummary.actual < 0.1 && !meetings.isEmpty {
                // Pure meeting day with no logged work
                results.append(DashboardInsight(
                    icon: "person.2.fill",
                    text: "\(meetings.count) meeting\(meetings.count == 1 ? "" : "s") scheduled – no hours logged yet",
                    accent: AppColor.meetingBlue
                ))
            }
        }

        // 3. Top project of the day
        if let topProject = projects.first, topProject.hours > 0.25 {
            let share = daySummary.actual > 0 ? Int((topProject.hours / daySummary.actual * 100).rounded()) : 0
            if share > 60 {
                results.append(DashboardInsight(
                    icon: "target",
                    text: "Deep-focus day – \(share)% on \(topProject.name)",
                    accent: ProjectPalette.color(for: topProject.id)
                ))
            } else if projects.count >= 3 {
                results.append(DashboardInsight(
                    icon: "square.grid.2x2",
                    text: "Context-switched across \(projects.count) projects",
                    accent: AppColor.harvestOrange
                ))
            }
        }

        // 4. Holiday day
        if daySummary.holidayHours > 0 {
            results.append(DashboardInsight(
                icon: "sun.max.fill",
                text: "Holiday hours logged – \(TimeFormat.clock(daySummary.holidayHours))",
                accent: Color(red: 0.61, green: 0.35, blue: 0.71)
            ))
        }

        return results
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        let progress = daySummary.expected > 0
            ? min(daySummary.actual / daySummary.expected, 1.5)
            : 0
        let progressClamped = min(progress, 1.0)
        let isOver = daySummary.actual > daySummary.expected && daySummary.expected > 0
        let showProgress = daySummary.expected > 0

        return ZStack {
            // Background ring
            Circle()
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 12)

            if showProgress {
                // Progress ring – orange up to 100%
                Circle()
                    .trim(from: 0, to: progressClamped)
                    .stroke(
                        AppColor.harvestOrange,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progressClamped)

                // Overtime spillover ring – red beyond 100%
                if progress > 1.0 {
                    Circle()
                        .trim(from: 0, to: progress - 1.0)
                        .stroke(
                            AppColor.harvestRed.opacity(0.7),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            } else {
                // Non-working day: show a muted full ring
                Circle()
                    .stroke(Color(.separatorColor).opacity(0.15), lineWidth: 12)
            }

            // Center text – hero stat: hours logged today
            VStack(spacing: 2) {
                Text(TimeFormat.clock(daySummary.actual))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(showProgress ? "of \(TimeFormat.clock(daySummary.expected))" : "logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Overtime badge – only when there's a daily target set
                if isOver {
                    Text("+\(TimeFormat.clock(daySummary.delta))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.harvestRed)
                }
            }
        }
        .frame(width: 150, height: 150)
        .padding(10)
    }

    // MARK: - Stats Column

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Logged hours with vs-yesterday delta
            loggedRow

            // Entries with focus subtitle
            statRow(
                label: "Entries",
                value: "\(entries.count)",
                color: Color(red: 0.20, green: 0.60, blue: 0.86)
            )

            // Meeting load (only if meetings exist)
            if !meetings.isEmpty {
                statRow(
                    label: "Meetings",
                    value: TimeFormat.clock(meetingHours),
                    color: AppColor.meetingBlue
                )
            }

            if daySummary.holidayHours > 0 {
                statRow(
                    label: "Holiday",
                    value: TimeFormat.clock(daySummary.holidayHours),
                    color: Color(red: 0.61, green: 0.35, blue: 0.71)
                )
            }

            // vs Yesterday – only if there's a baseline
            if previousDaySummary.actual > 0.01 {
                vsYesterdayRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loggedRow: some View {
        HStack {
            Text("Logged")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(formatHours(daySummary.actual))
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private var vsYesterdayRow: some View {
        let delta = daySummary.actual - previousDaySummary.actual
        let isUp = delta > 0
        let color: Color = isUp
            ? Color(red: 0.20, green: 0.70, blue: 0.40)
            : AppColor.harvestOrange

        return HStack {
            Text("vs Yesterday")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(TimeFormat.signed(delta))
                .font(.callout)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .help("Yesterday: \(TimeFormat.clock(previousDaySummary.actual))")
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    // MARK: - Project Trends Section

    private var projectTrendsSection: some View {
        let trends = DashboardMetrics.projectTrends(current: projects, previous: previousProjects)
        return ProjectTrendsCard(
            trends: trends,
            comparisonLabel: "vs yesterday",
            maxRows: 5
        )
    }

    // MARK: - Project Mix Section

    private var dayCompositionSection: some View {
        let totalLogged = projects.reduce(0) { $0 + $1.hours }
        let target = daySummary.expected
        let isNonWorking = HolidayEngine.isNonWorkingDay(selectedDate, settings: appState.settings)

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Project Mix")
                    .font(.headline)

                Spacer()

                if target > 0 {
                    Text("\(TimeFormat.clock(totalLogged)) of \(TimeFormat.clock(target))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if totalLogged > 0 {
                    Text(TimeFormat.clock(totalLogged))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if entries.isEmpty && !isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: isNonWorking ? "moon.zzz.fill" : "clock")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text(isNonWorking ? "Non-working day" : "No entries for this day")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                // Stacked bar – reuses the shared ProjectCompositionBar
                ProjectCompositionBar(projects: projects, height: 32, showEmptyState: false)
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Meetings Section

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Meetings")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(meetings.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(TimeFormat.clock(meetingHours))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Click a meeting to log it as a time entry")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(meetings) { meeting in
                meetingRow(meeting)
                if meeting.id != meetings.last?.id {
                    Divider()
                }
            }
        }
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    @ViewBuilder
    private func meetingRow(_ meeting: CalendarEvent) -> some View {
        let hasMemory = appState.meetingMapper.savedDefault(for: meeting.subject) != nil

        Button {
            meetingToLog = meeting
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColor.meetingBlue)
                    .frame(width: 4, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.subject)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formatMeetingTimeRange(meeting))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if let location = meeting.location, !location.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if meeting.isOnlineMeeting {
                            Image(systemName: "video.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColor.meetingBlue)
                        }
                    }
                }

                Spacer()

                if hasMemory {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(AppColor.harvestOrange)
                        .help("Project remembered – click to save quickly")
                }

                Text("\(meeting.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppColor.harvestOrange)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Log this meeting as a time entry")
    }

    private func formatMeetingTimeRange(_ meeting: CalendarEvent) -> String {
        return "\(dailyMeetingTimeFormatter.string(from: meeting.start)) – \(dailyMeetingTimeFormatter.string(from: meeting.end))"
    }

    // MARK: - Entry List

    private var entryListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entries")
                .font(.headline)

            if entries.isEmpty && !isLoading {
                Text("No time entries")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    EntryRow(entry: entry)
                    if entry.id != entries.last?.id {
                        Divider()
                    }
                }
            }
        }
        // Stretch to the column width even when content is just the empty-
        // state line. Without this, an empty `Entries` card collapses to
        // the width of "No time entries" and looks like an orphan tile.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Data Loading

    private func loadEntries() {
        isLoading = true
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let prevStart = cal.date(byAdding: .day, value: -1, to: start) ?? start
        let prevEnd = start

        // Calendar events are local (EventKit) – no async needed
        meetings = appState.calendarService.getEvents(for: selectedDate)

        Task {
            async let current = appState.fetchEntries(from: start, to: end)
            async let previous = appState.fetchEntries(from: prevStart, to: prevEnd)

            entries = await current
            previousDayEntries = await previous
            isLoading = false
            appState.pendingExportPeriod = .daily(date: selectedDate, entries: entries, summary: daySummary)
        }
    }

    // MARK: - Helpers

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        return dailyWeekdayFormatter.string(from: selectedDate)
    }

    private var dateLabel: String {
        return dailyLongDateFormatter.string(from: selectedDate)
    }

    private func formatHours(_ hours: Double) -> String {
        let (h, m) = TimeFormat.hoursAndMinutes(hours)
        return String(format: "%dh %02dm", h, m)
    }

}
