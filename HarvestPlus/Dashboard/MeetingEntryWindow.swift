//
//  MeetingEntryWindow.swift
//  HarvestPlus
//
//  Standalone window that hosts the MeetingEntrySheet when launched from
//  the menu-bar popover (which can't present sheets because it closes
//  on focus loss).
//

import SwiftUI

struct MeetingEntryWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let meeting = appState.pendingMeetingEntry {
                MeetingEntrySheet(
                    meeting: meeting,
                    onDismiss: {
                        appState.pendingMeetingEntry = nil
                        dismissWindow(id: "meeting-entry")
                    }
                )
                .environmentObject(appState)
            } else {
                // No meeting selected – auto-close.
                Color.clear
                    .onAppear { dismissWindow(id: "meeting-entry") }
            }
        }
    }
}
