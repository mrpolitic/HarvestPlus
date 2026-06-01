//
//  TimerState.swift
//  HarvestPlus
//
//  The running state of the Harvest timer, as tracked by AppState.
//  Extracted from AppState.swift so the state object stays focused.
//

import Foundation

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
