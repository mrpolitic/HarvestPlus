//
//  BannerManager.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Banner Manager

@MainActor
final class BannerManager: ObservableObject {
    @Published var isVisible: Bool = false

    private var panel: BannerPanel?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var snoozeTimer: Timer?
    private var nudgeDelayTimer: Timer?
    private var isSnoozed: Bool = false
    private var isDismissed: Bool = false

    init(appState: AppState) {
        self.appState = appState
        observeTimerState()
    }

    // MARK: - State Observation

    private func observeTimerState() {
        guard let appState = appState else { return }

        appState.$timerState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleTimerStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleTimerStateChange(_ state: TimerState) {
        switch state {
        case .running:
            // Timer started — cancel any pending nudge, hide banner
            nudgeDelayTimer?.invalidate()
            nudgeDelayTimer = nil
            hideBanner()
            isDismissed = false
            isSnoozed = false

        case .stopped:
            // Cancel any existing pending nudge
            nudgeDelayTimer?.invalidate()
            nudgeDelayTimer = nil

            // Wait 30 seconds before showing nudge — gives the user time to start a new timer
            nudgeDelayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let appState = self.appState else { return }
                    // Re-check all conditions after the delay
                    if appState.timerState == .stopped
                        && appState.settings.workSchedule.isWorkingHours(at: Date())
                        && appState.settings.timerNudgeEnabled
                        && !self.isSnoozed
                        && !self.isDismissed {
                        self.showBanner(mode: .nudge)
                    }
                }
            }

        case .offline:
            nudgeDelayTimer?.invalidate()
            nudgeDelayTimer = nil
            hideBanner()
        }
    }

    // MARK: - Show / Hide

    func showBanner(mode: BannerMode) {
        guard let appState = appState else { return }

        // Per-mode width. The nudge is deliberately narrow so the view grows
        // taller — it reads as a calm, square-ish prompt rather than a strip.
        // The reactive modes get more width for their action rows.
        let bannerWidth = Self.preferredWidth(for: mode)

        let actions = BannerActions(
            onSnooze: { [weak self] in
                self?.snooze()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onStopTimer: { [weak self] in
                Task {
                    await self?.appState?.stopCurrentTimer()
                }
                self?.hideBanner()
            },
            onStopAndSubtractIdle: { [weak self] in
                Task {
                    await self?.appState?.stopAndSubtractIdleTime()
                }
                self?.hideBanner()
            },
            onKeepGoing: { [weak self] in
                self?.hideBanner()
            },
            onOpenHarvest: { [weak self] in
                PopoverView.openHarvestApp()
                self?.hideBanner()
            }
        )

        let snoozeMins = Int(appState.settings.snoozeDuration / 60)

        // Pin width via SwiftUI so the view can calculate the height it needs
        // given that width. No hard-coded min height — compact modes (nudge)
        // are free to settle into their natural square-ish proportions.
        let bannerView = BannerView(
            mode: mode,
            actions: actions,
            snoozeDurationMinutes: snoozeMins
        )
        .frame(width: bannerWidth)

        let hostingView = NSHostingView(rootView: bannerView)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let bannerHeight = max(fittingSize.height, 80)
        hostingView.frame = NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight)

        // Create panel if needed
        if panel == nil {
            panel = BannerPanel(contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight))
        }

        guard let panel = panel else { return }
        panel.setContentSize(NSSize(width: bannerWidth, height: bannerHeight))
        panel.contentView = hostingView

        // Position based on user preference
        if appState.settings.bannerPosition == .bottom {
            panel.positionAboveDock()
        } else {
            panel.positionBelowMenuBar()
        }

        // Animate in: start offscreen above, slide down
        let finalOrigin = panel.frame.origin
        let startOrigin = NSPoint(x: finalOrigin.x, y: finalOrigin.y + 60)
        panel.setFrameOrigin(startOrigin)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(finalOrigin)
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    func hideBanner() {
        guard let panel = panel, isVisible else { return }

        let currentOrigin = panel.frame.origin
        let targetOrigin = NSPoint(x: currentOrigin.x, y: currentOrigin.y + 60)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(targetOrigin)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            Task { @MainActor [weak self] in
                self?.isVisible = false
            }
        })
    }

    // MARK: - Snooze / Dismiss

    private func snooze() {
        isSnoozed = true
        hideBanner()

        let snoozeDuration = appState?.settings.snoozeDuration ?? 15 * 60

        snoozeTimer?.invalidate()
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: snoozeDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSnoozed = false
                // Re-check if banner should show
                if let state = self?.appState?.timerState {
                    self?.handleTimerStateChange(state)
                }
            }
        }
    }

    private func dismiss() {
        isDismissed = true
        hideBanner()
        // isDismissed resets on next timer start (see handleTimerStateChange)
    }

    // MARK: - Sizing

    /// Each mode has different content weight — nudge is minimal and wants a
    /// near-square footprint; the idle banner needs room for three buttons.
    private static func preferredWidth(for mode: BannerMode) -> CGFloat {
        let screenCap = (NSScreen.main?.frame.width ?? 1200) * 0.9
        let desired: CGFloat
        switch mode {
        case .nudge:           desired = 360   // narrow → grows tall, feels square-ish
        case .idle:            desired = 580   // 3 action buttons
        case .longTimer:       desired = 500   // 2 action buttons
        case .eodSummary,
             .eowSummary:      desired = 460   // stats row
        }
        return min(desired, screenCap)
    }

    deinit {
        snoozeTimer?.invalidate()
        nudgeDelayTimer?.invalidate()
    }
}
