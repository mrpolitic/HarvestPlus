//
//  DashboardBarChart.swift
//  HarvestPlus
//
//  The shared daily-hours bar chart (with its Y-axis tick helper) and the
//  compact sparkline. Split out of the former DashboardComponents.swift.
//

import SwiftUI

// MARK: - Chart Axis
//
// Small helper for picking "nice" round tick values on a bar chart Y axis.
// Pulled out so both the Weekly (days) and Yearly (months) bar charts show
// the same scale format instead of having no Y scale at all.

enum ChartAxis {
    /// Returns rounded tick values and a rounded max that comfortably contains
    /// `maxValue`. Uses the classic 1 / 2 / 5 × 10ⁿ scale and aims for about
    /// `targetTicks` labels. The returned `ticks` array always starts at 0 and
    /// ends at `niceMax`, so `niceMax` is what the chart should scale bars to.
    static func niceTicks(upTo maxValue: Double, targetTicks: Int = 5) -> (ticks: [Double], niceMax: Double) {
        // Degenerate input → a single tick at 0 and a visible 1h ceiling so
        // empty-week charts still render a Y scale.
        guard maxValue > 0 else { return ([0, 1], 1) }

        let roughStep = maxValue / Double(targetTicks)
        let magnitude = pow(10, floor(log10(roughStep)))
        let normalized = roughStep / magnitude

        let niceStep: Double
        if normalized <= 1 { niceStep = 1 * magnitude }
        else if normalized <= 2 { niceStep = 2 * magnitude }
        else if normalized <= 5 { niceStep = 5 * magnitude }
        else { niceStep = 10 * magnitude }

        let niceMax = ceil(maxValue / niceStep) * niceStep

        var ticks: [Double] = []
        var v = 0.0
        // Small epsilon guard against floating-point drift from repeated addition.
        while v <= niceMax + niceStep * 0.001 {
            ticks.append(v)
            v += niceStep
        }
        return (ticks, niceMax)
    }

    /// Short hour label for a tick – "0h", "10h", "0.5h", etc.
    /// Whole-hour values drop the decimal; sub-hour values keep one.
    static func tickLabel(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        if hours >= 1, hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }
}

// MARK: - Dashboard Bar Chart
//
// Shared bar chart used by the Weekly and Yearly dashboards. Previously both
// views drew bars inline with no Y-axis labels, so users could only read a
// bar's value by hovering it. This centralises:
//
// - A Y-axis scale on the left (rounded to nice-number ticks) so "tall" and
//   "short" bars can be read as actual hours at a glance.
// - Horizontal dashed gridlines at each tick to anchor mid-scale bars.
// - Per-bar color, tooltip, and axis-label styling so callers keep full
//   control of "best", "current", etc. highlighting.
//
// The caller still owns all highlighting rules; this view is purely layout +
// scale rendering.

struct DashboardBarChart: View {
    struct Bar: Identifiable {
        let id: Int
        let value: Double
        let color: Color
        let tooltip: String
        let axisLabel: String
        /// Color for the bottom-axis label – Weekly paints "today" orange,
        /// Yearly paints the current month orange.
        var axisLabelColor: Color = .secondary
        var axisLabelBold: Bool = false
    }

    let bars: [Bar]
    var chartHeight: CGFloat = 160
    var barSpacing: CGFloat = 8
    var cornerRadius: CGFloat = 4
    var yAxisWidth: CGFloat = 32
    var bottomAxisHeight: CGFloat = 16
    var axisLabelFont: Font = .caption

