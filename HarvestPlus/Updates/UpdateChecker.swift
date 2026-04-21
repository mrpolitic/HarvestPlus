//
//  UpdateChecker.swift
//  HarvestPlus
//
//  Lightweight GitHub-Releases-based updater.
//
//  Why not Sparkle?
//  ----------------
//  HarvestPlus is sandboxed and distributed as a .pkg. Sparkle's self-install
//  flow requires XPC services and temporary sandbox exceptions, which adds
//  complexity we don't need for an internal tool. Instead we:
//
//    1. Poll `api.github.com/repos/<owner>/<repo>/releases/latest`
//    2. Compare the published tag to our CFBundleShortVersionString (semver)
//    3. If newer, download the `.pkg` asset to ~/Downloads
//    4. Reveal it in Finder so the user double-clicks to install
//
//  The .pkg is ad-hoc signed (no Apple Developer Program) — users right-click
//  → Open the downloaded installer once; the postinstall script then strips
//  the quarantine flag so subsequent app launches are prompt-free.
//
//  The GitHub HTTPS URL is the trust anchor for the download itself.
//

import Foundation
import AppKit
import Combine

// MARK: - Public surface

enum UpdateCheckResult: Equatable {
    /// Running the latest version (or a newer prerelease).
    case upToDate(current: String)
    /// A newer version is available.
    case updateAvailable(UpdateInfo)
    /// Network / decoding / rate-limit failure. `message` is user-safe.
    case failed(message: String)
}

struct UpdateInfo: Equatable {
    let version: String           // e.g. "1.2.0"
    let releaseName: String       // e.g. "HarvestPlus 1.2.0"
    let releaseNotes: String      // Markdown body from GitHub release
    let publishedAt: Date
    let downloadURL: URL          // .pkg asset URL
    let downloadSize: Int64       // bytes
    let htmlURL: URL              // release landing page on GitHub
}

// MARK: - Checker

@MainActor
final class UpdateChecker: ObservableObject {
    // MARK: - Configuration

    /// GitHub `owner/repo` for the release feed. Update this once you publish
    /// the repository. A placeholder means "update checker is effectively disabled"
    /// (it will return a friendly "not configured" failure rather than 404).
    static let repository = "mrpolitic/HarvestPlus"

    /// Daily auto-check interval. The network call itself is cheap — the
    /// concern is polite rate-limiting of the GitHub API.
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    /// UserDefaults key that records the timestamp of the last successful check.
    private static let lastCheckKey = "lastUpdateCheckAt"

    // MARK: - Published state

    @Published private(set) var state: State = .idle
    @Published private(set) var lastResult: UpdateCheckResult?
    @Published private(set) var downloadProgress: Double = 0

    enum State: Equatable {
        case idle
        case checking
        case downloading
    }

    // MARK: - Public API

    /// Current app version from Info.plist (`CFBundleShortVersionString`).
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Short build number from Info.plist (`CFBundleVersion`). Shown next to
    /// the version string in Settings for debugging.
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Manually trigger a check. Safe to call repeatedly — no-ops if already running.
    func checkForUpdates() async {
        guard state == .idle else { return }
        guard Self.repository != "YOUR_GITHUB_USER/HarvestPlus" else {
            lastResult = .failed(message: "Update checker not configured (no GitHub repository set).")
            return
        }

        state = .checking
        defer { state = .idle }

        do {
            let release = try await fetchLatestRelease()
            let latestVersion = normalized(release.tag_name)
            let current = normalized(currentVersion)

            if compareSemver(latestVersion, current) == .orderedDescending {
                guard let asset = release.pkgAsset() else {
                    lastResult = .failed(message: "Release \(release.tag_name) has no .pkg asset.")
                    return
                }
                guard let htmlURL = URL(string: release.html_url),
                      let downloadURL = URL(string: asset.browser_download_url) else {
                    lastResult = .failed(message: "Release asset URL is invalid.")
                    return
                }
                lastResult = .updateAvailable(UpdateInfo(
                    version: latestVersion,
                    releaseName: release.name ?? "HarvestPlus \(latestVersion)",
                    releaseNotes: release.body ?? "",
                    publishedAt: release.publishedDate ?? Date(),
                    downloadURL: downloadURL,
                    downloadSize: Int64(asset.size),
                    htmlURL: htmlURL
                ))
            } else {
                lastResult = .upToDate(current: currentVersion)
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        } catch {
            lastResult = .failed(message: error.localizedDescription)
        }
    }

    /// Called once on app launch. Runs a background check if >24h have elapsed
    /// since the last successful check. Never blocks launch.
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        let isDue = last == nil || Date().timeIntervalSince(last!) >= Self.autoCheckInterval
        guard isDue else { return }
        Task { await checkForUpdates() }
    }

