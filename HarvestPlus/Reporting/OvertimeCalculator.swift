//
//  OvertimeCalculator.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The summary model types (Day / Week / Month) and the logic that turns raw
//  entries + the work schedule + holidays into expected-vs-actual hours and
//  overtime deltas. The dashboards and the report exporter consume these.
//

import Foundation

// MARK: - Day Summary

struct DaySummary: Identifiable {
    let id = UUID()
    let date: Date
    let expected: Double         // Target hours for this day
    let actual: Double           // Hours logged in Harvest
    let holidayHours: Double     // Hours logged under holiday tasks
    let isNonWorkingDay: Bool    // Weekend / holiday / custom
    var delta: Double {          // actual - expected (positive = overtime)
        actual - expected
    }
}

// MARK: - Week Summary

struct WeekSummary: Identifiable {
    let id = UUID()
    let weekNumber: Int
    let year: Int
    let startDate: Date
    let endDate: Date
    let days: [DaySummary]

    var expectedTotal: Double { days.reduce(0) { $0 + $1.expected } }
    var actualTotal: Double { days.reduce(0) { $0 + $1.actual } }
    var delta: Double { actualTotal - expectedTotal }
}

// MARK: - Month Summary

struct MonthSummary: Identifiable {
    let id = UUID()
    let month: Int
    let year: Int
    let weeks: [WeekSummary]

    var expectedTotal: Double { weeks.reduce(0) { $0 + $1.expectedTotal } }
    var actualTotal: Double { weeks.reduce(0) { $0 + $1.actualTotal } }
    var delta: Double { actualTotal - expectedTotal }
}

// MARK: - Overtime Calculator

struct OvertimeCalculator {

    // MARK: - Daily Calculation

    /// Build a day summary for a single date.
    static func daySummary(
        date: Date,
        entries: [TimeEntry],
        settings: AppSettings,
        polledAt: Date? = nil
    ) -> DaySummary {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)

        // Honor the user-configurable "report start date" cutoff: days
        // strictly before that cutoff get a zeroed-out summary so they
        // don't pull the running totals around.
        if let cutoff = settings.reportStartDate,
           startOfDay < cal.startOfDay(for: cutoff) {
            return DaySummary(
                date: startOfDay,
                expected: 0,
                actual: 0,
                holidayHours: 0,
                isNonWorkingDay: HolidayEngine.isNonWorkingDay(date, settings: settings)
            )
        }

        // Filter entries for this day
        let dayEntries = entries.filter { entry in
            guard let entryDate = Self.parseSpentDate(entry.spentDate) else { return false }
            return cal.isDate(entryDate, inSameDayAs: startOfDay)
        }

        let isNonWorking = HolidayEngine.isNonWorkingDay(date, settings: settings)
        let expected = isNonWorking ? 0 : settings.workSchedule.dailyTarget(for: date)

        // Sum all hours, extrapolating the running timer's live elapsed
        // from `polledAt` (see TimeEntry.liveHours – fixes the 2× bug).
        let now = Date()
        var totalHours: Double = 0
        var holidayHours: Double = 0

        for entry in dayEntries {
            let hours = entry.liveHours(now: now, polledAt: polledAt)
            totalHours += hours

            if HolidayEngine.isHolidayTask(taskName: entry.task.name, settings: settings) {
                holidayHours += hours
            }
        }

