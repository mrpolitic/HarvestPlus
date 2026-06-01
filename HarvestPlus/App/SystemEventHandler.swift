//
//  SystemEventHandler.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//
//  Reacts to the system events surfaced by AppDelegate: auto-stops the timer
//  on sleep / screen lock (when enabled) and schedules the end-of-day and
//  end-of-week summary banners.
//

import Foundation
import Combine

// MARK: - System Event Handler

@MainActor
final class SystemEventHandler: ObservableObject {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var eodTimer: Timer?
    private var eowTimer: Timer?
    private var hasShownEodToday: Bool = false
    private var hasShownEowThisWeek: Bool = false

    init(appState: AppState) {
        self.appState = appState
        observeSystemEvents()
        scheduleNextSummaryCheck()
    }

    // MARK: - System Event Observers

    private func observeSystemEvents() {
        // Sleep – auto-stop timer
        NotificationCenter.default.publisher(for: .systemWillSleep)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSleep()
            }
            .store(in: &cancellables)

        // Wake – reset daily summary flag if the day rolled over
        NotificationCenter.default.publisher(for: .systemDidWake)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleWake()
            }
            .store(in: &cancellables)

        // Screen lock – same as sleep for timer purposes
        NotificationCenter.default.publisher(for: .screenDidLock)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleScreenLock()
            }
            .store(in: &cancellables)

        // Screen unlock – re-check whether summaries need to be shown
        NotificationCenter.default.publisher(for: .screenDidUnlock)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleScreenUnlock()
            }
            .store(in: &cancellables)
    }

    // MARK: - Sleep / Wake Handling

    private func handleSleep() {
        guard let appState = appState,
              appState.settings.autoStopOnSleep else { return }

        if case .running = appState.timerState {
            Task {
                await appState.stopCurrentTimer()
            }
        }
    }

    /// Reset the daily-summary flag if we've crossed into a new day while asleep.
    /// HarvestPlus intentionally does NOT auto-start a timer on wake – creating
    /// time entries belongs in Harvest.
    private func handleWake() {
        let cal = Calendar.current
        if !cal.isDateInToday(lastSummaryDate) {
            hasShownEodToday = false
        }
    }

    private func handleScreenLock() {
        // Same behavior as sleep
        handleSleep()
    }

    private func handleScreenUnlock() {
        handleWake()
        // Also check if summaries need to be shown
        checkSummaries()
    }

    // MARK: - EOD / EOW Summary Scheduling

    private var lastSummaryDate: Date = Date.distantPast

    /// Checks every 60 seconds if it's time to show a summary.
    private func scheduleNextSummaryCheck() {
        eodTimer?.invalidate()
        // .common modes so the summary check keeps firing while the popover or a
        // modal/tracking loop is open – otherwise the narrow EOD/EOW window
        // (a 5-minute band once a day) could be missed entirely.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSummaries()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        eodTimer = timer
    }

    private func checkSummaries() {
        guard let appState = appState else { return }
        let now = Date()
        let cal = Calendar.current

        // EOD Summary
        if appState.settings.eodSummaryEnabled && !hasShownEodToday {
            let eodComps = appState.settings.eodSummaryTime
            let eodHour = eodComps.hour ?? 16
            let eodMinute = eodComps.minute ?? 0
            let currentHour = cal.component(.hour, from: now)
            let currentMinute = cal.component(.minute, from: now)

            if currentHour == eodHour && currentMinute >= eodMinute && currentMinute < eodMinute + 5 {
                hasShownEodToday = true
                lastSummaryDate = now
                showEodSummary()
            }
        }

        // EOW Summary (Friday only)
        if appState.settings.eowSummaryEnabled && !hasShownEowThisWeek {
            let weekday = cal.component(.weekday, from: now)
            if weekday == 6 {  // Friday
                let eowComps = appState.settings.eowSummaryTime
                let eowHour = eowComps.hour ?? 16
                let eowMinute = eowComps.minute ?? 0
                let currentHour = cal.component(.hour, from: now)
                let currentMinute = cal.component(.minute, from: now)

                if currentHour == eowHour && currentMinute >= eowMinute && currentMinute < eowMinute + 5 {
                    hasShownEowThisWeek = true
                    showEowSummary()
                }
            }
        }

        // Reset weekly flag on Monday
        let weekday = cal.component(.weekday, from: now)
        if weekday == 2 {  // Monday
            hasShownEowThisWeek = false
        }

        // Reset daily flag at midnight
        if !cal.isDateInToday(lastSummaryDate) {
            hasShownEodToday = false
        }
    }

    // MARK: - Show Summaries

    private func showEodSummary() {
        guard let appState = appState else { return }

        let daySummary = OvertimeCalculator.daySummary(
            date: Date(),
            entries: appState.todayEntries,
            settings: appState.settings,
            polledAt: appState.lastPolledAt
        )

        appState.bannerManager?.showBanner(mode: .eodSummary(daySummary))
    }

    private func showEowSummary() {
        guard let appState = appState else { return }

        let weekSummary = OvertimeCalculator.weekSummary(
            containing: Date(),
            entries: appState.weekEntries,
            settings: appState.settings
        )

        appState.bannerManager?.showBanner(mode: .eowSummary(weekSummary))
    }

    deinit {
        eodTimer?.invalidate()
        eowTimer?.invalidate()
    }
}
