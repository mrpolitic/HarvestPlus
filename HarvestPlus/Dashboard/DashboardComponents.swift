//
//  DashboardComponents.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 21/04/2026.
//
//  Reusable SwiftUI views for dashboards: enhanced metric card with
//  period-over-period delta + sparkline, stacked project composition bar,
//  smart insights panel, project trends list.

import SwiftUI

// MARK: - Shared Formatters (hoisted to avoid per-render allocation)

private let componentDayMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f
}()

// MARK: - Cumulative Pace Chart
//
// Shared line-area chart showing `(date, cumulative)` pairs relative to a zero
// baseline. Used by the Monthly and Yearly dashboards. Renders:
//
//   - Y-axis scale labels at min, zero, and max (previously only "0h" showed,
//     giving the user no sense of magnitude).
//   - Hover crosshair + floating tooltip revealing the exact date and signed
//     hours at the nearest data point (previously the chart was inert — no
//     way to read intermediate values).
//
// The caller supplies the bottom axis (a trailing `ViewBuilder`) so the
// Monthly variant can show two end labels and the Yearly variant can show
// twelve evenly-spaced month names.

struct CumulativePaceChart<BottomAxis: View>: View {
    let data: [(date: Date, cumulative: Double)]
    var chartHeight: CGFloat = 160
    var emptyMessage: String = "No data yet"
    @ViewBuilder let bottomAxis: () -> BottomAxis

    @State private var hoverIndex: Int?

    // Semantic colors for the two zones:
    // - above baseline (cumulative > 0) → "ahead" / overtime → orange (brand)
    // - below baseline (cumulative < 0) → "behind" → red (warning)
    private let aheadColor: Color = AppColor.harvestOrange
    private let behindColor: Color = AppColor.harvestRed