        return DaySummary(
            date: startOfDay,
            expected: expected,
            actual: totalHours,
            holidayHours: holidayHours,
            isNonWorkingDay: isNonWorking
        )
    }

    // MARK: - Batch Daily Calculation

    /// Build day summaries for a date range in a single pass (O(entries + days) instead of O(entries × days)).
    static func daySummaries(
        from startDate: Date,
        to endDate: Date,
        entries: [TimeEntry],
        settings: AppSettings,
        polledAt: Date? = nil
    ) -> [DaySummary] {
        let cal = Calendar.current

        // Pre-group entries by "yyyy-MM-dd" key in a single pass
        var grouped: [String: [TimeEntry]] = [:]
        for entry in entries {
            grouped[entry.spentDate, default: []].append(entry)
        }

        var results: [DaySummary] = []
        var current = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        let now = Date()
        let cutoffDay = settings.reportStartDate.map { cal.startOfDay(for: $0) }

        while current <= end {
            let key = spentDateFormatter.string(from: current)
            let dayEntries = grouped[key] ?? []

            let isNonWorking = HolidayEngine.isNonWorkingDay(current, settings: settings)
            let isBeforeCutoff = cutoffDay.map { current < $0 } ?? false

            // Pre-cutoff days are still appended (so charts keep their full
            // date axis) but contribute nothing: expected, actual, holiday
            // all zero so they don't drag totals or deltas around.
            let expected: Double = (isBeforeCutoff || isNonWorking)
                ? 0
                : settings.workSchedule.dailyTarget(for: current)

            var totalHours: Double = 0
            var holidayHours: Double = 0

            if !isBeforeCutoff {
                for entry in dayEntries {
                    let hours = entry.liveHours(now: now, polledAt: polledAt)
                    totalHours += hours
                    if HolidayEngine.isHolidayTask(taskName: entry.task.name, settings: settings) {
                        holidayHours += hours
                    }
                }
            }

            results.append(DaySummary(
                date: current,
                expected: expected,
                actual: totalHours,
                holidayHours: holidayHours,
                isNonWorkingDay: isNonWorking
            ))

            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return results
    }

    // MARK: - Weekly Calculation

    /// Build a week summary for the ISO week containing the given date.
    static func weekSummary(
        containing date: Date,
        entries: [TimeEntry],
        settings: AppSettings,
        polledAt: Date? = nil
    ) -> WeekSummary {
        let cal = Calendar(identifier: .iso8601)
        let weekNumber = cal.component(.weekOfYear, from: date)
        let year = cal.component(.yearForWeekOfYear, from: date)

        // Get Monday of this week. If calendar math fails on an exotic input,
        // fall back to `startOfDay(for: date)` – caller still gets a valid
        // WeekSummary instead of a crash.
        let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? cal.startOfDay(for: date)
        let days = (0..<7).compactMap { offset -> DaySummary? in
            guard let day = cal.date(byAdding: .day, value: offset, to: monday) else { return nil }
            return daySummary(date: day, entries: entries, settings: settings, polledAt: polledAt)
        }

        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday

        return WeekSummary(
            weekNumber: weekNumber,
            year: year,
            startDate: monday,
            endDate: sunday,
            days: days
        )
    }

    /// Build week summaries for a date range.
    static func weekSummaries(
        from startDate: Date,
        to endDate: Date,
        entries: [TimeEntry],
        settings: AppSettings,
        polledAt: Date? = nil
    ) -> [WeekSummary] {
        let cal = Calendar(identifier: .iso8601)
        var weeks: [WeekSummary] = []
        guard var currentMonday = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
        ) else {
            return []
        }

        // Hard-cap the loop. Normally the `<=` check terminates, but if
        // `byAdding:` ever returned the same date (bad calendar config) we'd
        // spin forever. 520 weeks = ~10 years – well above any real range.
        var safetyCounter = 0
        while currentMonday <= endDate && safetyCounter < 520 {
            let summary = weekSummary(containing: currentMonday, entries: entries, settings: settings, polledAt: polledAt)
            weeks.append(summary)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: currentMonday) else { break }
            currentMonday = next
            safetyCounter += 1
        }

        return weeks
    }

    // MARK: - Monthly Calculation

    /// Build a month summary for the given month/year.
    static func monthSummary(
        month: Int,
        year: Int,
        entries: [TimeEntry],
        settings: AppSettings,
        polledAt: Date? = nil
    ) -> MonthSummary {
        let cal = Calendar(identifier: .iso8601)
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              let lastOfMonth = cal.date(from: DateComponents(year: year, month: month, day: range.count))
        else {
            return MonthSummary(month: month, year: year, weeks: [])
        }

        let weeks = weekSummaries(from: firstOfMonth, to: lastOfMonth, entries: entries, settings: settings, polledAt: polledAt)

        return MonthSummary(
            month: month,
            year: year,
            weeks: weeks
        )
    }

    // MARK: - Cumulative Overtime

    /// Calculate cumulative overtime from a start date to an end date.
    /// Returns an array of (date, cumulativeOvertime) tuples.
    static func cumulativeOvertime(
        from startDate: Date,
        to endDate: Date,
        entries: [TimeEntry],
        settings: AppSettings
    ) -> [(date: Date, cumulative: Double)] {
        let days = daySummaries(from: startDate, to: endDate, entries: entries, settings: settings)
        var cumulative: Double = 0
        return days.map { day in
            cumulative += day.delta
            return (date: day.date, cumulative: cumulative)
        }
    }

    /// Cumulative overtime from pre-computed day summaries (avoids recomputation).
    static func cumulativeOvertime(
        from daySummaries: [DaySummary]
    ) -> [(date: Date, cumulative: Double)] {
        var cumulative: Double = 0
        return daySummaries.map { day in
            cumulative += day.delta
            return (date: day.date, cumulative: cumulative)
        }
    }

    /// Cumulative pace curve for the Pace chart. Identical to `cumulativeOvertime`
    /// except the *current in-progress day* has its expected hours prorated to
    /// the fraction of the workday that has elapsed. Without this, a mid-morning
    /// reader sees their pace drop by the full daily target every day and reads
    /// as "undertime" even when perfectly on schedule.
    static func cumulativePace(
        from daySummaries: [DaySummary],
        asOf now: Date = Date(),
        schedule: WorkSchedule
    ) -> [(date: Date, cumulative: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var cumulative: Double = 0
        return daySummaries.map { day in
            let delta: Double
            if cal.startOfDay(for: day.date) == today && !day.isNonWorkingDay {
                let fullTarget = schedule.dailyTarget(for: day.date)
                let fraction = workdayElapsedFraction(now: now, schedule: schedule)
                delta = day.actual - fullTarget * fraction
            } else {
                delta = day.delta
            }
            cumulative += delta
            return (date: day.date, cumulative: cumulative)
        }
    }

    /// Fraction of today's configured workday window (start→end) that has elapsed.
    /// Clamped to [0, 1]. Before the workday starts → 0; after it ends → 1.
    private static func workdayElapsedFraction(now: Date, schedule: WorkSchedule) -> Double {
        let cal = Calendar.current
        let startMinutes = (schedule.workStartTime.hour ?? 8) * 60 + (schedule.workStartTime.minute ?? 0)
        let endMinutes = (schedule.workEndTime.hour ?? 16) * 60 + (schedule.workEndTime.minute ?? 0)
        let span = endMinutes - startMinutes
        guard span > 0 else { return 1.0 }
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let elapsed = max(0, min(span, nowMinutes - startMinutes))
        return Double(elapsed) / Double(span)
    }

    // MARK: - Batch Week/Month from Pre-Computed Days

    /// Build week summaries from pre-computed day summaries (avoids recomputation).
    /// Groups days by ISO week and creates one WeekSummary per group.
    static func weekSummaries(from daySummaries: [DaySummary]) -> [WeekSummary] {
        guard !daySummaries.isEmpty else { return [] }
        let cal = Calendar(identifier: .iso8601)

        // Group days by ISO week key (yearForWeek * 100 + weekNumber)
        var grouped: [Int: [DaySummary]] = [:]
        for day in daySummaries {
            let weekNum = cal.component(.weekOfYear, from: day.date)
            let yearForWeek = cal.component(.yearForWeekOfYear, from: day.date)
            let key = yearForWeek * 100 + weekNum
            grouped[key, default: []].append(day)
        }

        return grouped.compactMap { key, days -> WeekSummary? in
            let sortedDays = days.sorted { $0.date < $1.date }
            let yearForWeek = key / 100
            let weekNum = key % 100
            // If calendar math fails (pathological ISO week key), fall back to
            // the first day we actually have – better than dropping the week.
            let monday = cal.date(from: DateComponents(weekOfYear: weekNum, yearForWeekOfYear: yearForWeek))
                ?? sortedDays.first?.date
                ?? Date()
            let sunday = cal.date(byAdding: .day, value: 6, to: monday)
                ?? sortedDays.last?.date
                ?? monday
            return WeekSummary(
                weekNumber: weekNum,
                year: yearForWeek,
                startDate: monday,
                endDate: sunday,
                days: sortedDays
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Helpers

    private static let spentDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Pin to the local time zone (the default, made explicit): `spent_date`
        // is a calendar day, and every other parser of it (DashboardMetrics,
        // day/week grouping) compares against Calendar.current – they must agree.
        f.timeZone = .current
        return f
    }()

    static func parseSpentDate(_ string: String) -> Date? {
        spentDateFormatter.date(from: string)
    }
}
