//
//  AppState.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import SwiftUI
import Combine

// MARK: - Timer State

enum TimerState: Equatable {
    case running(TimeEntry)
    case stopped
    case offline

    static func == (lhs: TimerState, rhs: TimerState) -> Bool {
        switch (lhs, rhs) {
        case (.running(let a), .running(let b)):
            return a.id == b.id
        case (.stopped, .stopped):
            return true
        case (.offline, .offline):
            return true
        default:
            return false
        }
    }
}

// MARK: - Work Schedule

struct WorkSchedule {
    var workStartTime: DateComponents = DateComponents(hour: 8, minute: 0)
    var workEndTime: DateComponents = DateComponents(hour: 16, minute: 0)

    // Per-day targets (Calendar weekday: 1=Sun, 2=Mon, ..., 7=Sat)
    var targetMon: Double = 7.5
    var targetTue: Double = 7.5
    var targetWed: Double = 7.5
    var targetThu: Double = 7.5
    var targetFri: Double = 7.0
    var targetSat: Double = 0.0
    var targetSun: Double = 0.0

    // Kept for backward compatibility with older persistence
    var dailyTargetMonThu: Double {
        get { targetMon }
        set { targetMon = newValue; targetTue = newValue; targetWed = newValue; targetThu = newValue }
    }
    var dailyTargetFri: Double {
        get { targetFri }
        set { targetFri = newValue }
    }

    var lunchDuration: TimeInterval = 30 * 60  // 30 minutes
    var lunchWindowStart: DateComponents? = nil

    var weeklyTarget: Double {
        targetMon + targetTue + targetWed + targetThu + targetFri + targetSat + targetSun
    }

    func dailyTarget(for date: Date) -> Double {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 1: return targetSun
        case 2: return targetMon
        case 3: return targetTue
        case 4: return targetWed
        case 5: return targetThu
        case 6: return targetFri
        case 7: return targetSat
        default: return 0
        }
    }

    func isWorkingHours(at date: Date) -> Bool {
        let calendar = Calendar.current

        // No work on days with 0 target
        if dailyTarget(for: date) == 0 { return false }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        let startMinutes = (workStartTime.hour ?? 8) * 60 + (workStartTime.minute ?? 0)
        let endMinutes = (workEndTime.hour ?? 16) * 60 + (workEndTime.minute ?? 0)

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
}

