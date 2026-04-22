//
//  UpdateChecker.swift
//  HarvestPlus
//
//  Lightweight GitHub-Releases-based updater.
//
//  Why not Sparkle?
//  ----------------
//  HarvestPlus is sandboxed. Sparkle's self-install flow needs XPC services
//  and temporary sandbox exceptions — more machinery than we need for an
//  internal tool.
//
//  The update flow:
//
//    1. Poll `api.github.com/repos/<owner>/<repo>/releases/latest`
//    2. Compare the published tag to our CFBundleShortVersionString (semver)
//    3. If newer, show the release notes + a one-click "Install Update" button.
//       Clicking it uses NSAppleScript to tell Terminal to run the install
//       one-liner directly — no file written, no quarantine issue.
//
//  Why not download-and-replace in-app?
//  ------------------------------------
//  The app is sandboxed, so it can't overwrite its own bundle in /Applications
//  without user approval anyway. And the downloaded .zip would inherit the
//  quarantine xattr if delivered via a browser-style download, triggering
//  Gatekeeper on relaunch. Running `curl ... | bash` in Terminal sidesteps
//  both problems: curl doesn't set quarantine, and the shell isn't sandboxed.
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
    let zipURL: URL               // .app.zip asset URL (kept for reference; not auto-downloaded)
    let zipSize: Int64            // bytes
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

    /// The Terminal one-liner we tell the user to paste. Defined once here so
    /// the Settings UI and this file can't drift out of sync.
    static let installCommand =
        "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/Scripts/install.sh | bash"

    /// UserDefaults key that records the timestamp of the last successful check.
    private static let lastCheckKey = "lastUpdateCheckAt"

    // MARK: - Published state

    @Published private(set) var state: State = .idle
    @Published private(set) var lastResult: UpdateCheckResult?

    enum State: Equatable {
        case idle
        case checking
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
                guard let asset = release.installerAsset() else {
                    lastResult = .failed(message: "Release \(release.tag_name) has no .app.zip asset.")
                    return
                }
                guard let htmlURL = URL(string: release.html_url),
                      let zipURL = URL(string: asset.browser_download_url) else {
                    lastResult = .failed(message: "Release asset URL is invalid.")
                    return
                }
                lastResult = .updateAvailable(UpdateInfo(
                    version: latestVersion,
                    releaseName: release.name ?? "HarvestPlus \(latestVersion)",
                    releaseNotes: release.body ?? "",
                    publishedAt: release.publishedDate ?? Date(),
                    zipURL: zipURL,
                    zipSize: Int64(asset.size),
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

    /// Copy the Terminal install one-liner to the general pasteboard. Returns
    /// the command string so the UI can show a confirmation toast.
    @discardableResult
    func copyInstallCommand() -> String {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Self.installCommand, forType: .string)
        return Self.installCommand
    }

    /// Run the installer in a new Terminal window using Apple Events.
    ///
    /// Tells Terminal to `do script` with the install one-liner directly — no
    /// file is written to disk, so macOS never applies `com.apple.quarantine`.
    /// Requires `com.apple.security.automation.apple-events` in the entitlements
    /// and `NSAppleEventsUsageDescription` in Info.plist.
    ///
    /// macOS shows a one-time consent dialog ("HarvestPlus wants to control
    /// Terminal.") the first time this runs. After the user clicks OK it is
    /// never asked again.
    ///
    /// Throws `UpdateError.network` if Terminal refuses the Apple Event.
    func launchInstaller() throws {
        // Build the AppleScript source. installCommand contains no quotes or
        // backslashes, so no additional escaping is needed.
        let source = """
        tell application "Terminal"
            activate
            do script "\(Self.installCommand)"
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            throw UpdateError.network("Couldn't create Terminal install script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let msg = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? "Terminal automation failed."
            throw UpdateError.network(msg)
        }
    }

    /// Open the release page in the user's browser — for users who'd rather
    /// read the notes or grab the .app.zip manually.
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
        }
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .network(let msg),
             .decoding(let msg):  return msg
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

    /// Match the .app.zip asset produced by Scripts/build.sh. We match on the
    /// ".app.zip" suffix specifically so we don't accidentally grab a source
    /// tarball that also ends in ".zip".
    func installerAsset() -> Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".app.zip") }
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
