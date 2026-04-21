//
//  TimerMonitor.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import Foundation
import Combine

// MARK: - Timer Monitor

@MainActor
final class TimerMonitor: ObservableObject {
    @Published var isPolling: Bool = false

    private var pollTimer: Timer?
    private weak var appState: AppState?

    // Long timer tracking — only notify once per entry
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

        // Schedule recurring polls
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
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

        do {
            // Fetch running timer
            if let running = try await client.getRunningTimer() {
                appState.timerState = .running(running)

                // Check if timer has been running too long
                checkLongTimer(entry: running)
            } else {
                appState.timerState = .stopped

                // Reset long timer tracking when no timer is running
                hasNotifiedLongTimer = false
                lastLongTimerEntryId = nil
            }

            // Fetch today's entries
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let todayEntries = try await client.getTimeEntries(from: startOfDay, to: Date())
            appState.todayEntries = todayEntries

        } catch {
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
            // New entry or below threshold — reset tracking
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
