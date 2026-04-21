//
//  HarvestModels.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import Foundation

// MARK: - Time Entry

struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let spentDate: String
    let hours: Double
    let notes: String?
    let isRunning: Bool
    let timerStartedAt: Date?
    let project: ProjectReference
    let task: TaskReference
    let user: UserReference

    enum CodingKeys: String, CodingKey {
        case id
        case spentDate = "spent_date"
        case hours
        case notes
        case isRunning = "is_running"
        case timerStartedAt = "timer_started_at"
        case project
        case task
        case user
    }

    static func == (lhs: TimeEntry, rhs: TimeEntry) -> Bool {
        lhs.id == rhs.id
    }

    /// Project name with bracket codes stripped for display.
    var displayProjectName: String {
        project.name.replacingOccurrences(
            of: "\\[\\d+\\]\\s*",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Short display format: "Project / Task"
    var shortDisplayName: String {
        let proj = displayProjectName
        let taskName = task.name
        let combined = "\(proj) / \(taskName)"
        if combined.count > 20 {
            return taskName
        }
        return combined
    }
}

// MARK: - Nested References

struct ProjectReference: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

struct TaskReference: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

struct UserReference: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

// MARK: - API Responses

struct TimeEntriesResponse: Codable, Sendable {
    let timeEntries: [TimeEntry]
    let totalEntries: Int
    let totalPages: Int
    let page: Int

    enum CodingKeys: String, CodingKey {
        case timeEntries = "time_entries"
        case totalEntries = "total_entries"
        case totalPages = "total_pages"
        case page
    }
}

// MARK: - Project

struct HarvestProject: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
    }
}

// MARK: - Task Assignment (a task available on a project)

struct HarvestTask: Codable, Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
}

struct TaskAssignment: Codable, Identifiable, Sendable {
    let id: Int
    let isActive: Bool
    let task: HarvestTask

    enum CodingKeys: String, CodingKey {
        case id
        case isActive = "is_active"
        case task
    }
}

// MARK: - Project Assignment (project + its task assignments, scoped to current user)

struct ProjectAssignmentProject: Codable, Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let code: String?
}

struct ProjectAssignmentClient: Codable, Sendable, Hashable {
    let id: Int
    let name: String
}

struct ProjectAssignment: Codable, Identifiable, Sendable {
    let id: Int
    let isActive: Bool
    let project: ProjectAssignmentProject
    let client: ProjectAssignmentClient?
    let taskAssignments: [TaskAssignment]

    enum CodingKeys: String, CodingKey {
        case id
        case isActive = "is_active"
        case project
        case client
        case taskAssignments = "task_assignments"
    }

    /// Active tasks on this project.
    var activeTasks: [HarvestTask] {
        taskAssignments.filter(\.isActive).map(\.task)
    }
}

// MARK: - User

struct HarvestUser: Codable, Identifiable, Sendable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

struct HarvestUserResponse: Codable, Sendable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }
}
