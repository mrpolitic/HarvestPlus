//
//  FeedbackSettingsTab.swift
//  HarvestPlus
//
//  In-app feedback form. Submissions are sent to a Web3Forms endpoint that
//  forwards them to the maintainer's inbox. The maintainer's email never
//  appears in the app bundle — only the public Web3Forms access key, which
//  is rate-limited on the service side.
//
//  Free-tier limits at time of writing:
//    250 submissions / month
//    Attachments up to 5 MB
//
//  How to rotate the access key:
//    1. Generate a new key at https://web3forms.com
//    2. Replace FeedbackService.accessKey below
//    3. Ship a new build — the old key keeps working for users on older
//       versions until their app updates, so no submission is lost.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Feedback Settings Tab

struct FeedbackSettingsTab: View {
    @State private var category: FeedbackCategory = .general
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var attachmentURL: URL?
    @State private var attachmentError: String?
    @State private var isSending: Bool = false
    @State private var sendResult: SendResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                categoryRow
                subjectRow
                messageRow
                attachmentRow
                Divider()
                sendRow
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Send Feedback", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Text("Found a bug, want to suggest a feature, or have something else to share? Send it directly to the maintainer. We auto-attach your app version and macOS version so you don't have to.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text("What we collect:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Link("Privacy Policy", destination: URL(string: "https://github.com/mrpolitic/HarvestPlus/blob/main/PRIVACY.md")!)
                    .font(.caption)
            }
        }
    }

    // MARK: - Category

    private var categoryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: $category) {
                ForEach(FeedbackCategory.allCases) { c in
                    Text("\(c.symbol)  \(c.rawValue)").tag(c)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)
        }
    }

    // MARK: - Subject

    private var subjectRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subject")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Optional — e.g. \"Crash when stopping a timer\"", text: $subject)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Message

    private var messageRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Message")
                .font(.callout)
                .foregroundStyle(.secondary)

            // TextField with axis: .vertical gives us multi-line input
            // *and* AppKit-rendered placeholder — the placeholder sits at
            // the exact text origin, no overlay-alignment guesswork. The
            // line limit range gives a stable initial height (7 lines)
            // that grows to a max of 12 lines before scrolling.
            TextField(placeholder, text: $message, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(7...12)
                .font(.body)
        }
    }

    private var placeholder: String {
        switch category {
        case .bug:
            return "What were you doing when the bug happened? What did you expect, and what actually happened? Steps to reproduce help a lot."
        case .feature:
            return "Describe the feature, who it would help, and what problem it solves."
        case .general:
            return "Anything you'd like to share — workflow ideas, kind words, complaints, etc."
        }
    }

    // MARK: - Attachment

    private var attachmentRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attachment (optional)")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Choose File…") { pickAttachment() }

                if let url = attachmentURL {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            attachmentURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove attachment")
                    }
                } else {
                    Text("Max 5 MB. Screenshots, logs, PDFs, zip files.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let err = attachmentError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(AppColor.harvestRed)
            }
        }
    }

    // MARK: - Send

    private var sendRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSending ? "Sending…" : "Send Feedback")
                }
                .frame(minWidth: 110)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSend || isSending)

            if let result = sendResult {
                resultBadge(result)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: sendResult)
        .animation(.easeInOut(duration: 0.2), value: isSending)
    }

    @ViewBuilder
    private func resultBadge(_ result: SendResult) -> some View {
        switch result {
        case .success:
            Label("Sent. Thank you!", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(AppColor.harvestGreen)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(AppColor.harvestRed)
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pick attachment

    private func pickAttachment() {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.title = "Attach a file"
        panel.message = "Pick a screenshot, log, PDF, or other file to include."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image, .pdf, .plainText, .json, .zip,
            UTType("public.log") ?? .data,
            .data
        ]

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        // Enforce the Web3Forms free-tier 5 MB attachment limit. Better to
        // refuse client-side than have the POST silently fail at 5.0001 MB.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64,
           size > 5 * 1024 * 1024 {
            attachmentError = "That file is larger than 5 MB. Try compressing it first."
            return
        }
        attachmentURL = url
    }

    // MARK: - Submit

    private func send() async {
        isSending = true
        sendResult = nil
        defer { isSending = false }

        do {
            try await FeedbackService.submit(
                category: category,
                subject: subject,
                message: message,
                attachmentURL: attachmentURL
            )
            sendResult = .success
            // Clear form for the next submission.
            subject = ""
            message = ""
            attachmentURL = nil
        } catch {
            sendResult = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Category

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug      = "Bug Report"
    case feature  = "Feature Request"
    case general  = "General Feedback"

    var id: String { rawValue }

    /// Symbol shown in the picker. Plain emoji so it renders consistently
    /// regardless of SF Symbols version.
    var symbol: String {
        switch self {
        case .bug:     return "🐞"
        case .feature: return "💡"
        case .general: return "💬"
        }
    }

    /// Short tag used as the email subject prefix so the maintainer's
    /// inbox is auto-filterable.
    var subjectTag: String {
        switch self {
        case .bug:     return "Bug"
        case .feature: return "Feature"
        case .general: return "Feedback"
        }
    }
}

// MARK: - Result

private enum SendResult: Equatable {
    case success
    case failure(String)
}
