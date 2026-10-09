import AppKit
import Foundation
import OTPGrabberMenuBarCore
import SwiftUI

@main
struct OTPGrabberMenuBarApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = StatusBarAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
private final class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model = PanelModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.title = "OTP"
        item.button?.toolTip = "OTP Grabber"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !model.showingGmailResult { Task { await model.refresh() } }
    }
}

@MainActor
private final class PanelModel: ObservableObject {
    private static let defaultGmailClientID = "704452847810-l2d2q73rrlaaugep1saj31njl17lnufk.apps.googleusercontent.com"

    @Published var headline = "Looking for a recent code…"
    @Published var detail = ""
    @Published var copied: CodeFinding?
    @Published var history: [Finding] = []
    @Published var clientID = UserDefaults.standard.string(forKey: "gmailClientID") ?? PanelModel.defaultGmailClientID
    @Published var gmailStatus = "Checking saved sign-in…"
    @Published var hasClientSecret = false
    @Published var connectingGmail = false
    @Published var showingGmailResult = false
    @Published var busy = false
    private let store = FindingsStore()

    init() {
        history = (try? store.history()) ?? []
        do { gmailStatus = try GmailRefreshTokenStore(clientID: clientID).load() == nil ? "Not connected" : "Sign-in saved" }
        catch let GmailAuthError.keychain(status) { gmailStatus = "Keychain error (OSStatus \(status))" }
        catch { gmailStatus = "Could not check saved sign-in" }
        hasClientSecret = (try? GmailClientSecretStore(clientID: clientID).load()) != nil
    }

    func saveClientID() {
        let previousID = UserDefaults.standard.string(forKey: "gmailClientID") ?? Self.defaultGmailClientID
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(clientID, forKey: "gmailClientID")
        hasClientSecret = (try? GmailClientSecretStore(clientID: clientID).load()) != nil
        if clientID != previousID {
            gmailStatus = (try? GmailRefreshTokenStore(clientID: clientID).load()) == nil ? "Not connected" : "Sign-in saved"
        }
        headline = "Gmail client ID saved"
        detail = "Choose Connect Gmail to sign in."
    }

    func connectGmail(newSecret: String = "") async {
        guard !connectingGmail else { return }
        connectingGmail = true
        showingGmailResult = true
        defer { connectingGmail = false }
        saveClientID()
        do {
            let secretStore = GmailClientSecretStore(clientID: clientID)
            let providedSecret = newSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !providedSecret.isEmpty { try secretStore.save(providedSecret) }
            guard try secretStore.load()?.isEmpty == false else {
                throw GmailAuthError.missingClientSecret
            }
            hasClientSecret = true
            let server = try OAuthCallbackServer()
            let request = try GmailOAuth.makeRequest(clientID: clientID, redirectURI: server.redirectURI)
            let provider = GmailTokenProvider(clientID: clientID)
            gmailStatus = "Waiting for Google in this Mac's browser…"
            headline = "Complete Gmail sign-in in your browser"
            detail = "Finish in a browser on this Mac, then reopen the OTP menu."
            guard NSWorkspace.shared.open(request.url) else { throw OAuthCallbackError.browserOpenFailed }
            let code = try await server.waitForCode(expectedState: request.state)
            try await provider.connect(code: code, request: request)
            gmailStatus = "Connected"
            headline = "Gmail connected"
            detail = "Open the panel again to look for a code."
        } catch {
            gmailStatus = "Sign-in failed: \(Self.gmailErrorMessage(error))"
            headline = "Gmail sign-in did not finish"
            detail = gmailStatus
        }
    }

