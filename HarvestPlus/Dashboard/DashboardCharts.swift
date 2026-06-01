//
//  DashboardCharts.swift
//  HarvestPlus
//
//  The cumulative-pace line/area chart used by the Monthly and Yearly
//  dashboards, its plain-English status caption, and the hover tooltip.
//  Split out of the former 984-line DashboardComponents.swift.
//

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
//     hours at the nearest data point (previously the chart was inert – no
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
    // - above baseline (cumulative > 0) → "overtime" → orange (brand)
    // - below baseline (cumulative < 0) → "undertime" → red (warning)
    private let overtimeColor: Color = AppColor.harvestOrange
    private let undertimeColor: Color = AppColor.harvestRed

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

                // Baseline label – "On track" reads in plain English where the
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
                // zeroY so the enclosed area reads as orange (overtime) above and
                // red (undertime) below without needing two separate clipped paths.
                lineFill(width: width, height: height,
                         maxVal: maxVal, range: range, zeroY: zeroY)

                // Line stroke with the same zoned color scheme. A linear
                // gradient stops exactly at the baseline so the segment above
                // uses overtimeColor and below uses undertimeColor.
                linePath(width: width, height: height,
                         maxVal: maxVal, range: range)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: overtimeColor, location: 0),
                                .init(color: overtimeColor, location: max(0, min(1, zeroY / height))),
                                .init(color: undertimeColor, location: max(0, min(1, zeroY / height))),
                                .init(color: undertimeColor, location: 1),
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
                        .foregroundStyle(last.cumulative >= 0 ? overtimeColor : undertimeColor)
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

                    // Point marker – color by which side of the baseline we're on
                    let markerColor: Color = point.cumulative >= 0 ? overtimeColor : undertimeColor
                    Circle()
                        .fill(markerColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: 1.5))
                        .position(x: x, y: y)

                    // Floating tooltip – anchored above the marker when possible,
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
        // baseline, any filled region only occupies one zone at a time – so
        // the user reads "orange area = overtime, red area = undertime" at a glance.
        let stopFraction = max(0, min(1, zeroY / height))
        let gradient = LinearGradient(
            stops: [
                .init(color: overtimeColor.opacity(0.28), location: 0),
                .init(color: overtimeColor.opacity(0.08), location: stopFraction),
                .init(color: undertimeColor.opacity(0.08), location: stopFraction),
                .init(color: undertimeColor.opacity(0.28), location: 1),
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
        // PaceStatusCaption – truncating (h then .frac*60) drifts by ~1 min
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
/// - `latest`: the rightmost cumulative value (positive = overtime, negative
///   = undertime). `nil` hides the caption entirely.
/// - `periodNoun`: "this month", "this year", etc. – inserted at the end.
struct PaceStatusCaption: View {
    let latest: Double?
    let periodNoun: String

    var body: some View {
        if let latest = latest {
            // Round once at minute precision – avoids boundary jumps you'd get
            // from rounding to tenths-of-an-hour and then re-splitting into
            // h/m (e.g. 1.95 → "2h" but 1.94 → "1h 54m").
            let totalMinutes = Int((latest * 60).rounded())
            if abs(totalMinutes) < 5 {
                Text("Right on track \(periodNoun)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if totalMinutes > 0 {
                (
                    Text("You have ")
                        .foregroundStyle(.secondary)
                    + Text(Self.magnitude(minutes: totalMinutes)).fontWeight(.semibold)
                        .foregroundStyle(AppColor.harvestOrange)
                    + Text(" overtime \(periodNoun)")
                        .foregroundStyle(.secondary)
                )
                .font(.caption)
            } else {
                (
                    Text("You have ")
                        .foregroundStyle(.secondary)
                    + Text(Self.magnitude(minutes: -totalMinutes)).fontWeight(.semibold)
                        .foregroundStyle(AppColor.harvestRed)
                    + Text(" undertime \(periodNoun)")
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

