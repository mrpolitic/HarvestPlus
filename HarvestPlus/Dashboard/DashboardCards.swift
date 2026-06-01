//
//  DashboardCards.swift
//  HarvestPlus
//
//  Reusable dashboard card views: the metric card (delta + sparkline),
//  stacked project-composition bar, smart-insights panel, project-trends
//  list, and the highlight row. Split out of the former
//  DashboardComponents.swift.
//

import SwiftUI

// MARK: - Metric Card

/// A dashboard stat card: title, big value, an optional delta-vs-previous
/// badge, and an optional sparkline under the value.
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    /// Percent change vs previous period; nil means "no comparison available".
    var deltaPercent: Double? = nil
    /// Sparkline values for a mini trend chart. Empty = no sparkline.
    var sparkline: [Double] = []
    /// Short explanation shown on hover.
    var tooltip: String? = nil

    private var deltaColor: Color {
        guard let d = deltaPercent else { return .secondary }
        if d > 2 { return Color(red: 0.20, green: 0.70, blue: 0.40) }
        if d < -2 { return AppColor.harvestRed }
        return .secondary
    }

    private var deltaString: String {
        DashboardMetrics.formatPercentChange(deltaPercent)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if deltaPercent != nil {
                HStack(spacing: 3) {
                    if let d = deltaPercent {
                        Image(systemName: d > 0 ? "arrow.up.right" : (d < 0 ? "arrow.down.right" : "arrow.right"))
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(deltaString)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .foregroundStyle(deltaColor)
            }

            if !sparkline.isEmpty {
                SparklineView(values: sparkline, color: color)
                    .frame(height: 20)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.sm)
        .harvestSurface(cornerRadius: AppRadius.md)
        .help(tooltip ?? "")
    }
}

// MARK: - Project Composition Bar

/// Horizontal stacked bar showing the share of each project for a period.
/// Handles single / empty projects gracefully. Rounded only on the outermost edges.
struct ProjectCompositionBar: View {
    let projects: [ProjectSummary]
    var height: CGFloat = 28
    /// When true, shows "No data" placeholder when projects is empty.
    var showEmptyState: Bool = true

    private var totalHours: Double {
        projects.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if projects.isEmpty {
                if showEmptyState {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.separatorColor).opacity(0.15))
                        .frame(height: height)
                        .overlay(
                            Text("No projects logged")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        )
                }
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let total = totalHours

                    HStack(spacing: 1) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            let share = total > 0 ? project.hours / total : 0
                            let segWidth = max(share * w, projects.count > 1 ? 2 : 0)
                            let isFirst = index == 0
                            let isLast = index == projects.count - 1

                            Rectangle()
                                .fill(ProjectPalette.color(for: project.id))
                                .frame(width: segWidth, height: height)
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: isFirst ? 6 : 0,
                                        bottomLeadingRadius: isFirst ? 6 : 0,
                                        bottomTrailingRadius: isLast ? 6 : 0,
                                        topTrailingRadius: isLast ? 6 : 0
                                    )
                                )
                                .help("\(project.name) – \(TimeFormat.clock(project.hours)) (\(Int((share * 100).rounded()))%)")
                        }
                    }
                }
                .frame(height: height)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(projects) { project in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ProjectPalette.color(for: project.id))
                                .frame(width: 10, height: 10)
                            Text(project.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(TimeFormat.clock(project.hours))
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

}

// MARK: - Smart Insights Card

/// Auto-generated insight bullets at the top of a dashboard period.
/// Silent when there are no insights so it doesn't take up empty space.
struct SmartInsightsCard: View {
    let insights: [DashboardInsight]
    var title: String = "Insights"

    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color(red: 0.95, green: 0.77, blue: 0.06))
                    Text(title)
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insights) { insight in
                        // - Fixed 22pt icon column so narrow glyphs (star) and
                        //   wide ones (briefcase, grid.2x2) all left-align the
                        //   text at the same x.
                        // - Icon font matches the text so strokes read as the
                        //   same visual weight.
                        // - `.firstTextBaseline` sits the icon on the text's
                        //   baseline, which looks right for a single-line row
                        //   and degrades cleanly if a row wraps to two lines.
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: insight.icon)
                                .foregroundStyle(insight.accent)
                                .font(.callout)
                                .frame(width: 22, alignment: .center)
                            Text(insight.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .harvestSurface(cornerRadius: AppRadius.md)
        }
    }
}

// MARK: - Project Trends List

/// A compact list of projects and their period-over-period changes.
struct ProjectTrendsCard: View {
    let trends: [ProjectTrend]
    var title: String = "Project Trends"
    var comparisonLabel: String  // e.g. "vs last week"
    var maxRows: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(comparisonLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if trends.isEmpty {
                Text("No projects in this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(trends.prefix(maxRows))) { trend in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ProjectPalette.color(for: trend.id))
                            .frame(width: 8, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.name)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(TimeFormat.clock(trend.currentHours)) now · \(TimeFormat.clock(trend.previousHours)) before")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: trend.direction.symbol)
                                .font(.caption)
                                .foregroundStyle(trend.direction.color)
                            Text(trendLabel(trend))
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(trend.direction.color)
                        }
                        .frame(width: 80, alignment: .trailing)
                    }

                    if trend.id != trends.prefix(maxRows).last?.id {
                        Divider()
                    }
                }
            }
        }
        // Stretch so the surrounding card always fills the column width,
        // even when the only content is the empty-state line.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    private func trendLabel(_ trend: ProjectTrend) -> String {
        switch trend.direction {
        case .new: return "new"
        case .gone: return "–"
        case .steady: return "steady"
        case .up, .down:
            guard let p = trend.percentChange else { return "steady" }
            let rounded = Int(p.rounded())
            let sign = rounded > 0 ? "+" : "−"
            return "\(sign)\(abs(rounded))%"
        }
    }

}

// MARK: - Highlight Row

/// Single colored callout row, used for highlight callouts.
struct HighlightRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .fontWeight(.semibold)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
    }
}