    var body: some View {
        if bars.isEmpty {
            Color.clear.frame(height: chartHeight + bottomAxisHeight + 6)
        } else {
            // Single top-level GeometryReader measures the full card width once.
            // We then hand *explicit* widths to every child – no nested flex
            // layout, no HStack maxWidth distribution, no chance of SwiftUI
            // collapsing the plot area to intrinsic size and centering it
            // inside the card. The x-coordinate of bar `i` and label `i` are
            // literally the same arithmetic expression below.
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let plotWidth = max(0, totalWidth - yAxisWidth)
                let bw = Self.barWidth(plotWidth: plotWidth, count: bars.count, spacing: barSpacing)
                let rawMax = bars.map(\.value).max() ?? 0
                let (ticks, niceMax) = ChartAxis.niceTicks(upTo: max(rawMax, 0.5))

                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        yAxisColumn(ticks: ticks, niceMax: niceMax)
                            .frame(width: yAxisWidth, height: chartHeight)
                        plotBody(ticks: ticks, niceMax: niceMax, plotWidth: plotWidth, bw: bw)
                            .frame(width: plotWidth, height: chartHeight)
                    }
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: yAxisWidth, height: bottomAxisHeight)
                        axisLabelsRow(plotWidth: plotWidth, bw: bw)
                            .frame(width: plotWidth, height: bottomAxisHeight)
                    }
                }
            }
            .frame(height: chartHeight + bottomAxisHeight + 6)
        }
    }

    // MARK: Sub-views

    private func yAxisColumn(ticks: [Double], niceMax: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: yAxisWidth, height: chartHeight)

            ForEach(Array(ticks.enumerated()), id: \.element) { _, tick in
                let fraction = niceMax > 0 ? CGFloat(1 - tick / niceMax) : 0
                Text(ChartAxis.tickLabel(tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: yAxisWidth - 6, alignment: .trailing)
                    .position(x: (yAxisWidth - 6) / 2, y: fraction * chartHeight)
            }
        }
    }

    private func plotBody(ticks: [Double], niceMax: Double, plotWidth: CGFloat, bw: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Gridlines – solid at 0 baseline, dashed above.
            ForEach(Array(ticks.enumerated()), id: \.element) { _, tick in
                let fraction = niceMax > 0 ? CGFloat(1 - tick / niceMax) : 0
                Path { p in
                    p.move(to: CGPoint(x: 0, y: fraction * chartHeight))
                    p.addLine(to: CGPoint(x: plotWidth, y: fraction * chartHeight))
                }
                .stroke(
                    Color(.separatorColor).opacity(tick == 0 ? 0.45 : 0.18),
                    style: StrokeStyle(lineWidth: 1, dash: tick == 0 ? [] : [3, 3])
                )
            }

            // Bars – x is `idx * (bw + spacing) + bw/2`, identical to the
            // label row below. No flex layout involved.
            ForEach(Array(bars.enumerated()), id: \.element.id) { idx, bar in
                let barHeight: CGFloat = bar.value > 0
                    ? max(4, CGFloat(bar.value / niceMax) * chartHeight)
                    : 0
                if barHeight > 0 {
                    let centerX = CGFloat(idx) * (bw + barSpacing) + bw / 2
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(bar.color)
                        .frame(width: bw, height: barHeight)
                        .position(x: centerX, y: chartHeight - barHeight / 2)
                        .help(bar.tooltip)
                }
            }
        }
    }

    private func axisLabelsRow(plotWidth: CGFloat, bw: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { idx, bar in
                let centerX = CGFloat(idx) * (bw + barSpacing) + bw / 2
                Text(bar.axisLabel)
                    .font(axisLabelFont)
                    .foregroundStyle(bar.axisLabelColor)
                    .fontWeight(bar.axisLabelBold ? .bold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: bw)
                    .position(x: centerX, y: bottomAxisHeight / 2)
            }
        }
    }

    private static func barWidth(plotWidth: CGFloat, count: Int, spacing: CGFloat) -> CGFloat {
        let n = max(count, 1)
        let totalSpacing = spacing * CGFloat(n - 1)
        return max(1, (plotWidth - totalSpacing) / CGFloat(n))
    }
}

// MARK: - Sparkline

/// Compact line chart – passes through a list of values and draws a smooth path.
/// If all values are equal, draws a centered flat line so the view never disappears.
struct SparklineView: View {
    let values: [Double]
    var color: Color = AppColor.harvestOrange
    var fill: Bool = true
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if values.count < 2 {
                // Single point / no data: centered horizontal line so layout is stable
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h / 2))
                    path.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(color.opacity(0.3), lineWidth: lineWidth)
            } else {
                let maxVal = values.max() ?? 1
                let minVal = values.min() ?? 0
                let range = max(maxVal - minVal, 0.001)
                let step = w / CGFloat(values.count - 1)

                ZStack {
                    if fill {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h))
                            for (i, v) in values.enumerated() {
                                let x = CGFloat(i) * step
                                let y = h - CGFloat((v - minVal) / range) * h
                                if i == 0 {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    Path { path in
                        for (i, v) in values.enumerated() {
                            let x = CGFloat(i) * step
                            let y = h - CGFloat((v - minVal) / range) * h
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
