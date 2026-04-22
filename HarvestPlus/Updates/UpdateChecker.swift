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
//    3. If newer, show the release notes + a one-click "Copy Install Command"
//       button. The user pastes that command into Terminal; the installer
//       script replaces /Applications/HarvestPlus.app in place and relaunches.
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

    /// Run the installer in a new Terminal window.
    ///
    /// Writes a short `.command` script to the app's temporary directory that
    /// invokes `installCommand`, then hands it to Terminal via LaunchServices.
    /// macOS opens `.command` files in Terminal by default, so the user sees
    /// live install progress in a new window — no AppleEvents entitlement
    /// required (unlike `tell application "Terminal" to do script …`).
    ///
    /// Throws if the script file can't be written.
    func launchInstaller() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let cmdFile = tmpDir.appendingPathComponent("install-harvestplus-\(UUID().uuidString).command")

        // Heredoc-style bash — avoids tricky escaping of the curl command.
        let script = """
        #!/bin/bash
        # HarvestPlus self-installer — generated by the app's update checker.
        clear
        printf '\\033[1;34m==>\\033[0m Installing the latest HarvestPlus…\\n\\n'
        \(Self.installCommand)
        status=$?
        echo
        if [ $status -eq 0 ]; then
            printf '\\033[1;32m✓\\033[0m Install complete. You can close this window.\\n'
        else
            printf '\\033[1;31m✗\\033[0m Install failed. Scroll up for details.\\n'
        fi
        """

        try script.write(to: cmdFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: cmdFile.path
        )

        // Prefer opening the file explicitly with Terminal.app — that way the
        // install still works for users whose default .command handler is
        // something else (iTerm, a text editor, …).
        let terminalPath = "/System/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: terminalPath) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [cmdFile],
                withApplicationAt: URL(fileURLWithPath: terminalPath),
                configuration: config,
                completionHandler: nil
            )
        } else {
            // Fall back to whatever app is registered for .command.
            NSWorkspace.shared.open(cmdFile)
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
