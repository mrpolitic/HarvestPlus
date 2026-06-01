//
//  CalendarService.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 15/04/2026.
//
//  EventKit wrapper. Manages calendar-access authorization and reads the
//  user's events for a given day, filtered to the calendars they've enabled.
//  Feeds the "Meetings today" list in the popover and the Daily dashboard.
//

import Foundation
import EventKit
import Combine
import SwiftUI

// MARK: - Calendar Service

@MainActor
final class CalendarService: ObservableObject {
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var availableCalendars: [CalendarInfo] = []
    @Published var enabledCalendarIds: Set<String> = []

    private let store = EKEventStore()

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    init() {
        refreshStatus()
        loadEnabledCalendars()
    }

    // MARK: - Authorization

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized {
            loadAvailableCalendars()
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshStatus()
            return granted
        } catch {
            refreshStatus()
            return false
        }
    }

    // MARK: - Calendars

    private func loadAvailableCalendars() {
        availableCalendars = store.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                accountName: cal.source.title,
                color: Color(cgColor: cal.cgColor)
            )
        }
        .sorted { $0.accountName < $1.accountName }
    }

    private func loadEnabledCalendars() {
        if let saved = UserDefaults.standard.array(forKey: "enabledCalendarIds") as? [String] {
            enabledCalendarIds = Set(saved)
        }
        // If nothing saved yet, enable all by default on first use
        if enabledCalendarIds.isEmpty && isAuthorized {
            enabledCalendarIds = Set(availableCalendars.map(\.id))
        }
    }

    func setCalendarEnabled(_ calendarId: String, enabled: Bool) {
        if enabled {
            enabledCalendarIds.insert(calendarId)
        } else {
            enabledCalendarIds.remove(calendarId)
        }
        UserDefaults.standard.set(Array(enabledCalendarIds), forKey: "enabledCalendarIds")
    }

    // MARK: - Fetch Events

    func getEvents(for date: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }

        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: enabledEKCalendars)
        let ekEvents = store.events(matching: predicate)

        return ekEvents
            .filter { !$0.isAllDay }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    subject: event.title ?? "(No Subject)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    organizer: event.organizer?.name,
                    isOnlineMeeting: event.isDetached == false && (event.url != nil || (event.notes?.contains("teams.microsoft.com") ?? false) || (event.notes?.contains("zoom.us") ?? false)),
                    calendarName: event.calendar.title,
                    calendarColor: Color(cgColor: event.calendar.cgColor)
                )
            }
            .sorted { $0.start < $1.start }
    }

    func getEvents(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: enabledEKCalendars)
        let ekEvents = store.events(matching: predicate)

        return ekEvents
            .filter { !$0.isAllDay }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    subject: event.title ?? "(No Subject)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    organizer: event.organizer?.name,
                    isOnlineMeeting: event.url != nil || (event.notes?.contains("teams.microsoft.com") ?? false) || (event.notes?.contains("zoom.us") ?? false),
                    calendarName: event.calendar.title,
                    calendarColor: Color(cgColor: event.calendar.cgColor)
                )
            }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Helpers

    private var enabledEKCalendars: [EKCalendar]? {
        guard !enabledCalendarIds.isEmpty else { return nil }
        let all = store.calendars(for: .event)
        let filtered = all.filter { enabledCalendarIds.contains($0.calendarIdentifier) }
        return filtered.isEmpty ? nil : filtered
    }
}

// MARK: - Calendar Info

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let accountName: String
    let color: Color
}

// MARK: - Calendar Event

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let subject: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let organizer: String?
    let isOnlineMeeting: Bool
    var calendarName: String = ""
    var calendarColor: Color = AppColor.meetingBlue

    /// Duration in minutes.
    var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }

    /// Start minute of day (minutes from midnight).
    var startMinuteOfDay: Int {
        let cal = Calendar.current
        return cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
    }

    /// End minute of day (minutes from midnight).
    var endMinuteOfDay: Int {
        let cal = Calendar.current
        return cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}