// MARK: - App Settings

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
    var calendarOverlayEnabled: Bool = true

    // Holidays
    var holidayTaskNames: String = "Holiday, Holiday (feriefridag)"
    var holidayICSUrl: String = ""

    // Export
    var defaultExportFormat: ExportFormat = .pdf
    var pdfPaperSize: PaperSize = .a4
    var projectNameDisplayRegex: String = "\\[\\d+\\]\\s*"
}

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

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var timerState: TimerState = .stopped
    @Published var todayEntries: [TimeEntry] = []
    @Published var weekEntries: [TimeEntry] = []
    @Published var settings: AppSettings = AppSettings()
    @Published var isConnected: Bool = false

    private(set) var harvestClient: HarvestAPIClient?
    /// Token kept in memory so the Settings UI can read it without a second
    /// keychain call on every view appear. Populated once at launch, updated
    /// whenever new credentials are saved. Never written anywhere except the
    /// login Keychain.
    private(set) var harvestToken: String = ""
    private(set) var timerMonitor: TimerMonitor?
    private(set) var bannerManager: BannerManager?
    private(set) var idleDetector: IdleDetector?
    private(set) var systemEventHandler: SystemEventHandler?
    @Published var actionError: String? = nil

    // Calendar integration (EventKit)
    let calendarService = CalendarService()
    @Published var todayMeetings: [CalendarEvent] = []

    // Meeting → project/task memory
    let meetingMapper = MeetingProjectMapper()

    /// The meeting the user is about to log. Set when they click a meeting from the
    /// popover; a separate window reads this and shows the entry form.
    @Published var pendingMeetingEntry: CalendarEvent?

    // Project assignments (projects + tasks the user can log against). Loaded lazily.
    @Published var projectAssignments: [ProjectAssignment] = []
    @Published var isLoadingProjectAssignments: Bool = false

    // Auto-update checker (GitHub Releases)
    let updateChecker = UpdateChecker()

    init() {
        // Load persisted settings
        loadPersistedSettings()

        // Try to load saved credentials on launch.
        // Immediately re-save each item after reading so the "allow all" ACL
        // introduced in 1.0.3 is applied in the same pass that reads the value.
        // This means at most one keychain prompt per item ever — not one per
        // install — and removes the need for a separate AppDelegate migration.
        if let accountId = try? KeychainHelper.loadString(key: KeychainKey.harvestAccountId),
           let token = try? KeychainHelper.loadString(key: KeychainKey.harvestToken),
           !accountId.isEmpty, !token.isEmpty {
            try? KeychainHelper.save(key: KeychainKey.harvestAccountId, string: accountId)
            try? KeychainHelper.save(key: KeychainKey.harvestToken, string: token)
            harvestClient = HarvestAPIClient(accountId: accountId, token: token)
            harvestToken = token
            settings.harvestAccountId = accountId
            isConnected = true
            Task {
                await fetchInitialData()
                startMonitoring()
            }
        }

        // Load calendar events if authorized
        if calendarService.isAuthorized {
            todayMeetings = calendarService.getEvents(for: Date())
        }

        // Kick off a non-blocking update check if enough time has passed since
        // the last one. Safe to call unconditionally — internally no-ops if
        // the daily interval hasn't elapsed.
        updateChecker.checkIfDue()
    }

    func initializeHarvestClient(accountId: String, token: String) {
        harvestClient = HarvestAPIClient(accountId: accountId, token: token)
        harvestToken = token
        isConnected = true
        Task {
            await fetchInitialData()
            startMonitoring()
        }
    }

    // MARK: - Timer Monitor + Banner

    private func startMonitoring() {
        timerMonitor?.stopPolling()
        let monitor = TimerMonitor(appState: self)
        timerMonitor = monitor
        monitor.startPolling(interval: settings.pollingInterval)

        // Set up banner manager
        if bannerManager == nil {
            bannerManager = BannerManager(appState: self)
        }

        // Set up idle detector
        if idleDetector == nil {
            let detector = IdleDetector(appState: self)
            detector.onIdleDetected = { [weak self] idleDuration in
                guard let self = self else { return }
                if case .running(let entry) = self.timerState {
                    let taskName = entry.shortDisplayName
                    self.bannerManager?.showBanner(mode: .idle(taskName: taskName))
                }
            }
            idleDetector = detector
            detector.startMonitoring()
        }

        // Set up system event handler (auto-start/stop, EOD/EOW summaries)
        if systemEventHandler == nil {
            systemEventHandler = SystemEventHandler(appState: self)
        }
    }

    // MARK: - Timer Actions

    func stopCurrentTimer() async {
        guard let client = harvestClient,
              let entry = currentRunningEntry else { return }

        do {
            _ = try await client.stopTimer(entryId: entry.id)
            timerState = .stopped
            idleDetector?.resetIdleState()
            invalidateEntryCache()
            await timerMonitor?.pollNow()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func startTimer(projectId: Int, taskId: Int) async {
        guard let client = harvestClient else { return }

        do {
            let entry = try await client.startTimer(projectId: projectId, taskId: taskId)
            timerState = .running(entry)
            idleDetector?.resetIdleState()
            invalidateEntryCache()
            await timerMonitor?.pollNow()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Stop the current timer and subtract the idle duration from the entry.
    func stopAndSubtractIdleTime() async {
        guard let client = harvestClient,
              let entry = currentRunningEntry,
              let detector = idleDetector else { return }

        let idleHours = detector.currentIdleDuration / 3600.0

        do {
            // Stop the timer first
            let stoppedEntry = try await client.stopTimer(entryId: entry.id)

            // Subtract idle time from the total hours
            let adjustedHours = max(0, stoppedEntry.hours - idleHours)
            _ = try await client.updateTimeEntry(entryId: entry.id, hours: adjustedHours)

            timerState = .stopped
            detector.resetIdleState()
            // Refresh data immediately
            await timerMonitor?.pollNow()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Data Fetching

    private func fetchInitialData() async {
        guard let client = harvestClient else { return }

        do {
            // Fetch running timer
            if let running = try await client.getRunningTimer() {
                timerState = .running(running)
            } else {
                timerState = .stopped
            }

            // Fetch today's entries
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            todayEntries = try await client.getTimeEntries(from: startOfDay, to: Date())

            // Fetch current week's entries (Monday to Sunday)
            let isoCal = Calendar(identifier: .iso8601)
            let monday = isoCal.date(from: isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let sunday = isoCal.date(byAdding: .day, value: 6, to: monday)!
            weekEntries = try await client.getTimeEntries(from: monday, to: sunday)
        } catch {
            if let apiError = error as? HarvestAPIError,
               case .unauthorized = apiError {
                isConnected = false
            }
            // Keep previous state on other errors
        }
    }

    var todayTotalHours: Double {
        todayEntries.reduce(0) { total, entry in
            if entry.isRunning, let startedAt = entry.timerStartedAt {
                let elapsed = Date().timeIntervalSince(startedAt) / 3600.0
                return total + entry.hours + elapsed
            }
            return total + entry.hours
        }
    }

    var todayTarget: Double {
        HolidayEngine.expectedHours(for: Date(), settings: settings)
    }

    var todayProgress: Double {
        guard todayTarget > 0 else { return 0 }
        return min(todayTotalHours / todayTarget, 1.0)
    }

    var todayDelta: Double {
        todayTotalHours - todayTarget
    }

    var currentRunningEntry: TimeEntry? {
        if case .running(let entry) = timerState {
            return entry
        }
        return nil
    }

    // MARK: - Overtime (Week)

    var currentWeekSummary: WeekSummary {
        OvertimeCalculator.weekSummary(
            containing: Date(),
            entries: weekEntries,
            settings: settings
        )
    }

    var weeklyNetOvertime: Double {
        currentWeekSummary.delta
    }

    // MARK: - Export Data (non-reactive — does NOT trigger view re-renders)

    /// Holds the current export period for the active dashboard tab.
    /// Intentionally NOT @Published so setting it doesn't cascade re-renders.
    var pendingExportPeriod: ExportPeriod?

    // MARK: - Entry Cache

    private var entryCache: [String: (entries: [TimeEntry], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 120  // 2 minutes

    private static let cacheKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func cacheKey(from: Date, to: Date) -> String {
        return "\(Self.cacheKeyFormatter.string(from: from))_\(Self.cacheKeyFormatter.string(from: to))"
    }

    /// Fetch entries for a given date range (for dashboard use). Uses cache.
    func fetchEntries(from: Date, to: Date) async -> [TimeEntry] {
        let key = cacheKey(from: from, to: to)

        // Return cached if fresh
        if let cached = entryCache[key],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.entries
        }

        guard let client = harvestClient else { return [] }
        do {
            let entries = try await client.getTimeEntries(from: from, to: to)
            entryCache[key] = (entries: entries, fetchedAt: Date())
            return entries
        } catch {
            return []
        }
    }

    /// Invalidate cache (e.g. after starting/stopping a timer).
    func invalidateEntryCache() {
        entryCache.removeAll()
    }

    // MARK: - Calendar Integration

    func refreshTodayMeetings() {
        guard calendarService.isAuthorized else {
            todayMeetings = []
            return
        }
        todayMeetings = calendarService.getEvents(for: Date())
    }

    /// Fetch meetings for a specific date (for dashboard use).
    func fetchMeetings(for date: Date) async -> [CalendarEvent] {
        guard calendarService.isAuthorized else { return [] }
        return calendarService.getEvents(for: date)
    }

    // MARK: - Project Assignments (projects + tasks)

    /// Load the user's project assignments if we don't already have them. Safe to call repeatedly.
    func loadProjectAssignmentsIfNeeded(force: Bool = false) async {
        if !force && !projectAssignments.isEmpty { return }
        guard let client = harvestClient else { return }

        isLoadingProjectAssignments = true
        do {
            let assignments = try await client.getMyProjectAssignments()
            // Keep only active project assignments with at least one active task.
            projectAssignments = assignments
                .filter { $0.isActive && !$0.activeTasks.isEmpty }
                .sorted { $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending }
        } catch {
            actionError = "Couldn't load projects: \(error.localizedDescription)"
        }
        isLoadingProjectAssignments = false
    }

    /// Create a (non-running) time entry for a meeting and remember the
    /// project/task choice for that meeting title.
    /// Returns `true` on success.
    @discardableResult
    func createEntryForMeeting(
        meetingTitle: String,
        projectId: Int,
        projectName: String,
        taskId: Int,
        taskName: String,
        spentDate: Date,
        hours: Double?,
        notes: String?
    ) async -> Bool {
        guard let client = harvestClient else { return false }

        do {
            _ = try await client.createTimeEntry(
                projectId: projectId,
                taskId: taskId,
                spentDate: spentDate,
                hours: hours,
                notes: notes
            )

            // Remember the choice for this meeting title
            meetingMapper.remember(
                meetingTitle: meetingTitle,
                projectId: projectId,
                projectName: projectName,
                taskId: taskId,
                taskName: taskName
            )

            invalidateEntryCache()
            await timerMonitor?.pollNow()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: - Load Persisted Settings

    private func loadPersistedSettings() {
        let ud = UserDefaults.standard

        // General
        settings.pollingInterval = ud.object(forKey: "pollingInterval") as? TimeInterval ?? 60

        // Work Schedule
        settings.workSchedule.workStartTime = DateComponents(
            hour: ud.object(forKey: "workStartHour") as? Int ?? 8,
            minute: ud.object(forKey: "workStartMinute") as? Int ?? 0
        )
        settings.workSchedule.workEndTime = DateComponents(
            hour: ud.object(forKey: "workEndHour") as? Int ?? 16,
            minute: ud.object(forKey: "workEndMinute") as? Int ?? 0
        )
        settings.workSchedule.targetMon = ud.object(forKey: "targetMon") as? Double ?? 7.5
        settings.workSchedule.targetTue = ud.object(forKey: "targetTue") as? Double ?? 7.5
        settings.workSchedule.targetWed = ud.object(forKey: "targetWed") as? Double ?? 7.5
        settings.workSchedule.targetThu = ud.object(forKey: "targetThu") as? Double ?? 7.5
        settings.workSchedule.targetFri = ud.object(forKey: "targetFri") as? Double ?? 7.0
        settings.workSchedule.targetSat = ud.object(forKey: "targetSat") as? Double ?? 0.0
        settings.workSchedule.targetSun = ud.object(forKey: "targetSun") as? Double ?? 0.0
        settings.workSchedule.lunchDuration = (ud.object(forKey: "lunchDuration") as? Double ?? 30) * 60
        if ud.bool(forKey: "hasLunchWindow") {
            settings.workSchedule.lunchWindowStart = DateComponents(
                hour: ud.object(forKey: "lunchWindowHour") as? Int ?? 12,
                minute: ud.object(forKey: "lunchWindowMinute") as? Int ?? 0
            )
        }

        // Notifications
        settings.timerNudgeEnabled = ud.object(forKey: "timerNudge") as? Bool ?? true
        settings.bannerPosition = BannerPosition(rawValue: ud.string(forKey: "bannerPosition") ?? "Top") ?? .top
        settings.snoozeDuration = (ud.object(forKey: "snoozeDuration") as? Double ?? 15) * 60
        settings.idleDetectionEnabled = ud.object(forKey: "idleDetection") as? Bool ?? true
        settings.idleThreshold = (ud.object(forKey: "idleThreshold") as? Double ?? 15) * 60
        settings.longTimerWarningEnabled = ud.object(forKey: "longTimerWarning") as? Bool ?? true
        settings.longTimerThreshold = (ud.object(forKey: "longTimerThreshold") as? Double ?? 3) * 3600
        settings.autoStopOnSleep = ud.bool(forKey: "autoStopOnSleep")

        // EOD / EOW summary schedule — keys written by NotificationsSettingsTab.
        // Without loading here, the scheduler falls back to 16:00 every app
        // launch until the user opens Settings (which re-syncs as a side effect).
        settings.eodSummaryEnabled = ud.object(forKey: "eodSummary") as? Bool ?? true
        settings.eodSummaryTime = DateComponents(
            hour: ud.object(forKey: "eodHour") as? Int ?? 16,
            minute: ud.object(forKey: "eodMinute") as? Int ?? 0
        )
        settings.eowSummaryEnabled = ud.object(forKey: "eowSummary") as? Bool ?? true
        settings.eowSummaryTime = DateComponents(
            hour: ud.object(forKey: "eowHour") as? Int ?? 16,
            minute: ud.object(forKey: "eowMinute") as? Int ?? 0
        )

        // Holidays
        settings.holidayTaskNames = ud.string(forKey: "holidayTaskNames") ?? "Holiday, Holiday (feriefridag)"
        settings.holidayICSUrl = ud.string(forKey: "holidayICSUrl") ?? ""

        // Export
        settings.defaultExportFormat = ExportFormat(rawValue: ud.string(forKey: "defaultExportFormat") ?? "PDF") ?? .pdf
        settings.pdfPaperSize = PaperSize(rawValue: ud.string(forKey: "pdfPaperSize") ?? "A4") ?? .a4
        settings.projectNameDisplayRegex = ud.string(forKey: "projectNameDisplayRegex") ?? "\\[\\d+\\]\\s*"
    }
}
