//
//  TimerMonitor.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Polls the Harvest API on an interval to keep the running-timer state in
//  sync with whatever the user does in Harvest itself, and raises the
//  long-timer warning once per entry.
//

import Foundation
import Combine

// MARK: - Timer Monitor

@MainActor
final class TimerMonitor: ObservableObject {
    @Published var isPolling: Bool = false

    private var pollTimer: Timer?
    private weak var appState: AppState?

    /// Bumped at the start of every poll. A poll only commits its results if it's
    /// still the latest one – so an older, slower poll resolving after a newer one
    /// (e.g. a scheduled poll overlapping a `pollNow()` after Stop) can't clobber
    /// fresh state with stale data.
    private var pollGeneration = 0

    // Long timer tracking – only notify once per entry
    private var hasNotifiedLongTimer: Bool = false
    private var lastLongTimerEntryId: Int?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 60) {
        guard !isPolling else { return }
        isPolling = true

        // Immediate first poll
        Task { await poll() }

        // Schedule recurring polls. Add to RunLoop.main in .common modes so the
        // timer keeps firing while the menu-bar popover (or any modal/tracking
        // loop) is open – with the default mode, polling would stall exactly while
        // the user has the popover open to check status.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    func restartPolling(interval: TimeInterval) {
        stopPolling()
        startPolling(interval: interval)
    }

    /// Force an immediate poll (e.g., after starting/stopping a timer)
    func pollNow() async {
        await poll()
    }

    // MARK: - Poll Logic

    private func poll() async {
        guard let appState = appState,
              let client = appState.harvestClient else { return }

        pollGeneration += 1
        let generation = pollGeneration

        do {
            // Fetch everything first, then commit in one shot. Fetching before
            // mutating means a mid-poll failure leaves all state untouched (no
            // half-applied running/stopped + entries), and the generation check
            // below ensures a stale poll can't overwrite newer data.
            let running = try await client.getRunningTimer()
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let todayEntries = try await client.getTimeEntries(from: startOfDay, to: Date())

            guard generation == pollGeneration else { return }  // a newer poll superseded us

            if let running = running {
                appState.timerState = .running(running)

                // Check if timer has been running too long
                checkLongTimer(entry: running)
            } else {
                appState.timerState = .stopped

                // Reset long timer tracking when no timer is running
                hasNotifiedLongTimer = false
                lastLongTimerEntryId = nil
            }

            appState.todayEntries = todayEntries

            // Stamp the moment we successfully received fresh data – all
            // live-elapsed extrapolation (popover ticker, dashboard sums,
            // OvertimeCalculator) is computed as (now - lastPolledAt).
            appState.lastPolledAt = Date()

        } catch {
            guard generation == pollGeneration else { return }  // stale error from a superseded poll

            // Network error: keep previous state, mark offline if persistent
            if let apiError = error as? HarvestAPIError {
                switch apiError {
                case .unauthorized:
                    appState.isConnected = false
                    appState.timerState = .offline
                    stopPolling()
                case .networkError:
                    appState.timerState = .offline
                default:
                    break  // Keep previous state
                }
            }
        }
    }

    // MARK: - Long Timer Detection

    private func checkLongTimer(entry: TimeEntry) {
        guard let appState = appState,
              appState.settings.longTimerWarningEnabled,
              let startedAt = entry.timerStartedAt else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        let threshold = appState.settings.longTimerThreshold

        if elapsed >= threshold {
            // Only notify once per entry
            if lastLongTimerEntryId != entry.id || !hasNotifiedLongTimer {
                hasNotifiedLongTimer = true
                lastLongTimerEntryId = entry.id
                let hours = elapsed / 3600.0
                let taskName = entry.shortDisplayName
                appState.bannerManager?.showBanner(
                    mode: .longTimer(taskName: taskName, hours: hours)
                )
            }
        } else {
            // New entry or below threshold – reset tracking
            if lastLongTimerEntryId != entry.id {
                hasNotifiedLongTimer = false
                lastLongTimerEntryId = entry.id
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}
