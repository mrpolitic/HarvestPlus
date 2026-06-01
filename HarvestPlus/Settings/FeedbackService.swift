//
//  FeedbackService.swift
//  HarvestPlus
//
//  Posts an in-app feedback submission to Web3Forms, which forwards it to
//  the maintainer's inbox. No backend of our own — Web3Forms hides the
//  destination email behind a public access key.
//
//  Why Web3Forms vs. mailto: vs. GitHub Issues?
//    - mailto: would put the maintainer's email in the app bundle. No.
//    - GitHub Issues would require a GitHub account from every reporter.
//    - Web3Forms: zero infrastructure, hides the email, free tier covers
//      250 submissions/month with attachments up to 5 MB.
//
//  Access keys are designed to be embedded in client code. Worst-case spam
//  is rate-limited at 250/month by the service; rotate the key by
//  generating a new one and shipping a build if it ever becomes an issue.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum FeedbackService {

    // MARK: - Configuration

    /// Public Web3Forms access key. Tied to the maintainer's inbox on
    /// the Web3Forms side. Safe to embed; not a secret.
    static let accessKey = "132c71a6-2630-4585-ba52-0973787bf40c"

    private static let endpoint = URL(string: "https://api.web3forms.com/submit")!

    // MARK: - Submit

    /// Send a feedback submission. Throws if the request fails or Web3Forms
    /// returns a non-success response.
    static func submit(
        category: FeedbackCategory,
        subject: String,
        message: String,
        attachmentURL: URL?
    ) async throws {
        var multipart = MultipartBody()
        multipart.addField("access_key", accessKey)
        multipart.addField("from_name", "HarvestPlus user")
        multipart.addField("subject", emailSubject(category: category, subject: subject))
        multipart.addField("message", emailBody(category: category, message: message))

        if let url = attachmentURL {
            let data = try Data(contentsOf: url)
            let mime = mimeType(for: url)
            multipart.addFile(
                name: "attachment",
                filename: url.lastPathComponent,
                mimeType: mime,
                data: data
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = multipart.finalize()
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.network("No HTTP response from server.")
        }

        // Trust the HTTP status code. Web3Forms returns 2xx when the
        // submission is accepted and forwarded, and 4xx with a JSON
        // error body when it's rejected (rate limit, invalid key, etc.).
        // Parsing the JSON `success` field was brittle (`NSNumber`/`Bool`
        // bridging) and didn't tell us anything the status code didn't.
        if (200..<300).contains(http.statusCode) {
            return
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let serverMessage = (json?["message"] as? String)
            ?? "Server returned HTTP \(http.statusCode)."
        throw FeedbackError.network(serverMessage)
    }

    // MARK: - Email formatting

    private static func emailSubject(category: FeedbackCategory, subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmed.isEmpty ? "HarvestPlus feedback" : trimmed
        return "[\(category.subjectTag)] \(suffix)"
    }

    private static func emailBody(category: FeedbackCategory, message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Category: \(category.rawValue)

        \(trimmedMessage)

        ────────────────────────────
        App version : \(appVersion) (build \(buildNumber))
        macOS       : \(osVersion)
        Architecture: \(architecture)
        Locale      : \(Locale.current.identifier)
        Time zone   : \(TimeZone.current.identifier)
        """
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "unknown"
        #endif
    }

    // MARK: - MIME detection

    /// Best-effort MIME type for the attachment so Web3Forms (and the
    /// recipient's mail client) handle it as the right kind of file.
    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

// MARK: - Errors

enum FeedbackError: LocalizedError {
    case network(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        }
    }
}

// MARK: - Multipart body builder

/// Builds an RFC 7578 multipart/form-data body. Web3Forms requires this
/// format when a file attachment is included; we use it for all submissions
/// for consistency.
private struct MultipartBody {
    private let boundary: String = "----HarvestPlus-\(UUID().uuidString)"
    private var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        appendString("\r\n")
    }

    mutating func finalize() -> Data {
        appendString("--\(boundary)--\r\n")
        return data
    }

    private mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { data.append(d) }
    }
}