    var body: some View {
        if data.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            VStack(spacing: 6) {
                chartBody
                    .frame(height: chartHeight)
                bottomAxis()
            }
        }
    }

    private var chartBody: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let values = data.map(\.cumulative)
            // Pad the bounds so a chart with values clustered near zero still
            // has visible amplitude. Matches the prior implementation.
            let dataMax = values.max() ?? 0
            let dataMin = values.min() ?? 0
            let maxVal = max(dataMax, 0.5)
            let minVal = min(dataMin, -0.5)
            let range = maxVal - minVal
            let zeroY = height * (maxVal / range)
            // Only label extremes when real data reaches them, not the padding clamp
            let showMaxLabel = dataMax > 0
            let showMinLabel = dataMin < 0

            ZStack(alignment: .topLeading) {
                // ---- Zero baseline (dashed) ----
                Path { path in
                    path.move(to: CGPoint(x: 0, y: zeroY))
                    path.addLine(to: CGPoint(x: width, y: zeroY))
                }
                .stroke(Color(.separatorColor).opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // ---- Y-axis scale labels (top, zero, bottom) ----
                // `.position` sets the label's *center*. The labels sit 18pt in
                // from the left inside the chart so they don't shift the plot
                // origin.
                if showMaxLabel {
                    Text(Self.formatHoursSigned(maxVal))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.regularMaterial))
                        .position(x: 28, y: 10)
                }

                // Baseline label — "On track" reads in plain English where the
                // previous "0h" demanded the user understand the axis math.
                // Hidden when it would collide with either extreme label.
                if zeroY > 26 && zeroY < height - 14 {
                    Text("On track")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.regularMaterial))
                        .position(x: 34, y: zeroY - 10)
                }

                if showMinLabel {
                    Text(Self.formatHoursSigned(minVal))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.regularMaterial))
                        .position(x: 28, y: height - 10)
                }

                // ---- Line + fill ----
                // Fill uses a single vertical gradient with a HARD STOP at
                // zeroY so the enclosed area reads as orange (ahead) above and
                // red (behind) below without needing two separate clipped paths.
                lineFill(width: width, height: height,
                         maxVal: maxVal, range: range, zeroY: zeroY)

                // Line stroke with the same zoned color scheme. A linear
                // gradient stops exactly at the baseline so the segment above
                // uses aheadColor and below uses behindColor.
                linePath(width: width, height: height,
                         maxVal: maxVal, range: range)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: aheadColor, location: 0),
                                .init(color: aheadColor, location: max(0, min(1, zeroY / height))),
                                .init(color: behindColor, location: max(0, min(1, zeroY / height))),
                                .init(color: behindColor, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )

                // ---- Current value label (right edge, pilled for contrast) ----
                if let last = data.last {
                    let lastY = height * (maxVal - last.cumulative) / range
                    Text(Self.formatHoursSigned(last.cumulative))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(last.cumulative >= 0 ? aheadColor : behindColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.regularMaterial))
                        .position(x: width - 40, y: max(14, min(lastY - 14, height - 14)))
                }

                // ---- Hover crosshair + tooltip ----
                if let idx = hoverIndex, idx < data.count {
                    let point = data[idx]
                    let x = Self.pointX(index: idx, count: data.count, width: width)
                    let y = height * (maxVal - point.cumulative) / range

                    // Vertical guide
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    .stroke(Color.primary.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    // Point marker — color by which side of the baseline we're on
                    let markerColor: Color = point.cumulative >= 0 ? aheadColor : behindColor
                    Circle()
                        .fill(markerColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.5))
                        .position(x: x, y: y)

                    // Floating tooltip — anchored above the marker when possible,
                    // flipped below when the marker is near the top so it doesn't
                    // clip out of the chart area.
                    let tooltipAbove = y > 36
                    HoverTooltip(date: point.date, cumulative: point.cumulative)
                        .position(
                            x: min(max(x, 60), width - 60),
                            y: tooltipAbove ? max(y - 28, 14) : min(y + 28, height - 14)
                        )
                }
            }
            .contentShape(Rectangle()) // Hover should register over the whole plot area.
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let idx = Self.nearestIndex(x: location.x, width: width, count: data.count)
                    hoverIndex = idx
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }

    // MARK: Path helpers (kept as functions so the ZStack body stays readable)

    private func linePath(width: CGFloat, height: CGFloat, maxVal: Double, range: Double) -> Path {
        Path { path in
            for (index, point) in data.enumerated() {
                let x = Self.pointX(index: index, count: data.count, width: width)
                let y = height * (maxVal - point.cumulative) / range
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func lineFill(width: CGFloat, height: CGFloat, maxVal: Double, range: Double, zeroY: CGFloat) -> some View {
        // Vertical gradient with a hard stop at zeroY paints orange above the
        // baseline and red below. Because the path always closes against the
        // baseline, any filled region only occupies one zone at a time — so
        // the user reads "orange area = ahead, red area = behind" at a glance.
        let stopFraction = max(0, min(1, zeroY / height))
        let gradient = LinearGradient(
            stops: [
                .init(color: aheadColor.opacity(0.28), location: 0),
                .init(color: aheadColor.opacity(0.08), location: stopFraction),
                .init(color: behindColor.opacity(0.08), location: stopFraction),
                .init(color: behindColor.opacity(0.28), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        return Path { path in
            for (index, point) in data.enumerated() {
                let x = Self.pointX(index: index, count: data.count, width: width)
                let y = height * (maxVal - point.cumulative) / range
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: zeroY))
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            let lastX = Self.pointX(index: data.count - 1, count: data.count, width: width)
            path.addLine(to: CGPoint(x: lastX, y: zeroY))
            path.closeSubpath()
        }
        .fill(gradient)
    }

    // MARK: Static helpers

    private static func pointX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(index) / CGFloat(max(count - 1, 1))
    }

    private static func nearestIndex(x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard count > 1, width > 0 else { return 0 }
        let normalized = max(0, min(1, x / width))
        let raw = Int(round(normalized * CGFloat(count - 1)))
        return max(0, min(count - 1, raw))
    }

    private static func formatHoursSigned(_ hours: Double) -> String {
        // Round once at minute precision so this stays consistent with
        // PaceStatusCaption — truncating (h then .frac*60) drifts by ~1 min
        // near half-minute values versus rounding the total minute count.
        let totalMinutes = Int((hours * 60).rounded())
        let sign = totalMinutes > 0 ? "+" : (totalMinutes < 0 ? "−" : "")
        let abs = Swift.abs(totalMinutes)
        let h = abs / 60
        let m = abs % 60
        if h == 0 && m == 0 { return "0h" }
        if h == 0 { return "\(sign)\(m)m" }
        if m == 0 { return "\(sign)\(h)h" }
        return String(format: "%@%dh %02dm", sign, h, m)
    }
}

/// One-line plain-English status caption shown above the Cumulative Pace
/// chart. Replaces the earlier "Hours above/below baseline" phrasing with
/// something a first-time viewer can read without understanding the axis.
///
/// - `latest`: the rightmost cumulative value (positive = ahead, negative
///   = behind). `nil` hides the caption entirely.
/// - `periodNoun`: "this month", "this year", etc. — inserted at the end.
struct PaceStatusCaption: View {
    let latest: Double?
    let periodNoun: String

    var body: some View {
        if let latest = latest {
            // Round once at minute precision — avoids boundary jumps you'd get
            // from rounding to tenths-of-an-hour and then re-splitting into
            // h/m (e.g. 1.95 → "2h" but 1.94 → "1h 54m").
            let totalMinutes = Int((latest * 60).rounded())
            if abs(totalMinutes) < 5 {
                Text("Right on track \(periodNoun)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if totalMinutes > 0 {
                (
                    Text("You're ")
                        .foregroundStyle(.secondary)
                    + Text(Self.magnitude(minutes: totalMinutes)).fontWeight(.semibold)
                        .foregroundStyle(AppColor.harvestOrange)
                    + Text(" ahead \(periodNoun)")
                        .foregroundStyle(.secondary)
                )
                .font(.caption)
            } else {
                (
                    Text("You're ")
                        .foregroundStyle(.secondary)
                    + Text(Self.magnitude(minutes: -totalMinutes)).fontWeight(.semibold)
                        .foregroundStyle(AppColor.harvestRed)
                    + Text(" behind \(periodNoun)")
                        .foregroundStyle(.secondary)
                )
                .font(.caption)
            }
        }
    }

    private static func magnitude(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return String(format: "%dh %02dm", h, m)
    }
}

/// The floating date + value pill shown at the hover location.
private struct HoverTooltip: View {
    let date: Date
    let cumulative: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.dateLabel(date))
                .foregroundStyle(.secondary)
            Text(Self.hoursLabel(cumulative))
                .fontWeight(.semibold)
                .foregroundStyle(cumulative >= 0 ? AppColor.harvestOrange : AppColor.harvestRed)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(.regularMaterial)
        )
        .overlay(
            Capsule().stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private static func dateLabel(_ date: Date) -> String {
        return componentDayMonthFormatter.string(from: date)
    }

    private static func hoursLabel(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let sign = totalMinutes > 0 ? "+" : (totalMinutes < 0 ? "−" : "")
        let abs = Swift.abs(totalMinutes)
        let h = abs / 60
        let m = abs % 60
        if h == 0 && m == 0 { return "0h" }
        if h == 0 { return "\(sign)\(m)m" }
        if m == 0 { return "\(sign)\(h)h" }
        return String(format: "%@%dh %02dm", sign, h, m)
    }
}

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

    /// Short hour label for a tick — "0h", "10h", "0.5h", etc.
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
        /// Color for the bottom-axis label — Weekly paints "today" orange,
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
            // We then hand *explicit* widths to every child — no nested flex
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
            // Gridlines — solid at 0 baseline, dashed above.
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

            // Bars — x is `idx * (bw + spacing) + bw/2`, identical to the
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

/// Compact line chart — passes through a list of values and draws a smooth path.
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

// MARK: - Metric Card

/// Richer version of SummaryCard. Shows a title, a big value, optional delta-vs-previous
/// and optional sparkline under the value.
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
                                .help("\(project.name) — \(formatHoursCompact(project.hours)) (\(Int((share * 100).rounded()))%)")
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
                            Text(formatHoursCompact(project.hours))
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

    private func formatHoursCompact(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return String(format: "%d:%02d", h, m)
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
                            Text("\(formatHours(trend.currentHours)) now · \(formatHours(trend.previousHours)) before")
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
        .padding(AppSpacing.lg)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    private func trendLabel(_ trend: ProjectTrend) -> String {
        switch trend.direction {
        case .new: return "new"
        case .gone: return "—"
        case .steady: return "steady"
        case .up, .down:
            guard let p = trend.percentChange else { return "steady" }
            let rounded = Int(p.rounded())
            let sign = rounded > 0 ? "+" : "−"
            return "\(sign)\(abs(rounded))%"
        }
    }

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return String(format: "%d:%02d", h, m)
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
