//
//  UpdateSection.swift
//  HarvestPlus
//
//  Settings row that shows the current version, the last update-check result,
//  and (when applicable) a one-click "Install Update" button. Embedded in
//  GeneralSettingsTab under the "About" section.
//
//  Clicking "Install Update" opens Terminal and runs `install.sh` directly
//  (via a .command file in the sandbox tmp dir — see UpdateChecker).
//  The sandboxed app can't replace its own bundle in place, so we delegate
//  the quit → download → extract → relaunch dance to bash in Terminal.
//

import SwiftUI

struct UpdateSection: View {
    @ObservedObject var checker: UpdateChecker

    /// Briefly flips to `true` while Terminal is being launched, so the
    /// button can show "Opening Terminal…" and disable itself to prevent
    /// double-clicks that would stack Terminal windows.
    @State private var launching = false

    /// Briefly flips to `true` after a fallback "Copy Command" click. Used
    /// when `launchInstaller()` can't write the .command script for some
    /// reason and we gracefully fall back to clipboard.
    @State private var justCopied = false

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
        .animation(.easeInOut(duration: 0.2), value: launching)
        .animation(.easeInOut(duration: 0.2), value: justCopied)
    }

    // MARK: - Action button
    //
    // Three states:
    //   - idle, no update    → "Check for Updates"
    //   - idle, update ready → "Install Update" (opens Terminal and runs install.sh)
    //   - checking           → progress spinner + "Checking…"
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
        case .idle:
            if case .updateAvailable = checker.lastResult {
                Button(launching ? "Opening Terminal…" : "Install Update") {
                    installUpdate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(launching)
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
            VStack(alignment: .leading, spacing: 8) {
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

                    Text(formatSize(info.zipSize))
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

    private func installUpdate() {
        launching = true
        do {
            try checker.launchInstaller()
        } catch {
            // launchInstaller() failed to write the .command file (disk full?).
            // Fall back to copying the command so the user can still install.
            _ = checker.copyInstallCommand()
            justCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                justCopied = false
            }
        }
        // Reset the button label after a moment — Terminal is now open.
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            launching = false
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
