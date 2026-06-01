//
//  IntegrationsSettingsTab.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
//
//  Integrations settings: the Harvest connection (account ID + personal
//  access token, with test / save) and calendar access for the meeting
//  overlay.
//

import SwiftUI
import EventKit

// MARK: - Integrations Settings Tab

struct IntegrationsSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var accountId: String = ""
    @State private var apiToken: String = ""
    @State private var isTokenVisible: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult? = nil
    @State private var isSaved: Bool = false

    // Calendar
    @State private var isRequestingCalendarAccess: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Harvest Section
                harvestSection

                Divider()

                // Calendar Section
                calendarSection
            }
            .padding(20)
        }
        .onAppear {
            loadCredentials()
            appState.calendarService.refreshStatus()
        }
    }

    // MARK: - Harvest Section

    private var harvestSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Harvest", systemImage: "clock.badge.checkmark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Enter your Harvest Account ID and a personal access token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppColor.meetingBlue)
                        .imageScale(.small)
                        .padding(.top, 1)

                    Text("At [id.getharvest.com/developers](https://id.getharvest.com/developers), use the **Personal access tokens** section – not OAuth2 applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Account ID
            VStack(alignment: .leading, spacing: 4) {
                Text("Account ID")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("Your Harvest Account ID", text: $accountId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)
            }

            // API Token
            VStack(alignment: .leading, spacing: 4) {
                Text("API Token")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if isTokenVisible {
                            TextField("Your personal access token", text: $apiToken)
                        } else {
                            SecureField("Your personal access token", text: $apiToken)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isTokenVisible ? "Hide token" : "Show token")
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(accountId.isEmpty || apiToken.isEmpty || isTesting)

                Button("Save") {
                    saveCredentials()
                }
                .disabled(accountId.isEmpty || apiToken.isEmpty)
                .keyboardShortcut(.defaultAction)

                if isSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(AppColor.harvestGreen)
                        .transition(.opacity)
                }
            }

            // Test result
            if let result = testResult {
                testResultView(result)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Calendar", systemImage: "calendar")
                .font(.headline)

            Text("Show calendar events on the daily timeline. Uses calendars from System Settings → Internet Accounts (Outlook, Google, iCloud, etc.).")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Authorization status
            calendarAuthStatus

            // Calendar picker (when authorized)
            if appState.calendarService.isAuthorized {
                calendarPicker
            }
        }
    }

    @ViewBuilder
    private var calendarAuthStatus: some View {
        let service = appState.calendarService

        if service.isAuthorized {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.harvestGreen)
                Text("Calendar access granted")
                    .font(.callout)
            }
        } else if service.authorizationStatus == .notDetermined {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(AppColor.meetingBlue)
                    Text("Calendar access not yet granted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isRequestingCalendarAccess = true
                    Task {
                        _ = await service.requestAccess()
                        isRequestingCalendarAccess = false
                        if service.isAuthorized {
                            appState.refreshTodayMeetings()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRequestingCalendarAccess {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Grant Access")
                    }
                }
                .disabled(isRequestingCalendarAccess)
            }
        } else {
            // Denied, restricted, or writeOnly
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.harvestRed)
                    Text("Calendar access denied")
                        .font(.callout)
                }

                Text("Grant access in **System Settings → Privacy & Security → Calendars → HarvestPlus**.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show events from:")
                .font(.callout)
                .foregroundStyle(.secondary)

            let grouped = Dictionary(grouping: appState.calendarService.availableCalendars, by: \.accountName)

            ForEach(grouped.keys.sorted(), id: \.self) { account in
                VStack(alignment: .leading, spacing: 6) {
                    Text(account)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    ForEach(grouped[account] ?? []) { cal in
                        let isEnabled = appState.calendarService.enabledCalendarIds.contains(cal.id)

                        Toggle(isOn: Binding(
                            get: { isEnabled },
                            set: { newValue in
                                appState.calendarService.setCalendarEnabled(cal.id, enabled: newValue)
                                appState.refreshTodayMeetings()
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(cal.color)
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                                    .font(.callout)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(AppSpacing.md)
        .harvestSurface(cornerRadius: AppRadius.md)
    }

    // MARK: - Test Result View

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isSuccess ? AppColor.harvestGreen : AppColor.harvestRed)

            Text(result.message)
                .font(.callout)
                .foregroundStyle(result.isSuccess ? .primary : AppColor.harvestRed)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(result.isSuccess
                      ? AppColor.harvestGreen.opacity(0.1)
                      : AppColor.harvestRed.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func loadCredentials() {
        // Read from the in-memory cache on AppState – avoids a keychain ACL
        // check (and the password prompt it can trigger) on every tab appear.
        // AppState loads from the keychain exactly once at launch and keeps
        // the values in memory for the lifetime of the app.
        accountId = appState.settings.harvestAccountId
        apiToken  = appState.harvestToken
    }

    private func saveCredentials() {
        // Trim – pasted tokens/account ids routinely carry a trailing newline or
        // stray spaces, which would otherwise be saved verbatim and produce a
        // baffling 401 later.
        let cleanAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccountId.isEmpty, !cleanToken.isEmpty else {
            testResult = TestResult(isSuccess: false, message: "Account ID and API token can't be empty.")
            return
        }
        // Reflect the cleaned values back so the field shows what was actually saved.
        accountId = cleanAccountId
        apiToken = cleanToken

        do {
            // Save the token FIRST. If it throws, the stored account id is still
            // the old one – so we never end up with a new account id paired to a
            // stale/absent token (which would build a broken client on next launch).
            try KeychainHelper.save(key: KeychainKey.harvestToken, string: cleanToken)
            try KeychainHelper.save(key: KeychainKey.harvestAccountId, string: cleanAccountId)
            appState.settings.harvestAccountId = cleanAccountId

            withAnimation {
                isSaved = true
            }
            // Initialize the API client in AppState
            appState.initializeHarvestClient(accountId: cleanAccountId, token: cleanToken)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { isSaved = false }
            }
        } catch {
            testResult = TestResult(isSuccess: false, message: "Failed to save: \(error.localizedDescription)")
        }
    }

    private func testConnection() {
        let cleanAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccountId.isEmpty, !cleanToken.isEmpty else { return }

        isTesting = true
        testResult = nil

        let client = HarvestAPIClient(accountId: cleanAccountId, token: cleanToken)

        Task {
            do {
                let user = try await client.getCurrentUser()
                await MainActor.run {
                    testResult = TestResult(
                        isSuccess: true,
                        message: "Connected as \(user.fullName) (\(user.email))"
                    )
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = TestResult(
                        isSuccess: false,
                        message: error.localizedDescription
                    )
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Test Result

private struct TestResult {
    let isSuccess: Bool
    let message: String
}
