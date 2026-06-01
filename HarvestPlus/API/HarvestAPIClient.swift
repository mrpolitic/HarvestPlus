//
//  HarvestAPIClient.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  The Harvest v2 REST client. Wraps the endpoints HarvestPlus needs –
//  running timer, time entries for a date range (paginated), project
//  assignments, and stop/restart/create – behind bearer-token auth.
//

import Foundation

// MARK: - Harvest API Client

final class HarvestAPIClient: Sendable {
    private let baseURL = "https://api.harvestapp.com/v2"
    private let accountId: String
    private let token: String

    // MARK: - Init

    init(accountId: String, token: String) {
        self.accountId = accountId
        self.token = token
    }

    // MARK: - API Methods

    /// Get the currently running timer, if any.
    func getRunningTimer() async throws -> TimeEntry? {
        let response: TimeEntriesResponse = try await performRequest(
            endpoint: "/time_entries",
            queryItems: [URLQueryItem(name: "is_running", value: "true")]
        )
        return response.timeEntries.first
    }

    /// Fetch time entries for a date range. Handles pagination automatically.
    func getTimeEntries(from: Date, to: Date) async throws -> [TimeEntry] {
        let fromStr = Self.dateFormatter.string(from: from)
        let toStr = Self.dateFormatter.string(from: to)

        var allEntries: [TimeEntry] = []
        var currentPage = 1
        var totalPages = 1
        let maxPages = 100  // safety ceiling: 100 × 2000 = 200k entries, far beyond any real range

        while currentPage <= totalPages && currentPage <= maxPages {
            let response: TimeEntriesResponse = try await performRequest(
                endpoint: "/time_entries",
                queryItems: [
                    URLQueryItem(name: "from", value: fromStr),
                    URLQueryItem(name: "to", value: toStr),
                    URLQueryItem(name: "page", value: String(currentPage)),
                    URLQueryItem(name: "per_page", value: "2000")
                ]
            )
            // Stop if a page comes back empty even though total_pages claims more –
            // guards against an infinite loop on a malformed pagination response.
            if response.timeEntries.isEmpty { break }
            allEntries.append(contentsOf: response.timeEntries)
            totalPages = response.totalPages
            currentPage += 1
        }

        return allEntries
    }

    /// Start a new timer.
    func startTimer(projectId: Int, taskId: Int, notes: String? = nil) async throws -> TimeEntry {
        var body: [String: Any] = [
            "project_id": projectId,
            "task_id": taskId,
            "spent_date": Self.dateFormatter.string(from: Date()),
            "is_running": true
        ]
        if let notes = notes {
            body["notes"] = notes
        }

        return try await performRequest(endpoint: "/time_entries", method: "POST", body: body)
    }

    /// Create a time entry without starting the timer (e.g. for a past meeting).
    /// If `hours` is nil, Harvest creates a zero-duration entry.
    func createTimeEntry(
        projectId: Int,
        taskId: Int,
        spentDate: Date,
        hours: Double?,
        notes: String?
    ) async throws -> TimeEntry {
        var body: [String: Any] = [
            "project_id": projectId,
            "task_id": taskId,
            "spent_date": Self.dateFormatter.string(from: spentDate)
        ]
        if let hours = hours {
            body["hours"] = hours
        }
        if let notes = notes {
            body["notes"] = notes
        }

        return try await performRequest(endpoint: "/time_entries", method: "POST", body: body)
    }

    /// Stop a running timer.
    func stopTimer(entryId: Int) async throws -> TimeEntry {
        return try await performRequest(
            endpoint: "/time_entries/\(entryId)/stop",
            method: "PATCH"
        )
    }

    /// Update a time entry's hours (e.g., to subtract idle time).
    func updateTimeEntry(entryId: Int, hours: Double) async throws -> TimeEntry {
        let body: [String: Any] = ["hours": max(0, hours)]
        return try await performRequest(
            endpoint: "/time_entries/\(entryId)",
            method: "PATCH",
            body: body
        )
    }

    /// Get all active projects.
    func getProjects() async throws -> [HarvestProject] {
        var allProjects: [HarvestProject] = []
        var currentPage = 1
        var totalPages = 1
        let maxPages = 100

        while currentPage <= totalPages && currentPage <= maxPages {
            let response: ProjectsResponse = try await performRequest(
                endpoint: "/projects",
                queryItems: [
                    URLQueryItem(name: "is_active", value: "true"),
                    URLQueryItem(name: "page", value: String(currentPage))
                ]
            )
            if response.projects.isEmpty { break }
            allProjects.append(contentsOf: response.projects)
            totalPages = response.totalPages
            currentPage += 1
        }

        return allProjects
    }

