//
//  UpdateSection.swift
//  HarvestPlus
//
//  Settings row that shows the current version and a "Check for Updates"
//  button. Sparkle owns the rest of the update UI – when the user clicks
//  the button, Sparkle's standard updater driver presents the "Update
//  Available" modal with release notes and progress.
//
//  Embedded in GeneralSettingsTab under the "About" section.
//

import SwiftUI

struct UpdateSection: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Button("Check for Updates…") {
                    checker.checkForUpdates()
                }
                .disabled(!checker.canCheckForUpdates)
            }

            Text("HarvestPlus checks for updates daily in the background and installs them silently the next time you quit the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
