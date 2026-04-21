//
//  UpdateSection.swift
//  HarvestPlus
//
//  Settings row that shows the current version, the last update-check result,
//  and (when applicable) a one-click button to download + install an update.
//  Embedded in GeneralSettingsTab under the "About" section.
//

import SwiftUI

struct UpdateSection: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Version line — always visible.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HarvestPlus")
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("Version \(checker.currentVersion) (\(checker.currentBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                actionButton
            }

            // Result line — only when there is something interesting to say.
            if let result = checker.lastResult {
                resultRow(result)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: checker.state)
        .animation(.easeInOut(duration: 0.2), value: checker.lastResult)
    }

    // MARK: - Action button
    //
    // Three states:
    //   - idle           → "Check for Updates"
    //   - checking       → progress spinner + "Checking…"
    //   - downloading    → determinate progress + "Downloading…"
    //
    // When an update is available, the action switches from "Check" to
    // "Download & Install" — minimising clicks.
    @ViewBuilder
    private var actionButton: some View {
        switch checker.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: checker.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .idle:
            if case .updateAvailable(let info) = checker.lastResult {
                Button("Download & Install") {
                    downloadAndInstall(info)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Check for Updates") {
                    Task { await checker.checkForUpdates() }
                }
            }
        }
    }

    // MARK: - Result line

    @ViewBuilder
    private func resultRow(_ result: UpdateCheckResult) -> some View {
        switch result {
        case .upToDate:
            Label("You're on the latest version.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(AppColor.harvestGreen)

        case .updateAvailable(let info):
            VStack(alignment: .leading, spacing: 6) {
                Label("Version \(info.version) is available.", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.meetingBlue)

                if !info.releaseNotes.isEmpty {
                    Text(info.releaseNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("View on GitHub") {
                        checker.openReleasePage(info)
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(formatSize(info.downloadSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppColor.harvestRed)
        }
    }

    // MARK: - Actions

    private func downloadAndInstall(_ info: UpdateInfo) {
        Task {
            do {
                _ = try await checker.downloadAndReveal(info)
                // The Finder now has the .pkg selected. The user double-clicks
                // to install; no further in-app step needed.
            } catch {
                // Silent failure is fine — the user can retry. We surface the
                // error in `lastResult` via openReleasePage fallback if they prefer.
                checker.openReleasePage(info)
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
