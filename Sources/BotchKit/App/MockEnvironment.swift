import Foundation
import WebKit

@MainActor
enum MockEnvironment {
    nonisolated static let passphrase = "mock-safe-storage"

    static var chromeRoot: URL? {
        ProcessInfo.processInfo.environment["BOTCH_MOCK_CHROME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    static var openSeconds: TimeInterval? {
        ProcessInfo.processInfo.environment["BOTCH_MOCK_OPEN"].flatMap(TimeInterval.init)
    }

    static var defaults: UserDefaults? {
        chromeRoot == nil ? nil : UserDefaults(suiteName: "com.pulkit.botch.mock")
    }

    static func browserStore(defaults: UserDefaults) -> NotchBrowserStore? {
        guard let root = chromeRoot else { return nil }
        return NotchBrowserStore(
            installation: ChromeInstallation(
                applicationURL: { root },
                defaultBrowser: { (ChromeInstallation.bundleIdentifier, "Google Chrome") },
                userData: ChromeUserData(root: root)),
            sessionFile: BrowserSessionFile(url: root.appendingPathComponent("session.json")),
            defaults: defaults,
            keyProvider: { ChromeCookieKey(passphrase: passphrase) },
            dataStoreFactory: { _ in WKWebsiteDataStore.nonPersistent() })
    }
}
