//
//  PopoverView.swift
//  HarvestPlus
//
//  Menu bar popover. HarvestPlus is a companion to Harvest — it mirrors the
//  timer state and lets you stop a running timer, log meetings, and review
//  your day — but it does NOT create new time entries from scratch. For that,
//  users open Harvest itself.
//
//  Layout:
//    - Header (Today + date + running pill)
//    - Today hero — primary action: tap to open the Dashboard (⌘D)
//    - Active timer card (with stop control) OR an "Open Harvest" CTA when idle
//    - Logged today (read-only, collapsible)
//    - Meetings today (clickable → log as time entry, the one allowed creation path)
//    - Bottom row (Settings / Quit)
//

import AppKit
import SwiftUI
import Combine

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let popoverHeaderDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMM"
    return f
}()

private let popoverMeetingTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

// MARK: - Popover View

struct PopoverView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    // UI state
    @State private var showAllMeetings: Bool = false
    @State private var showAllTodayEntries: Bool = false
    @State private var isHeroHovered: Bool = false

    // Auto-refresh meetings (and trigger other time-sensitive UI) periodically.
    // Subscribed only while the popover is visible to avoid pointless wake-ups
    // when the menu bar popup is closed.
    @State private var meetingsRefreshCancellable: AnyCancellable?

    private let popoverWidth: CGFloat = 380
    private let sectionSpacing: CGFloat = 14
    private let horizontalPadding: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)

            todayHero
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, sectionSpacing)

            timerCard
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, sectionSpacing)

            if !appState.todayEntries.isEmpty {
                todayEntriesSection
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, sectionSpacing)
            }

            if !todaysMeetings.isEmpty {
                meetingsSection
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, sectionSpacing)
            }

            bottomRow
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .frame(width: popoverWidth)
        .alert("Error", isPresented: Binding(
            get: { appState.actionError != nil },
            set: { if !$0 { appState.actionError = nil } }
        )) {
            Button("OK") { appState.actionError = nil }
        } message: {
            Text(appState.actionError ?? "")
        }
        .onAppear {
            appState.refreshTodayMeetings()
            // Start periodic refresh only while popover is visible.
            meetingsRefreshCancellable = Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    appState.refreshTodayMeetings()
                }
        }
        .onDisappear {
            meetingsRefreshCancellable?.cancel()
            meetingsRefreshCancellable = nil
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .font(.headline)
                Text(headerDateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Running-timer pill (if any)
            if case .running = appState.timerState {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColor.harvestOrange)
                        .frame(width: 6, height: 6)
                    Text("Timer running")
                        .font(.caption)
                        .foregroundStyle(AppColor.harvestOrange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(AppColor.harvestOrange.opacity(0.12))
                )
            }
        }
    }

    private var headerDateString: String {
        return popoverHeaderDateFormatter.string(from: Date())
    }

    // MARK: - Today Hero (primary Dashboard button)

    /// The hero card is the product's primary action: your day at a glance,
    /// click-through to the full reporting dashboard. Reporting is what
    /// HarvestPlus is for, so it earns the visual weight here.
    private var todayHero: some View {
        Button {
            openWindow(id: "dashboard")
            activateApp()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatHours(appState.todayTotalHours))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    if appState.todayTarget > 0 {
                        Text("/ \(formatHours(appState.todayTarget))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    if appState.todayTarget > 0 {
                        overtimeBadge
                    }
                }

                progressBar

                HStack(alignment: .center, spacing: 6) {
                    Text(progressStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Primary CTA label — matches a standard button size so the hero
                    // reads unambiguously as "click here to see the full report".
                    HStack(spacing: 4) {
                        Text("View Dashboard")
                            .font(.callout)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .offset(x: isHeroHovered ? 3 : 0)
                    }
                    .foregroundStyle(AppColor.harvestOrange)
                }
            }
            .padding(AppSpacing.md)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColor.harvestOrange.opacity(isHeroHovered ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .strokeBorder(
                        AppColor.harvestOrange.opacity(isHeroHovered ? 0.65 : 0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHeroHovered = hovering
            }
        }
        .keyboardShortcut("d", modifiers: .command)
        .help("Open full dashboard (⌘D)")
    }

    private var overtimeBadge: some View {
        let delta = appState.todayDelta
        return Group {
            if delta >= 0 && appState.todayTotalHours >= appState.todayTarget {
                Text("+\(formatDelta(delta))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.harvestRed)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppColor.harvestRed.opacity(0.15))
                    )
            } else {
                Text(formatDelta(delta))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.separatorColor).opacity(0.3))
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 5)
                    .fill(progressColor)
                    .frame(
                        width: max(0, geometry.size.width * min(appState.todayProgress, 1.0)),
                        height: 10
                    )

                // Overtime spillover
                if appState.todayTotalHours > appState.todayTarget && appState.todayTarget > 0 {
                    let overtimeRatio = min(
                        (appState.todayTotalHours - appState.todayTarget) / appState.todayTarget,
                        0.5
                    )
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColor.harvestRed.opacity(0.5))
                        .frame(
                            width: max(0, geometry.size.width * overtimeRatio),
                            height: 10
                        )
                        .offset(x: geometry.size.width)
                }
            }
        }
        .frame(height: 10)
    }

    private var progressColor: Color {
        if appState.todayTarget <= 0 { return AppColor.harvestOrange }
        if appState.todayTotalHours >= appState.todayTarget {
            return AppColor.harvestOrange
        }
        let progress = appState.todayProgress
        if progress >= 0.5 {
            return AppColor.harvestOrange
        }
        return AppColor.harvestRed
    }

    private var progressStatusText: String {
        if appState.todayTarget <= 0 {
            return "Non-working day"
        }
        let delta = appState.todayDelta
        if delta >= 0 {
            return "Day complete"
        }
        return "\(formatDelta(delta)) to go"
    }

    // MARK: - Timer Card

    @ViewBuilder
    private var timerCard: some View {
        if let entry = appState.currentRunningEntry {
            runningTimerCard(entry)
        } else {
            idleOpenHarvestCard
        }
    }

    /// Compact card shown while a timer is running in Harvest — lets the user see it and stop it here.
    private func runningTimerCard(_ entry: TimeEntry) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppColor.harvestOrange)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayProjectName)
                    .font(.headline)
                    .lineLimit(1)

                Text(entry.task.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ElapsedTimeView(startedAt: entry.timerStartedAt, baseHours: entry.hours)

            Button {
                Task { await appState.stopCurrentTimer() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.harvestOrange)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop timer")
            .accessibilityLabel("Stop timer")
        }
        .padding(AppSpacing.md - 2)
        .harvestSurface(cornerRadius: AppRadius.sm)
    }

    /// Idle state — HarvestPlus doesn't create entries. Nudge the user to Harvest for that.
    private var idleOpenHarvestCard: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(.separatorColor))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("No timer running")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Start one in Harvest to see it here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Plain text link — secondary, utility-style. The external-link arrow
            // (vs the hero's drill-in chevron) signals this leaves HarvestPlus.
            Button {
                Self.openHarvestApp()
            } label: {
                HStack(spacing: 4) {
                    Text("Open Harvest")
                        .font(.callout)
                        .fontWeight(.medium)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(AppColor.harvestOrange)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Harvest to start a timer")
        }
        .padding(AppSpacing.md - 2)
        .harvestSurface(cornerRadius: AppRadius.sm)
    }

    /// Bring Harvest's menu-bar app to the front, or launch it if not running.
    static func openHarvestApp() {
        if let harvestApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.getharvest.harvestxapp"
        ).first {
            harvestApp.activate()
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Harvest.app"))
        }
    }

    // MARK: - Logged Today

    private var visibleTodayEntries: [TimeEntry] {
        let sorted = appState.todayEntries.sorted { lhs, rhs in
            // Running last, otherwise by higher hours first (rough recency signal)
            if lhs.isRunning && !rhs.isRunning { return false }
            if !lhs.isRunning && rhs.isRunning { return true }
            return lhs.hours > rhs.hours
        }
        if showAllTodayEntries {
            return sorted
        }
        return Array(sorted.prefix(3))
    }

    private var todayEntriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Logged today")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(appState.todayEntries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color(.separatorColor).opacity(0.3))
                    )

                Spacer()

                if appState.todayEntries.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAllTodayEntries.toggle()
                        }
                    } label: {
                        Text(showAllTodayEntries ? "Show less" : "Show all")
                            .font(.caption)
                            .foregroundStyle(AppColor.harvestOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(visibleTodayEntries) { entry in
                todayEntryRow(entry)
            }
        }
    }

    @ViewBuilder
    private func todayEntryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ProjectPalette.color(for: entry.project.id))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.task.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.displayProjectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if entry.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColor.harvestOrange)
                        .frame(width: 5, height: 5)
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(AppColor.harvestOrange)
                }
            } else {
                Text(formatEntryHours(entry.hours))
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }

    private func formatEntryHours(_ hours: Double) -> String {
        if hours < 0.01 { return "0m" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return String(format: "%dh %02dm", h, m)
    }

    // MARK: - Meetings

    private var todaysMeetings: [CalendarEvent] {
        appState.todayMeetings
    }

    private var visibleMeetings: [CalendarEvent] {
        if showAllMeetings {
            return todaysMeetings
        }
        return Array(todaysMeetings.prefix(3))
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Meetings today")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(todaysMeetings.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color(.separatorColor).opacity(0.3))
                    )

                Spacer()

                Button {
                    appState.refreshTodayMeetings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh meetings")
                .accessibilityLabel("Refresh meetings")

                if todaysMeetings.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAllMeetings.toggle()
                        }
                    } label: {
                        Text(showAllMeetings ? "Show less" : "Show all")
                            .font(.caption)
                            .foregroundStyle(AppColor.harvestOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(visibleMeetings) { meeting in
                meetingRow(meeting)
            }
        }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: CalendarEvent) -> some View {
        let isPast = meeting.end < Date()
        let hasMemory = appState.meetingMapper.savedDefault(for: meeting.subject) != nil

        Button {
            appState.pendingMeetingEntry = meeting
            openWindow(id: "meeting-entry")
            activateApp()
        } label: {
            HStack(spacing: 8) {
                Text(formatMeetingTime(meeting.start))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .leading)

                Text(meeting.subject)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasMemory {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(AppColor.harvestOrange)
                        .help("Project remembered — click to save quickly")
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppColor.harvestOrange)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .opacity(isPast ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .help("Log this meeting as a time entry")
    }

    private func formatMeetingTime(_ date: Date) -> String {
        return popoverMeetingTimeFormatter.string(from: date)
    }

    // MARK: - Bottom Row

    /// Secondary actions only. The primary action (Dashboard) lives in the hero.
    private var bottomRow: some View {
        HStack(spacing: 10) {
            SettingsLink {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.callout)
                    Text("Settings")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Open settings (⌘,)")
            // SettingsLink opens the scene but doesn't activate a LSUIElement
            // app — without this, the window lands behind Xcode/Finder/etc.
            .simultaneousGesture(TapGesture().onEnded { activateApp() })

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit HarvestPlus (⌘Q)")
        }
    }

    // MARK: - Activation

    /// Bring the app forward after opening a window from the menu-bar popover.
    /// HarvestPlus is `LSUIElement = YES`, so `openWindow(id:)` creates the
    /// window but doesn't activate the app — meaning the new window lands
    /// behind whatever was frontmost. This forces focus to the freshly-opened
    /// window.
    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Formatting

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 {
            return "\(h)h"
        }
        return String(format: "%dh %02dm", h, m)
    }

    private func formatDelta(_ hours: Double) -> String {
        let abs = abs(hours)
        let h = Int(abs)
        let m = Int((abs - Double(h)) * 60)
        let sign = hours < 0 ? "-" : ""
        if h == 0 {
            return String(format: "%@%dm", sign, m)
        }
        return String(format: "%@%dh %02dm", sign, h, m)
    }
}

// MARK: - Elapsed Time View

struct ElapsedTimeView: View {
    let startedAt: Date?
    let baseHours: Double

    @State private var now = Date()
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        Text(formattedElapsed)
            .font(.title2)
            .monospacedDigit()
            .onAppear {
                // Only subscribe while the view is in the hierarchy. Stops
                // the 1 Hz tick when the popover is closed, preventing
                // needless view-body re-evaluation.
                timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { date in
                        now = date
                    }
            }
            .onDisappear {
                timerCancellable?.cancel()
                timerCancellable = nil
            }
    }

    private var formattedElapsed: String {
        var totalSeconds = Int(baseHours * 3600)
        if let started = startedAt {
            totalSeconds += Int(now.timeIntervalSince(started))
        }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
