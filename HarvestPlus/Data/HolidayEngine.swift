//
//  HolidayEngine.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Computes non-working days – Danish public holidays (including the Easter
//  math), weekends, and the user's custom dates – behind a per-year cache.
//  The overtime calculator uses it to zero out targets on days off.
//

import Foundation

// MARK: - Holiday Engine

struct HolidayEngine {

    // MARK: - Cache

    /// Cached non-working date keys per year ("yyyy-MM-dd" → Set lookup).
    /// Built once per year on first access; avoids repeated UserDefaults reads,
    /// Easter computations, and ISO-8601 parsing on every isNonWorkingDay() call.
    private static var nonWorkingDaysCache: [Int: Set<String>] = [:]

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Invalidate the non-working days cache (call when holiday settings change).
    static func invalidateCache() {
        nonWorkingDaysCache.removeAll()
    }

    /// Build or retrieve the set of non-working date keys for a given year.
    /// On cache miss: reads UserDefaults once, computes holidays once, caches the result.
    /// On cache hit: returns immediately (O(1)).
    private static func nonWorkingDateKeys(year: Int) -> Set<String> {
        if let cached = nonWorkingDaysCache[year] {
            return cached
        }

        // --- Cache miss: build the set ---

        let disabledNames = UserDefaults.standard.stringArray(forKey: "disabledHolidays") ?? []
        let customDateStrings = UserDefaults.standard.stringArray(forKey: "customNonWorkingDates") ?? []

        var days = Set<String>()

        // Public holidays for this year
        for holiday in danishHolidays(year: year) where !disabledNames.contains(holiday.name) {
            days.insert(dateKeyFormatter.string(from: holiday.date))
        }

        // Custom non-working dates (all years – keyed by yyyy-MM-dd so only matching years hit)
        let isoFormatter = ISO8601DateFormatter()
        for dateStr in customDateStrings {
            if let date = isoFormatter.date(from: dateStr) {
                days.insert(dateKeyFormatter.string(from: date))
            }
        }

        nonWorkingDaysCache[year] = days
        return days
    }

    // MARK: - Public Holidays

    /// Returns all Danish public holidays for the given year.
    static func danishHolidays(year: Int) -> [HolidayItem] {
        let cal = Calendar.current
        let easter = computeEaster(year: year)

        func date(_ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day))!
        }

        func easterOffset(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: days, to: easter)!
        }

        return [
            HolidayItem(name: "New Year's Day", date: date(1, 1), isEnabled: true),
            HolidayItem(name: "Maundy Thursday", date: easterOffset(-3), isEnabled: true),
            HolidayItem(name: "Good Friday", date: easterOffset(-2), isEnabled: true),
            HolidayItem(name: "Easter Sunday", date: easter, isEnabled: true),
            HolidayItem(name: "Easter Monday", date: easterOffset(1), isEnabled: true),
            HolidayItem(name: "Ascension Day", date: easterOffset(39), isEnabled: true),
            HolidayItem(name: "Whit Sunday", date: easterOffset(49), isEnabled: true),
            HolidayItem(name: "Whit Monday", date: easterOffset(50), isEnabled: true),
            HolidayItem(name: "Constitution Day", date: date(6, 5), isEnabled: true),
            HolidayItem(name: "Christmas Eve", date: date(12, 24), isEnabled: true),
            HolidayItem(name: "Christmas Day", date: date(12, 25), isEnabled: true),
            HolidayItem(name: "2nd Christmas Day", date: date(12, 26), isEnabled: true),
            HolidayItem(name: "New Year's Eve", date: date(12, 31), isEnabled: true),
        ]
    }

    // MARK: - Non-Working Day Check

    /// Returns true if the given date is a non-working day (weekend, holiday, or custom date).
    /// Uses a per-year cache so repeated calls (e.g. 365 days) only compute once.
    static func isNonWorkingDay(_ date: Date, settings: AppSettings) -> Bool {
        // Weekend – check via daily target (no I/O, instant)
        if settings.workSchedule.dailyTarget(for: date) == 0 { return true }

        // Holiday / custom date – cached set lookup
        let year = Calendar.current.component(.year, from: date)
        let days = nonWorkingDateKeys(year: year)
        let key = dateKeyFormatter.string(from: date)
        return days.contains(key)
    }

    /// Returns the expected work hours for a given date, accounting for holidays.
    static func expectedHours(for date: Date, settings: AppSettings) -> Double {
        if isNonWorkingDay(date, settings: settings) {
            return 0
        }
        return settings.workSchedule.dailyTarget(for: date)
    }

    // MARK: - Holiday Task Detection

    /// Returns true if the given task name matches one of the configured holiday task names.
    static func isHolidayTask(taskName: String, settings: AppSettings) -> Bool {
        let names = settings.holidayTaskNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return names.contains(taskName.lowercased())
    }

    // MARK: - Computus (Easter Calculation)

    /// Anonymous Gregorian Easter algorithm.
    static func computeEaster(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1

        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
