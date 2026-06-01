//
//  DesignSystem.swift
//  HarvestPlus
//
//  Design tokens + Liquid Glass surface treatment for the entire app.
//
//  Everything that renders a card, panel, or container should route through
//  `.harvestSurface(...)` so the Liquid Glass setting can be flipped in one
//  place and every surface in the app responds consistently.
//

import SwiftUI

// MARK: - Radius Tokens

/// Corner radii used across the app. Cards normally land on `.md`; the banner
/// and hero surfaces use `.lg`; pills and chips use `.xs`.
enum AppRadius {
    static let xs: CGFloat = 6     // pills, small badges
    static let sm: CGFloat = 8     // small cards, buttons
    static let md: CGFloat = 10    // standard cards
    static let lg: CGFloat = 14    // banner, hero containers
    static let xl: CGFloat = 18    // window-level rounds
}

// MARK: - Spacing Tokens

/// Shared spacing scale. Prefer these over raw numbers for horizontal/vertical
/// paddings and stack spacing.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Project Color Palette
//
// Canonical project palette lives in `Dashboard/DashboardMetrics.swift` as
// `ProjectPalette` and is reused here by `PopoverView`, `EntryRow`, and
// `TimelineBar` (which previously each had their own divergent copy).

// MARK: - Surface Prominence

/// How strongly a surface should read. Affects the flat (non-glass) fallback
/// and could affect the glass variant in future iterations.
enum SurfaceProminence {
    /// Default card (popover timer card, dashboard metric card, etc.).
    case standard
    /// Hero areas or actionable top-level containers.
    case prominent
    /// Subtle inline containers (e.g., stat chips inside a card).
    case subtle
}

// MARK: - Surface Modifier (Liquid Glass + flat fallback)

extension View {
    /// The app's canonical container background.
    ///
    /// - When the user has Liquid Glass enabled (default), applies
    ///   `.glassEffect(in:)` – the macOS 26 translucent, reflective material.
    /// - When disabled, falls back to a flat `controlBackgroundColor` fill
    ///   at the same corner radius.
    ///
    /// Replace any `.background(RoundedRectangle(...).fill(Color(.controlBackgroundColor)))`
    /// with `.harvestSurface(cornerRadius: AppRadius.md)`.
    func harvestSurface(
        cornerRadius: CGFloat = AppRadius.md,
        prominence: SurfaceProminence = .standard
    ) -> some View {
        modifier(HarvestSurfaceModifier(
            cornerRadius: cornerRadius,
            prominence: prominence
        ))
    }

    /// A subtle elevation shadow appropriate for floating panels (banner, etc.)
    /// Skipped when Liquid Glass is on – glass already conveys elevation.
    func harvestFloatingShadow() -> some View {
        modifier(HarvestFloatingShadowModifier())
    }
}

struct HarvestSurfaceModifier: ViewModifier {
    // @AppStorage so any view picks up toggle changes without needing AppState
    // in its environment – matters for NSHostingView-hosted views like the
    // banner, which don't inherit SwiftUI environment.
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled: Bool = true

    let cornerRadius: CGFloat
    let prominence: SurfaceProminence

    func body(content: Content) -> some View {
        // `.glassEffect(in:)` is macOS 26+. The app's deployment target is lower
        // (see `MACOSX_DEPLOYMENT_TARGET`), so we availability-gate it and fall
        // back to the flat surface on older systems. On macOS 26+ the user's
        // toggle decides; on earlier systems the toggle is effectively ignored
        // and we always render the flat variant.
        if liquidGlassEnabled, #available(macOS 26.0, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(flatFillColor)
                )
        }
    }

    private var flatFillColor: Color {
        switch prominence {
        case .standard:  return Color(.controlBackgroundColor)
        case .prominent: return Color(.controlBackgroundColor)
        case .subtle:    return Color(.controlBackgroundColor).opacity(0.6)
        }
    }
}

struct HarvestFloatingShadowModifier: ViewModifier {
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled: Bool = true

    func body(content: Content) -> some View {
        // Match the decision in `HarvestSurfaceModifier`: only skip the shadow
        // when glass is *actually* being applied. On pre-macOS-26 systems the
        // toggle is set but no glass is drawn, so the banner still needs an
        // explicit shadow to feel elevated.
        if liquidGlassEnabled, #available(macOS 26.0, *) {
            content
        } else {
            content.shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
    }
}
