//
//  IdleDetector.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Polls the system HID idle time (IOKit) while a timer is running and fires
//  a callback once the user has been idle past the threshold, so the banner
//  can offer to stop the timer and subtract the idle stretch.
//

import Foundation
import IOKit
import Combine
import SwiftUI

// MARK: - Idle Detector

@MainActor
final class IdleDetector: ObservableObject {
    @Published var isIdle: Bool = false
    @Published var idleDuration: TimeInterval = 0

    private var checkTimer: Timer?
    private weak var appState: AppState?
    private var idleStartTime: Date?
    private var hasNotifiedIdle: Bool = false

    /// Called when the user has been idle longer than the threshold.
    var onIdleDetected: ((TimeInterval) -> Void)?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Start / Stop

    func startMonitoring() {
        guard checkTimer == nil else { return }

        // Check every 30 seconds. Add to RunLoop.main in .common modes so it keeps
        // firing while the popover or a modal/tracking loop is open.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIdleState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
        resetIdleState()
    }

    func resetIdleState() {
        isIdle = false
        idleDuration = 0
        idleStartTime = nil
        hasNotifiedIdle = false
    }

    // MARK: - Idle Check

    private func checkIdleState() {
        guard let appState = appState,
              appState.settings.idleDetectionEnabled else { return }

        // Only check when a timer is running
        guard case .running = appState.timerState else {
            resetIdleState()
            return
        }

        let systemIdleTime = getSystemIdleTime()
        let threshold = appState.settings.idleThreshold

        if systemIdleTime >= threshold {
            if !isIdle {
                // Just crossed the threshold – record when idle started
                isIdle = true
                idleStartTime = Date().addingTimeInterval(-systemIdleTime)
            }
            idleDuration = systemIdleTime

            if !hasNotifiedIdle {
                hasNotifiedIdle = true
                onIdleDetected?(systemIdleTime)
            }
        } else {
            if isIdle {
                // User came back – reset
                resetIdleState()
            }
        }
    }

    // MARK: - IOKit HIDIdleTime

    /// Queries IOKit for the time (in seconds) since the last mouse/keyboard event.
    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else {
            return 0
        }

        let entry = IOIteratorNext(iterator)
        defer { IOObjectRelease(entry) }
        guard entry != 0 else { return 0 }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedDict,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
              let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleTime = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }

    /// The duration of the current idle period (from when idle started until now).
    var currentIdleDuration: TimeInterval {
        guard let start = idleStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    deinit {
        checkTimer?.invalidate()
    }
}
