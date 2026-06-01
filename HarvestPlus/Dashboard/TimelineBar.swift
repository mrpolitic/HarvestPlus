//
//  TimelineBar.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  A horizontal day timeline that lays out time entries and meetings against
//  the configured working hours, with the lunch gap marked. Used by the
//  Daily dashboard.
//

import SwiftUI

// MARK: - Timeline Bar

struct TimelineBar: View {
    let entries: [TimeEntry]
    let workStart: DateComponents
    let workEnd: DateComponents
    let lunchWindowStart: DateComponents?
    let lunchDuration: TimeInterval
    var meetings: [CalendarEvent] = []

    // Timeline range in minutes from midnight
    private var rangeStart: Int {
        let wsMin = (workStart.hour ?? 8) * 60 + (workStart.minute ?? 0)
        let earliestEntry = entries.compactMap { entryStartMinute($0) }.min() ?? wsMin
        let earliestMeeting = meetings.map(\.startMinuteOfDay).min() ?? wsMin
        let earliest = min(wsMin, min(earliestEntry, earliestMeeting))
        return (earliest / 60) * 60  // Round down to full hour
    }

    private var rangeEnd: Int {
        let weMin = (workEnd.hour ?? 16) * 60 + (workEnd.minute ?? 0)
        let latestEntry = entries.compactMap { entryEndMinute($0) }.max() ?? weMin
        let latestMeeting = meetings.map(\.endMinuteOfDay).max() ?? weMin
        let latest = min(max(weMin, max(latestEntry, latestMeeting)), 23 * 60 + 59)  // Cap at 23:59
        return ((latest / 60) + 1) * 60  // Round up to full hour (max 24:00)
    }

    private var totalMinutes: CGFloat {
        CGFloat(max(rangeEnd - rangeStart, 60))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            VStack(alignment: .leading, spacing: 0) {
                // Hour labels
                ZStack(alignment: .leading) {
                    ForEach(hourMarkers, id: \.self) { hour in
                        Text(String(format: "%d:00", hour))
                            .font(.system(size: 10))
                            // .secondary meets WCAG AA over the card surface;
                            // .tertiary was borderline on lighter themes.
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .position(
                                x: xPos(minute: hour * 60, width: width),
                                y: 8
                            )
                    }
                }
                .frame(height: 18)

                // Bar area
                ZStack(alignment: .leading) {
                    // Full background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.separatorColor).opacity(0.15))
                        .frame(height: 40)

                    // Work hours highlight
                    let wsMin = (workStart.hour ?? 8) * 60 + (workStart.minute ?? 0)
                    let weMin = (workEnd.hour ?? 16) * 60 + (workEnd.minute ?? 0)
                    let wxStart = xPos(minute: wsMin, width: width)
                    let wxEnd = xPos(minute: weMin, width: width)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.separatorColor).opacity(0.12))
                        .frame(width: max(0, wxEnd - wxStart), height: 40)
                        .offset(x: wxStart)

                    // Lunch overlay
                    if let lunch = lunchWindowStart, lunchDuration > 0 {
                        let lMin = (lunch.hour ?? 12) * 60 + (lunch.minute ?? 0)
                        let lEnd = lMin + Int(lunchDuration / 60)
                        let lxStart = xPos(minute: lMin, width: width)
                        let lxEnd = xPos(minute: lEnd, width: width)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.lunchBreak.opacity(0.4))
                            .frame(width: max(0, lxEnd - lxStart), height: 40)
                            .offset(x: lxStart)
                    }