    /// Download the `.pkg`, save to ~/Downloads, reveal in Finder. Returns the
    /// file URL on success; throws on failure.
    @discardableResult
    func downloadAndReveal(_ info: UpdateInfo) async throws -> URL {
        guard state != .downloading else {
            throw UpdateError.alreadyDownloading
        }
        state = .downloading
        downloadProgress = 0
        defer {
            state = .idle
            downloadProgress = 0
        }

        let (tempURL, response) = try await URLSession.shared.download(from: info.downloadURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.downloadFailed("Server returned an unexpected response.")
        }

        // Move to ~/Downloads with a stable, collision-proof filename.
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let targetName = "HarvestPlus-\(info.version).pkg"
        let targetURL = uniqueDestination(folder: downloads, preferredName: targetName)

        try FileManager.default.moveItem(at: tempURL, to: targetURL)
        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        return targetURL
    }

    /// Open the release page in the user's browser — fallback when the .pkg
    /// download fails, or when the user prefers to read the release notes first.
    func openReleasePage(_ info: UpdateInfo) {
        NSWorkspace.shared.open(info.htmlURL)
    }

    // MARK: - Helpers

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network("No HTTP response.")
        }
        switch http.statusCode {
        case 200: break
        case 404: throw UpdateError.network("No releases published yet.")
        case 403: throw UpdateError.network("GitHub rate limit reached — try again later.")
        default:  throw UpdateError.network("GitHub returned HTTP \(http.statusCode).")
        }
        do {
            return try JSONDecoder.githubDecoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.decoding("Couldn't parse the release feed.")
        }
    }

    /// Strip a leading "v" (or "V") from a tag like "v1.2.3" to yield "1.2.3".
    private func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, first == "v" || first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    /// Lexicographic semver comparison. Treats missing components as 0
    /// (so "1.2" == "1.2.0"). Non-numeric components (e.g. "1.2.0-beta.1")
    /// sort lower than pure-numeric so a release supersedes its own prerelease.
    private func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> (numeric: [Int], tail: String?) {
            let split = s.split(separator: "-", maxSplits: 1).map(String.init)
            let base = split[0]
            let tail = split.count > 1 ? split[1] : nil
            let nums = base.split(separator: ".").map { Int($0) ?? 0 }
            return (nums, tail)
        }
        let (na, ta) = parts(a)
        let (nb, tb) = parts(b)
        let maxLen = max(na.count, nb.count)
        for i in 0..<maxLen {
            let ai = i < na.count ? na[i] : 0
            let bi = i < nb.count ? nb[i] : 0
            if ai != bi { return ai < bi ? .orderedAscending : .orderedDescending }
        }
        // Stable release > prerelease of the same base.
        switch (ta, tb) {
        case (nil, nil):         return .orderedSame
        case (nil, _?):          return .orderedDescending
        case (_?, nil):          return .orderedAscending
        case (let x?, let y?):   return x.compare(y)
        default:                 return .orderedSame
        }
    }

    private func uniqueDestination(folder: URL, preferredName: String) -> URL {
        var candidate = folder.appendingPathComponent(preferredName)
        var counter = 1
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = "\(base) (\(counter)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case network(String)
    case decoding(String)
    case downloadFailed(String)
    case alreadyDownloading

    var errorDescription: String? {
        switch self {
        case .network(let msg),
             .decoding(let msg),
             .downloadFailed(let msg):  return msg
        case .alreadyDownloading:       return "A download is already in progress."
        }
    }
}

// MARK: - GitHub Releases decoding

/// Minimal shape of the GitHub Release JSON. We only decode what we need;
/// GitHub's full payload is huge.
private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var publishedDate: Date? {
        guard let s = published_at else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    /// First asset whose filename ends in .pkg. If the release accidentally
    /// ships multiple .pkg assets, we take the first — release authors should
    /// publish only one.
    func pkgAsset() -> Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".pkg") }
    }

    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: String
    }
}

private extension JSONDecoder {
    /// Shared decoder used by UpdateChecker — keeps snake_case field names
    /// verbatim because GitHub's API uses them and we mirror that in the
    /// private model above.
    static let githubDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
}
