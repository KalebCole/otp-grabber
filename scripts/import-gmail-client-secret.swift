#!/usr/bin/env swift

import AppKit
import Foundation
import Security

private let defaultClientID = "704452847810-l2d2q73rrlaaugep1saj31njl17lnufk.apps.googleusercontent.com"
private let keychainService = "com.otpgrabber.menubar.gmail.client-secret"

private struct GoogleCredentials: Decodable {
    struct DesktopClient: Decodable {
        let client_id: String
        let client_secret: String
    }

    let installed: DesktopClient?
}

private func fail(_ message: String) -> Never {
    fputs("Could not import client secret: \(message)\n", stderr)
    exit(1)
}

private let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else {
    fail("Use --clipboard after copying the secret, or --file PATH for Google's Desktop client JSON.")
}

let input: String
let clipboardChangeCount: Int?
switch arguments[1] {
case "--clipboard" where arguments.count == 2:
    let pasteboard = NSPasteboard.general
    clipboardChangeCount = pasteboard.changeCount
    guard let copied = pasteboard.string(forType: .string) else {
        fail("The clipboard has no text. Copy the Desktop client secret and try again.")
    }
    input = copied
case "--file" where arguments.count == 3:
    clipboardChangeCount = nil
    let path = (arguments[2] as NSString).expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: path),
          let contents = String(data: data, encoding: .utf8) else {
        fail("The Desktop client JSON file could not be read.")
    }
    input = contents
default:
    fail("Use --clipboard after copying the secret, or --file PATH for Google's Desktop client JSON.")
}

let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmed.isEmpty else { fail("The secret is empty.") }

let configuredClientID = UserDefaults(suiteName: "com.otpgrabber.menubar")?
    .string(forKey: "gmailClientID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultClientID

let secret: String
if arguments[1] == "--file" || trimmed.hasPrefix("{") {
    guard let credentials = try? JSONDecoder().decode(GoogleCredentials.self, from: Data(trimmed.utf8)),
          let desktop = credentials.installed else {
        fail("Expected a Google Desktop app OAuth client JSON file.")
    }
    guard desktop.client_id == configuredClientID else {
        fail("The JSON client ID differs from OTP Grabber's saved Desktop client ID. Check Settings and the JSON file.")
    }
    secret = desktop.client_secret
} else {
    secret = trimmed
}

guard !secret.isEmpty, !secret.contains(where: \.isWhitespace),
      !secret.hasSuffix(".apps.googleusercontent.com") else {
    fail("The copied value does not look like a client secret.")
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: keychainService,
    kSecAttrAccount as String: configuredClientID,
]
let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
if status == errSecDuplicateItem {
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    guard updateStatus == errSecSuccess else { fail("Keychain update failed (OSStatus \(updateStatus)).") }
} else if status != errSecSuccess {
    fail("Keychain save failed (OSStatus \(status)).")
}

if let clipboardChangeCount, NSPasteboard.general.changeCount == clipboardChangeCount {
    NSPasteboard.general.clearContents()
}
print("Client secret saved in Keychain for OTP Grabber. Open OTP → Settings → Connect Gmail.")
