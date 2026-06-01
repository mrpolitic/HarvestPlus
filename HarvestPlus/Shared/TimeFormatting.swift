//
//  TimeFormatting.swift
//  HarvestPlus
//
//  Shared time/duration formatting. These helpers used to be copy-pasted
//  across the dashboard views – `formatHoursCompact` in five files,
//  `formatHoursSigned` in three, `formatDays` in three, `formatDuration`
//  in two. They're centralized here as `TimeFormat`.
//
//  The methods have distinct names on purpose: the app genuinely renders
//  hours in a few different styles ("H:MM" vs "Xh YYm", with/without a
//  minute component), and collapsing them would silently change on-screen
//  output. Each method preserves the exact behavior of the duplicates it
//  replaced. (Single-use, view-specific formatters – e.g. the popover's
//  "Xh YYm" elapsed style or a dashboard's weekday labels – deliberately
//  stay private to their view, but they share `hoursAndMinutes` below for
//  the decimal-hours → (h, m) math so rounding stays consistent.)
//

import Foundation

enum TimeFormat {

    /// Splits decimal hours into whole hours + minutes, **rounded to the
    /// nearest minute** (not truncated). Rounding at the total-minute level
    /// is what makes a day total line up with Harvest: decomposing the value
    /// and truncating each component rendered e.g. 5.4833h as "5:28", because
    /// 0.4833 × 60 = 28.9999 floored to 28 instead of rounding to 29. The
    /// returned `minutes` is always 0...59; the value is treated as a
    /// magnitude (sign is the caller's job – re-apply it after).
    static func hoursAndMinutes(_ hours: Double) -> (hours: Int, minutes: Int) {
        let totalMinutes = Int((Swift.abs(hours) * 60).rounded())
        return (totalMinutes / 60, totalMinutes % 60)
    }

    /// "H:MM", collapsing to "Xh" when there's no trailing minute
    /// (7.5 → "7:30", 8.0 → "8h"). The everyday dashboard hours style.
    static func clock(_ hours: Double) -> String {
        let (h, m) = hoursAndMinutes(hours)
        if m == 0 { return "\(h)h" }
        return String(format: "%d:%02d", h, m)
    }

    /// "H:MM" always, including a ":00" minute (7.0 → "7:00"). Used for
    /// discrete entry / meeting durations, where the colon reads as a span.
    static func clockExact(_ hours: Double) -> String {
        let (h, m) = hoursAndMinutes(hours)
        return String(format: "%d:%02d", h, m)
    }

    /// Signed "±Xh YYm" for overtime/undertime deltas; always shows a sign
    /// (+1h 30m / -0h 45m).
    static func signed(_ hours: Double) -> String {
        let sign = hours >= 0 ? "+" : "-"
        let (h, m) = hoursAndMinutes(hours)
        return String(format: "%@%dh %02dm", sign, h, m)
    }

    /// Whole/fractional days to one decimal, singular-aware
    /// (1 → "1 day", 2.5 → "2.5 days"). Used for the time-off tiles.
    static func days(_ days: Double) -> String {
        let rounded = (days * 10).rounded() / 10
        if rounded == 1 { return "1 day" }
        return String(format: "%.1f days", rounded)
    }
}