    /// Get active task assignments for a project.
    /// These are the tasks the current user can log time against on that project.
    func getTaskAssignments(projectId: Int) async throws -> [TaskAssignment] {
        var allAssignments: [TaskAssignment] = []
        var currentPage = 1
        var totalPages = 1
        let maxPages = 100

        while currentPage <= totalPages && currentPage <= maxPages {
            let response: TaskAssignmentsResponse = try await performRequest(
                endpoint: "/projects/\(projectId)/task_assignments",
                queryItems: [
                    URLQueryItem(name: "is_active", value: "true"),
                    URLQueryItem(name: "page", value: String(currentPage))
                ]
            )
            if response.taskAssignments.isEmpty { break }
            allAssignments.append(contentsOf: response.taskAssignments)
            totalPages = response.totalPages
            currentPage += 1
        }

        return allAssignments
    }

    /// Get the current user's project assignments – the projects they can log time against,
    /// with the tasks available on each. Single call, replaces separate projects+tasks fetching.
    func getMyProjectAssignments() async throws -> [ProjectAssignment] {
        var all: [ProjectAssignment] = []
        var currentPage = 1
        var totalPages = 1
        let maxPages = 100

        while currentPage <= totalPages && currentPage <= maxPages {
            let response: ProjectAssignmentsResponse = try await performRequest(
                endpoint: "/users/me/project_assignments",
                queryItems: [
                    URLQueryItem(name: "page", value: String(currentPage))
                ]
            )
            if response.projectAssignments.isEmpty { break }
            all.append(contentsOf: response.projectAssignments)
            totalPages = response.totalPages
            currentPage += 1
        }

        return all
    }

    /// Validate credentials and get current user info.
    func getCurrentUser() async throws -> HarvestUser {
        let response: HarvestUserResponse = try await performRequest(endpoint: "/users/me")
        return HarvestUser(
            id: response.id,
            firstName: response.firstName,
            lastName: response.lastName,
            email: response.email
        )
    }

    // MARK: - Generic Request

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw HarvestAPIError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw HarvestAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accountId, forHTTPHeaderField: "Harvest-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HarvestPlus", forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        // Retry logic for rate limiting
        var retryCount = 0
        let maxRetries = 3

        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                // Offline / timeout / DNS throws a bare URLError. Wrap it as a
                // typed network error so callers (poll / fetchInitialData) can
                // flip to the .offline state – otherwise the URLError slips past
                // their `as? HarvestAPIError` check and the app looks "connected"
                // with stale data.
                throw HarvestAPIError.networkError(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw HarvestAPIError.networkError(
                    NSError(domain: "HarvestAPI", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response"
                    ])
                )
            }

            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)

                    // Try ISO 8601 with time
                    if let date = ISO8601DateFormatter().date(from: dateString) {
                        return date
                    }
                    // Try ISO 8601 with fractional seconds
                    let isoFractional = ISO8601DateFormatter()
                    isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = isoFractional.date(from: dateString) {
                        return date
                    }
                    // Try date-only format
                    let dateOnly = DateFormatter()
                    dateOnly.dateFormat = "yyyy-MM-dd"
                    dateOnly.locale = Locale(identifier: "en_US_POSIX")
                    if let date = dateOnly.date(from: dateString) {
                        return date
                    }

                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Cannot decode date: \(dateString)"
                    )
                }

                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw HarvestAPIError.decodingError(error)
                }

            case 401, 403:
                // 401 = bad/missing token; 403 = token revoked or lacking scope.
                // Both mean these credentials won't work, so surface as
                // unauthorized and let the app disconnect rather than treating
                // it as a transient server error.
                throw HarvestAPIError.unauthorized

            case 429:
                retryCount += 1
                if retryCount > maxRetries {
                    throw HarvestAPIError.rateLimited
                }
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) } ?? Double(retryCount * 2)
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                continue

            case 404:
                throw HarvestAPIError.notFound

            default:
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                throw HarvestAPIError.serverError(httpResponse.statusCode, bodyString)
            }
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Internal Response Types

private struct ProjectsResponse: Codable {
    let projects: [HarvestProject]
    let totalPages: Int
    let page: Int
    enum CodingKeys: String, CodingKey {
        case projects
        case totalPages = "total_pages"
        case page
    }
}

private struct TaskAssignmentsResponse: Codable {
    let taskAssignments: [TaskAssignment]
    let totalPages: Int
    let page: Int
    enum CodingKeys: String, CodingKey {
        case taskAssignments = "task_assignments"
        case totalPages = "total_pages"
        case page
    }
}

private struct ProjectAssignmentsResponse: Codable {
    let projectAssignments: [ProjectAssignment]
    let totalPages: Int
    let page: Int
    enum CodingKeys: String, CodingKey {
        case projectAssignments = "project_assignments"
        case totalPages = "total_pages"
        case page
    }
}

// MARK: - API Errors

enum HarvestAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case rateLimited
    case notFound
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .unauthorized:
            return "Invalid credentials. Check your Account ID and API token."
        case .rateLimited:
            return "Rate limited by Harvest. Please wait a moment."
        case .notFound:
            return "Resource not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .serverError(let code, let body):
            return "Server error (\(code)): \(body)"
        }
    }
}