                    // Meeting overlay blocks
                    ForEach(meetings) { meeting in
                        let mStart = meeting.startMinuteOfDay
                        let mEnd = meeting.endMinuteOfDay
                        let mx = xPos(minute: mStart, width: width)
                        let mw = max(4, xPos(minute: mEnd, width: width) - mx)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.meetingBlue.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(AppColor.meetingBlue.opacity(0.5), lineWidth: 1, antialiased: true)
                            )
                            .frame(width: mw, height: 40)
                            .offset(x: mx, y: 0)
                            .allowsHitTesting(false)
                            .help("\(meeting.subject) (\(formatMeetingTime(meeting)))")
                    }

                    // Entry blocks
                    ForEach(entries) { entry in
                        let sMin = entryStartMinute(entry) ?? 0
                        let eMin = entryEndMinute(entry) ?? sMin
                        let bx = xPos(minute: sMin, width: width)
                        let bw = max(4, xPos(minute: eMin, width: width) - bx)

                        RoundedRectangle(cornerRadius: 5)
                            .fill(projectColor(for: entry))
                            .frame(width: bw, height: 30)
                            .offset(x: bx, y: 0)
                            .help("\(entry.displayProjectName) / \(entry.task.name) – \(TimeFormat.clockExact(entry.hours))")
                    }

                    // "Now" indicator
                    if isToday {
                        let nowMin = currentMinuteOfDay
                        if nowMin >= rangeStart && nowMin <= rangeEnd {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: 48)
                                .offset(x: xPos(minute: nowMin, width: width) - 1, y: -4)
                        }
                    }
                }
                .frame(height: 40)

                // Hour tick marks
                ZStack(alignment: .leading) {
                    ForEach(hourMarkers, id: \.self) { hour in
                        Rectangle()
                            .fill(Color(.separatorColor).opacity(0.3))
                            .frame(width: 1, height: 6)
                            .position(
                                x: xPos(minute: hour * 60, width: width),
                                y: 3
                            )
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 64)

        // Gap warning
        if !gaps.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColor.harvestOrange)
                Text(gapSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Layout

    private func xPos(minute: Int, width: CGFloat) -> CGFloat {
        let fraction = CGFloat(minute - rangeStart) / totalMinutes
        return fraction * width
    }

    private var hourMarkers: [Int] {
        let first = rangeStart / 60
        let last = rangeEnd / 60
        return Array(first...last)
    }

    // MARK: - Entry Time Extraction

    private func entryStartMinute(_ entry: TimeEntry) -> Int? {
        if let started = entry.timerStartedAt {
            let cal = Calendar.current
            let h = cal.component(.hour, from: started)
            let m = cal.component(.minute, from: started)
            return h * 60 + m
        }
        // No start time – estimate by placing entries sequentially
        return estimateStartMinute(for: entry)
    }

    private func entryEndMinute(_ entry: TimeEntry) -> Int? {
        guard let startMin = entryStartMinute(entry) else { return nil }
        if entry.isRunning {
            return currentMinuteOfDay
        }
        return startMin + Int(entry.hours * 60)
    }

    /// For entries without timerStartedAt, estimate position from work start.
    private func estimateStartMinute(for target: TimeEntry) -> Int? {
        let wsMin = (workStart.hour ?? 8) * 60 + (workStart.minute ?? 0)
        var cursor = wsMin

        for entry in entries {
            if entry.id == target.id {
                return cursor
            }
            if entry.timerStartedAt != nil {
                if let s = entryStartMinuteFromTimer(entry) {
                    cursor = s + Int(entry.hours * 60)
                }
            } else {
                cursor += Int(entry.hours * 60)
            }
        }
        return cursor
    }

    private func entryStartMinuteFromTimer(_ entry: TimeEntry) -> Int? {
        guard let started = entry.timerStartedAt else { return nil }
        let cal = Calendar.current
        return cal.component(.hour, from: started) * 60 + cal.component(.minute, from: started)
    }

    // MARK: - Gaps

    private struct Gap {
        let startMin: Int
        let endMin: Int
        var duration: Int { endMin - startMin }
    }

    private var gaps: [Gap] {
        let wsMin = (workStart.hour ?? 8) * 60 + (workStart.minute ?? 0)
        let weMin = (workEnd.hour ?? 16) * 60 + (workEnd.minute ?? 0)

        var ranges: [(start: Int, end: Int)] = []
        for entry in entries {
            if let s = entryStartMinute(entry), let e = entryEndMinute(entry) {
                ranges.append((start: s, end: e))
            }
        }
        ranges.sort { $0.start < $1.start }

        var result: [Gap] = []
        var cursor = wsMin

        for range in ranges {
            let effectiveStart = max(range.start, wsMin)
            let effectiveEnd = min(range.end, weMin)
            if effectiveStart > cursor && (effectiveStart - cursor) > 5 {
                result.append(Gap(startMin: cursor, endMin: effectiveStart))
            }
            cursor = max(cursor, effectiveEnd)
        }

        let boundary = isToday ? min(currentMinuteOfDay, weMin) : weMin
        if cursor < boundary && (boundary - cursor) > 5 {
            result.append(Gap(startMin: cursor, endMin: boundary))
        }

        return result
    }

    private var gapSummary: String {
        let total = gaps.reduce(0) { $0 + $1.duration }
        if total < 60 {
            return "\(total) min untracked during work hours"
        }
        return "\(total / 60)h \(total % 60)m untracked during work hours"
    }

    // MARK: - Helpers

    private var isToday: Bool {
        guard let first = entries.first,
              let entryDate = OvertimeCalculator.parseSpentDate(first.spentDate) else {
            return true
        }
        return Calendar.current.isDateInToday(entryDate)
    }

    private var currentMinuteOfDay: Int {
        let cal = Calendar.current
        return cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
    }

    private func projectColor(for entry: TimeEntry) -> Color {
        ProjectPalette.color(for: entry.project.id)
    }


    private func formatMeetingTime(_ meeting: CalendarEvent) -> String {
        let startH = meeting.startMinuteOfDay / 60
        let startM = meeting.startMinuteOfDay % 60
        let endH = meeting.endMinuteOfDay / 60
        let endM = meeting.endMinuteOfDay % 60
        return String(format: "%d:%02d – %d:%02d", startH, startM, endH, endM)
    }
}