    func refresh() async {
        guard !busy, !connectingGmail else { return }
        showingGmailResult = false
        busy = true
        copied = nil
        headline = "Looking for a recent code…"
        detail = ""
        let since = Date().addingTimeInterval(-86_400)
        async let messages = readMessages(since: since)
        async let gmail = readGmail(since: since)
        let (messageResult, gmailResult) = await (messages, gmail)
        if showingGmailResult { busy = false; return }
        var incoming: [Finding] = []
        var errors: [String] = []
        var sourceFailures = 0
        switch messageResult {
        case .success(let values): incoming += values
        case .failure(let error as MessagesReadError): sourceFailures += 1; errors.append(error.recoveryMessage)
        case .failure: sourceFailures += 1; errors.append("Messages could not be read.")
        }
        switch gmailResult {
        case .success(let values): incoming += values; gmailStatus = "Connected"
        case .failure(let error as GmailAuthError) where error == .signInRequired:
            sourceFailures += 1; errors.append("Connect Gmail in Settings.")
            if gmailStatus == "Connected" || gmailStatus == "Sign-in saved" {
                gmailStatus = "Reconnect Gmail in Settings"
            } else if !gmailStatus.hasPrefix("Sign-in failed") {
                gmailStatus = "Not connected"
            }
        case .failure(let error as GmailAuthError):
            sourceFailures += 1; errors.append("Gmail could not be read. Try again.")
            if case .keychain(let status) = error { gmailStatus = "Keychain error (OSStatus \(status))" }
            if error == .missingClientSecret { gmailStatus = "Add the desktop client secret in Settings" }
            if case .tokenRejected(_, let reason) = error, reason == "invalid_client" || reason == "invalid_request" {
                gmailStatus = "Update the desktop client secret in Settings and reconnect Gmail"
            }
        case .failure(let error as GmailReadError) where error == .signInRequired:
            sourceFailures += 1; errors.append("Reconnect Gmail in Settings."); gmailStatus = "Reconnect Gmail in Settings"
        case .failure: sourceFailures += 1; errors.append("Gmail could not be read. Try again.")
        }
        do { history = try store.save(incoming) }
        catch { errors.append("Recent history could not be saved.") }
        if let code = FindingSelection.newestCode(in: incoming, now: .now) {
            if copy(code.code) {
                copied = code
                headline = "Copied \(code.code)"
                detail = "\(code.source == .gmail ? "Gmail" : "Messages") · \(code.sender) · \(Self.age(code.receivedAt))"
            } else {
                headline = "Could not copy this code"
                detail = "The code or clipboard is unavailable."
            }
        } else {
            headline = sourceFailures == 2 ? "Sources unavailable" : sourceFailures == 1 ? "No code from available source" : "No recent code found"
            detail = "The clipboard was left unchanged."
        }
        if !errors.isEmpty { detail += "\n" + errors.joined(separator: " ") }
        busy = false
    }

    func copyManually(_ code: CodeFinding) {
        if copy(code.code) {
            headline = "Copied \(code.code)"
            detail = "\(code.source == .gmail ? "Gmail" : "Messages") · \(code.sender) · \(Self.age(code.receivedAt))"
        } else {
            headline = "Could not copy this code"
            detail = "The code or clipboard is unavailable."
        }
    }

    private func readMessages(since: Date) async -> Result<[Finding], Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try MessagesReader().read(since: since) }
        }.value
    }

    private func readGmail(since: Date) async -> Result<[Finding], Error> {
        do {
            guard !clientID.isEmpty else { throw GmailAuthError.signInRequired }
            let provider = GmailTokenProvider(clientID: clientID)
            let reader = GmailReader(token: { try await provider.accessToken() })
            return .success(try await reader.read(since: since))
        } catch { return .failure(error) }
    }

    private static func gmailErrorMessage(_ error: Error) -> String {
        if let auth = error as? GmailAuthError {
            switch auth {
            case .signInRequired:
                return "The saved sign-in expired. Try Connect Gmail again."
            case .authorizationRejected:
                return "Google rejected the authorization code. Try Connect Gmail again."
            case .missingRefreshToken:
                return "Google did not return a refresh token. Try Connect Gmail again."
            case .tokenRejected(let status, let reason):
                return "Google rejected the token request (\(reason), HTTP \(status))."
            case .keychain(let status):
                return "Keychain could not save the sign-in (OSStatus \(status))."
            case .invalidResponse:
                return "Google returned an unexpected token response."
            case .missingClientID:
                return "Enter a desktop OAuth client ID."
            case .missingClientSecret:
                return "Enter the desktop OAuth client secret in Settings."
            }
        }
        if let callback = error as? OAuthCallbackError {
            switch callback {
            case .listenerFailed: return "The local callback could not start."
            case .browserOpenFailed: return "The browser could not open."
            case .invalidCallback: return "Google returned an invalid callback."
            case .timedOut: return "The browser did not return within three minutes."
            }
        }
        return "Try again and check the browser result."
    }

    private func copy(_ value: String) -> Bool {
        guard let code = CopyCode.validated(value) else { return false }
        let pasteboard = NSPasteboard.general
        var canRestore = true
        let prior = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let snapshot = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), snapshot.setData(data, forType: type) else {
                    canRestore = false
                    continue
                }
            }
            return snapshot
        } ?? []
        guard canRestore else { return false }
        let newItem = NSPasteboardItem()
        guard newItem.setString(code, forType: .string) else { return false }
        pasteboard.clearContents()
        if pasteboard.writeObjects([newItem]) { return true }
        pasteboard.clearContents()
        if !prior.isEmpty { _ = pasteboard.writeObjects(prior) }
        return false
    }

    static func age(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) hr ago"
    }
}

private enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case gmail = "Gmail"
    case messages = "Messages"

    func includes(_ finding: Finding) -> Bool {
        switch self {
        case .all: true
        case .gmail: finding.source == .gmail
        case .messages: finding.source == .messages
        }
    }
}

private struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var clientSecret = ""
    @State private var historyExpanded = false
    @State private var settingsExpanded = false
    @State private var filter: HistoryFilter = .all
    private var visible: [Finding] { model.history.filter(filter.includes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("OTP Grabber").font(.headline)
                    Spacer()
                    Button("Settings") { settingsExpanded.toggle() }.buttonStyle(.plain)
                }
                Text("Gmail: \(model.gmailStatus)").font(.caption).foregroundStyle(.secondary)
                if settingsExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gmail desktop OAuth client ID").font(.caption)
                        TextField("Client ID", text: $model.clientID)
                        SecureField("Desktop OAuth client secret", text: $clientSecret)
                        Text(model.hasClientSecret ? "Client secret saved in Keychain" : "Enter the Desktop client secret from Google Auth Platform")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Save") { model.saveClientID() }
                            Button("Connect Gmail") {
                                let providedSecret = clientSecret
                                clientSecret = ""
                                Task { await model.connectGmail(newSecret: providedSecret) }
                            }
                                .disabled(model.connectingGmail)
                        }
                        Text("Messages needs Full Disk Access in System Settings.").font(.caption)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.headline).font(.title3).fontWeight(.semibold)
                    if !model.detail.isEmpty { Text(model.detail).font(.caption).foregroundStyle(.secondary) }
                    if let copied = model.copied, let url = copied.gmailURL {
                        Button("Open in Gmail") { NSWorkspace.shared.open(url) }
                    }
                }
                HStack {
                    Button("Refresh") { Task { await model.refresh() } }.disabled(model.busy)
                    Spacer()
                    Button(historyExpanded ? "Hide history" : "History") { historyExpanded.toggle() }
                }
                if historyExpanded {
                    Text("Last 24 hours").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(HistoryFilter.allCases, id: \.self) { item in
                            Button(item.rawValue) { filter = item }
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(filter == item ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .accessibilityValue(filter == item ? "Selected" : "Not selected")
                        }
                    }
                    if visible.isEmpty {
                        Text("No \(filter == .all ? "" : filter.rawValue + " ")findings in the last 24 hours.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(visible) { finding in
                        VStack(alignment: .leading, spacing: 7) {
                            switch finding {
                            case .code(let code):
                                HStack {
                                    Text(code.source == .gmail ? "Gmail" : "Messages").fontWeight(.semibold)
                                    Spacer()
                                    Text(PanelModel.age(code.receivedAt))
                                }.font(.caption)
                                Text(code.sender).font(.caption).lineLimit(1)
                                Text(code.code).font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                                HStack {
                                    Button("Copy") { model.copyManually(code) }
                                    if let url = code.gmailURL { Button("Open in Gmail") { NSWorkspace.shared.open(url) } }
                                }
                            case .resetLink(let link):
                                HStack {
                                    Text("Gmail · Password reset").fontWeight(.semibold)
                                    Spacer()
                                    Text(PanelModel.age(link.receivedAt))
                                }.font(.caption)
                                Text(link.sender).font(.caption).lineLimit(1)
                                Text(link.destinationDomain).font(.caption)
                                Button("Open reset link") { NSWorkspace.shared.open(link.url) }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.08)).cornerRadius(10)
                    }
                }
                Button("Quit OTP Grabber") { NSApp.terminate(nil) }.font(.caption)
            }
            .padding(18)
        }
        .frame(width: 360, height: 420)
    }
}
