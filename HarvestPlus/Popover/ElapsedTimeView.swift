//
//  ElapsedTimeView.swift
//  HarvestPlus
//
//  The live "H:MM:SS" elapsed-time readout shown in the popover's active
//  timer card. Ticks once per second while visible and stops when the
//  popover closes. Extracted from PopoverView.swift.
//

import SwiftUI
import Combine

struct ElapsedTimeView: View {
    /// `entry.hours` from the most recent Harvest poll – the live total
    /// at poll time (Harvest returns it that way for running timers).
    let baseHours: Double
    /// Wall-clock time of that poll. We extrapolate elapsed *from this
    /// moment forward*, not from `timer_started_at`, so the period from
    /// `timer_started_at` to `polledAt` isn't double-counted.
    let polledAt: Date?
    /// Only running entries get live extrapolation; for stopped entries
    /// we render `baseHours` verbatim.
    let isRunning: Bool

    @State private var now = Date()
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        Text(formattedElapsed)
            .font(.title2)
            .monospacedDigit()
            .onAppear {
                // Only subscribe while the view is in the hierarchy. Stops
                // the 1 Hz tick when the popover is closed, preventing
                // needless view-body re-evaluation.
                timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { date in
                        now = date
                    }
            }
            .onDisappear {
                timerCancellable?.cancel()
                timerCancellable = nil
            }
    }

    private var formattedElapsed: String {
        var totalSeconds = Int(baseHours * 3600)
        if isRunning, let polled = polledAt {
            // Forward-extrapolate from the poll moment, not from
            // `timer_started_at` – the time between `timer_started_at`
            // and `polled` is already included in `baseHours`.
            totalSeconds += Int(max(0, now.timeIntervalSince(polled)))
        }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
