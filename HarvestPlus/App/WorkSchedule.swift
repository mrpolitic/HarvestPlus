//
//  WorkSchedule.swift
//  HarvestPlus
//
//  The user's configured working hours and per-weekday hour targets, plus
//  the derived helpers (daily/weekly targets, working-hours check) used by
//  the overtime calculator and the nudge banner. Extracted from
//  AppState.swift.
//

import Foundation

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
