//
//  AppSettings.swift
//  HarvestPlus
//
//  The user-configurable preferences struct (persisted to UserDefaults by
//  AppState and the Settings tabs), plus the small enums it references.
//  Extracted from AppState.swift.
//

import Foundation

struct AppSettings {
    // General
    var launchAtLogin: Bool = false
    var pollingInterval: TimeInterval = 60

    // Work Schedule
    var workSchedule: WorkSchedule = WorkSchedule()

    // Notifications
    var timerNudgeEnabled: Bool = true
    var bannerPosition: BannerPosition = .top
    var snoozeDuration: TimeInterval = 15 * 60  // 15 minutes
    var idleDetectionEnabled: Bool = true
    var idleThreshold: TimeInterval = 15 * 60
    var longTimerWarningEnabled: Bool = true
    var longTimerThreshold: TimeInterval = 3 * 60 * 60  // 3 hours
    var eodSummaryEnabled: Bool = true
    var eodSummaryTime: DateComponents = DateComponents(hour: 16, minute: 0)
    var eowSummaryEnabled: Bool = true
    var eowSummaryTime: DateComponents = DateComponents(hour: 16, minute: 0)
    var autoStopOnSleep: Bool = false

    // Integrations
    var harvestAccountId: String = ""

    // Holidays
    var holidayTaskNames: String = "Holiday, Holiday (feriefridag)"
    var holidayICSUrl: String = ""

    // Export
    var defaultExportFormat: ExportFormat = .pdf
    var pdfPaperSize: PaperSize = .a4
    /// When true (default), strips leading `[code]` prefixes (numeric or
    /// alphanumeric) from project names before display – Harvest projects
    /// are often named `[000025] Project Name` for billing/admin purposes,
    /// and the code adds noise when you just want to read project names.
    /// Replaced the earlier free-form-regex setting, which was un-fillable
    /// for non-technical users and (more embarrassingly) never actually
    /// consulted by `TimeEntry.displayProjectName`.
    var stripProjectPrefixCodes: Bool = true
    /// Cutoff date for reports and dashboards. Entries dated before this
    /// (by `spent_date`) are excluded from all summaries. Nil = no cutoff.
    /// Use case: the user tracked time wrong for months, wants to start
    /// computing reports from a clean date going forward, but doesn't
    /// want to (or can't) edit historical data in Harvest.
    var reportStartDate: Date? = nil
}

// MARK: - Settings Enums

enum BannerPosition: String, CaseIterable {
    case top = "Top"
    case bottom = "Bottom"
}

enum ExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case csv = "CSV"
}

enum PaperSize: String, CaseIterable {
    case a4 = "A4"
    case letter = "Letter"
}
