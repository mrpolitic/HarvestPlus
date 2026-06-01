//
//  DashboardColors.swift
//  HarvestPlus
//
//  Shared coloring for the dashboard heat-map grids (monthly + yearly).
//  These two views had a near-identical `heatmapColor` helper; they're
//  unified here. The single difference between them – the minimum opacity
//  for a worked cell – is exposed as a parameter so each grid keeps its
//  exact previous appearance.
//

import SwiftUI

enum DashboardChartColor {

    /// Fill color for one heat-map cell.
    ///
    /// Non-working days (weekends + public holidays) always render in the
    /// neutral gray ramp – even when hours were logged – so the grid
    /// visually separates scheduled work days from days off at a glance.
    /// Worked days scale up the brand orange by `intensity` (0...1), floored
    /// at `minWorkedOpacity` so the lightest worked day is still visible.
    static func heatmap(
        intensity: Double,
        isNonWorking: Bool,
        minWorkedOpacity: Double
    ) -> Color {
        if isNonWorking {
            return Color(.separatorColor).opacity(intensity > 0 ? 0.35 : 0.08)
        }
        if intensity == 0 {
            return Color(.separatorColor).opacity(0.15)
        }
        return AppColor.harvestOrange.opacity(max(minWorkedOpacity, min(intensity, 1.0)))
    }
}
