//
//  UpdateSection.swift
//  HarvestPlus
//
//  Settings row that shows the current version, the last update-check result,
//  and (when applicable) a one-click "Copy Install Command" button. Embedded
//  in GeneralSettingsTab under the "About" section.
//
//  We don't download the update in-app — the app is sandboxed and can't
//  replace its own bundle cleanly. Instead the user pastes a curl | bash
//  one-liner into Terminal, which handles quit → replace → relaunch.
//

import SwiftUI

struct UpdateSection: View {
    @ObservedObject var checker: UpdateChecker

    /// Briefly flips to `true` after the user clicks "Copy Install Command",
    /// so the button label can say "Copied ✓" for a couple of seconds.
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
        .animation(.easeInOut(duration: 0.2), value: justCopied)
    }

    // MARK: - Action button
    //
    // Three states:
    //   - idle, no update    → "Check for Updates"
    //   - idle, update ready → "Copy Install Command" (flips to "Copied ✓" briefly)
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
                Button(justCopied ? "Copied ✓" : "Copy Install Command") {
                    copyInstallCommand()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(justCopied)
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

                // Install instructions — the button above copies this; we
                // show it inline so the user knows what they just copied.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste this into Terminal to install:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UpdateChecker.installCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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

    private func copyInstallCommand() {
        _ = checker.copyInstallCommand()
        justCopied = true
        // Revert the label after a short delay so repeated copies still work.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            justCopied = false
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
