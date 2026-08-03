import AppKit
import Foundation
import OTPGrabberMenuBarCore

@main
struct OTPGrabberMenuBarApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = StatusBarAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
private final class StatusBarAppDelegate: NSObject, NSApplicationDelegate, ClipboardWriting {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "OTP"
        statusItem.button?.toolTip = "OTP Grabber"
        rebuildMenu(state: .setup)
        configureClient()
    }

    private func configureClient() {
        do {
            let config = try ClientConfiguration.load()
            let controller = MenuBarController(client: APIClient(configuration: config), clipboard: self)
            controller.onStateChange = { [weak self] state in self?.rebuildMenu(state: state) }
            self.controller = controller
            Task { await controller.refresh() }
        } catch {
            rebuildMenu(state: .setup)
        }
    }

    func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @objc private func refresh(_ sender: Any?) {
        if controller == nil { configureClient() }
        if let controller { Task { await controller.refresh() } }
    }

    @objc private func revealSettings(_ sender: Any?) {
        let url = ClientConfiguration.defaultURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([ClientConfiguration.defaultURL])
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func rebuildMenu(state: MenuState) {
        let menu = NSMenu()
        let headline: String
        let detail: String?
        switch state {
        case .setup:
            headline = "Set up OTP Grabber"
            detail = "Add client.json to connect to your source agent."
        case .loading:
            headline = "Looking for a recent code…"
            detail = nil
        case let .success(code, source, warning):
            headline = "Copied \(code)"
            detail = "From \(source.capitalized)" + (warning.map { " — \($0)" } ?? "")
        case .empty:
            headline = "No recent code found"
            detail = "Choose Refresh to try again."
        case .partial:
            headline = "Some sources are unavailable"
            detail = "Refresh to try again."
        case .offline:
            headline = "Source agent is offline"
            detail = "Check your tailnet connection or setup."
        }
        let title = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let detail {
            let subtitle = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            subtitle.isEnabled = false
            menu.addItem(subtitle)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Reveal Settings", action: #selector(revealSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OTP Grabber", action: #selector(quit(_:)), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.title = state == .loading ? "OTP…" : "OTP"
    }
}
