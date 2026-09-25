import Foundation
import Testing

@testable import BotchKit

@Suite @MainActor struct BotchSettingsTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "test.botch.\(UUID().uuidString)"))
    }

    @Test func defaultsEnableTheNotchAndHoverWithGoogle() throws {
        let settings = BotchSettings(defaults: try defaults(), loginItem: .fake())
        #expect(settings.enabled)
        #expect(settings.openOnHover)
        #expect(!settings.requireOption)
        #expect(settings.showOnExternal)
        #expect(settings.searchEngine == .google)
        #expect(!settings.onboarded)
        #expect(!settings.launchAtLogin)
    }

    @Test func changesPersistAndNotify() throws {
        let store = try defaults()
        let settings = BotchSettings(defaults: store, loginItem: .fake())
        var changes = 0
        settings.onChange = { changes += 1 }
        settings.enabled = false
        settings.searchEngine = .kagi
        settings.requireOption = true
        settings.onboarded = true
        #expect(changes == 4)
        let reloaded = BotchSettings(defaults: store, loginItem: .fake())
        #expect(!reloaded.enabled)
        #expect(reloaded.searchEngine == .kagi)
        #expect(reloaded.requireOption)
        #expect(reloaded.onboarded)
        #expect(store.string(forKey: BotchSettings.Keys.searchEngine) == "kagi")
    }

    @Test func theBrowserReadsTheSearchEngineFromTheSameDefaults() throws {
        let store = try defaults()
        let settings = BotchSettings(defaults: store, loginItem: .fake())
        settings.searchEngine = .duckDuckGo
        let browser = NotchBrowserStore(
            installation: ChromeInstallation(
                applicationURL: { nil }, defaultBrowser: { nil },
                userData: ChromeUserData(root: URL(fileURLWithPath: "/nonexistent"))),
            sessionFile: BrowserSessionFile(
                url: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "botch-settings-\(UUID().uuidString)/session.json")),
            defaults: store, keyProvider: { throw ChromeSafeStorageError.keychainMissing })
        defer { browser.shutdown() }
        #expect(browser.searchEngine == .duckDuckGo)
        #expect(browser.readiness == .notInstalled)
    }

    @Test func launchAtLoginFollowsTheLoginItemAndReportsFailures() throws {
        let settings = BotchSettings(defaults: try defaults(), loginItem: .fake(initial: true))
        #expect(settings.launchAtLogin)
        settings.setLaunchAtLogin(false)
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError == nil)
        let broken = LoginItem(
            isEnabled: { false }, setEnabled: { _ in throw CocoaError(.featureUnsupported) })
        let failing = BotchSettings(defaults: try defaults(), loginItem: broken)
        failing.setLaunchAtLogin(true)
        #expect(!failing.launchAtLogin)
        #expect(failing.launchAtLoginError != nil)
    }
}
