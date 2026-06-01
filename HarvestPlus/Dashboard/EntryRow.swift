//
//  EntryRow.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  One row in a list of Harvest time entries: project color dot, project /
//  task, notes, and hours. Reused across the dashboard tabs.
//

import SwiftUI

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let entryRowTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

// MARK: - Entry Row

struct EntryRow: View {
    let entry: TimeEntry

    var body: some View {
        HStack(spacing: 10) {
            // Color dot
            Circle()
                .fill(projectColor)
                .frame(width: 10, height: 10)

            // Project & task
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayProjectName)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(entry.task.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Notes (if any)
            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

            // Time range
            if let started = entry.timerStartedAt {
                Text(timeRange(started: started))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Duration
            HStack(spacing: 4) {
                if entry.isRunning {
                    Circle()
                        .fill(AppColor.harvestGreen)
                        .frame(width: 6, height: 6)
                }

                Text(TimeFormat.clockExact(entry.hours))
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(entry.isRunning ? AppColor.harvestGreen : .primary)
            }
            .frame(width: 84, alignment: .trailing)
            // The green dot + color-only signal isn't enough for VoiceOver; tell
            // it in words that this entry's timer is running.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                entry.isRunning
                    ? "Running: \(TimeFormat.clockExact(entry.hours))"
                    : TimeFormat.clockExact(entry.hours)
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var projectColor: Color {
        ProjectPalette.color(for: entry.project.id)
    }


    private func timeRange(started: Date) -> String {
        let startStr = entryRowTimeFormatter.string(from: started)

        if entry.isRunning {
            return "\(startStr) - now"
        }

        let endDate = started.addingTimeInterval(entry.hours * 3600)
        let endStr = entryRowTimeFormatter.string(from: endDate)
        return "\(startStr) - \(endStr)"
    }
}
