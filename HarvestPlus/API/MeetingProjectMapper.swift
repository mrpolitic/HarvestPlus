//
//  MeetingProjectMapper.swift
//  HarvestPlus
//
//  Persists the user's project/task choices for meeting titles, so when they
//  click the same recurring meeting again, the right project/task is pre-filled.
//

import Foundation

// MARK: - Meeting Default

/// The user's last chosen project/task for a given meeting title.
struct MeetingEntryDefault: Codable, Equatable {
    let projectId: Int
    let projectName: String
    let taskId: Int
    let taskName: String
    let lastUsed: Date
}

// MARK: - Mapper

@MainActor
final class MeetingProjectMapper {
    private let defaultsKey = "meetingProjectMap"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Look up a saved default for a meeting title. Matching is case-insensitive
    /// and whitespace-trimmed to tolerate tiny variations.
    func savedDefault(for meetingTitle: String) -> MeetingEntryDefault? {
        let key = normalize(meetingTitle)
        guard !key.isEmpty else { return nil }
        return loadAll()[key]
    }

    /// Persist the choice. Called after the user saves a time entry from a meeting.
    func remember(
        meetingTitle: String,
        projectId: Int,
        projectName: String,
        taskId: Int,
        taskName: String
    ) {
        let key = normalize(meetingTitle)
        guard !key.isEmpty else { return }

        var map = loadAll()
        map[key] = MeetingEntryDefault(
            projectId: projectId,
            projectName: projectName,
            taskId: taskId,
            taskName: taskName,
            lastUsed: Date()
        )
        saveAll(map)
    }

    /// Forget the mapping for a meeting title (e.g. user chooses a different project
    /// and wants to reset).
    func forget(meetingTitle: String) {
        let key = normalize(meetingTitle)
        var map = loadAll()
        map.removeValue(forKey: key)
        saveAll(map)
    }

    /// Clear everything. Exposed for settings/debug.
    func clearAll() {
        userDefaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Private

    private func normalize(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func loadAll() -> [String: MeetingEntryDefault] {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: MeetingEntryDefault].self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveAll(_ map: [String: MeetingEntryDefault]) {
        do {
            let data = try JSONEncoder().encode(map)
            userDefaults.set(data, forKey: defaultsKey)
        } catch {
            // If we can't encode it, there's nothing sensible to do – silently drop.
        }
    }
}
