import AppKit
import Foundation
import Testing
import WebKit

@testable import BotchKit

private var timingEnabled: Bool {
    ProcessInfo.processInfo.environment["BOTCH_TIMING"] == "1"
}

@Suite(.serialized, .enabled(if: timingEnabled))
@MainActor struct NotchOpenTimingTests {

    @Test func measuresOpenBrowserToFirstSnapshot() async throws {
        let server = try BrowserHTTPFixture(pages: MockPages.pages)
        defer { server.stop() }
        let origin = try await server.origin()
        let host = origin.host() ?? "127.0.0.1"
        let chrome = try SyntheticChrome(profiles: [
            SyntheticChromeProfile(
                directory: "Default", name: "Mock Personal", email: "mock@example.com",
                cookies: [SyntheticChromeCookie(host: host, name: "session", value: "mock")],
                colorARGB: 0xFF1A_73E8)
        ])
        defer { chrome.remove() }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("botch-timing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try #require(UserDefaults(suiteName: "test.botch.timing.\(UUID())"))
        let settings = BotchSettings(defaults: defaults, loginItem: .fake())
        let store = NotchBrowserStore(
            installation: ChromeInstallation(
                applicationURL: { URL(fileURLWithPath: "/Applications/Google Chrome.app") },
                defaultBrowser: { ("com.google.Chrome", "Google Chrome") },
                userData: chrome.userData),
            sessionFile: BrowserSessionFile(url: folder.appendingPathComponent("session.json")),
            defaults: defaults, keyProvider: { SyntheticChrome.key },
            dataStoreFactory: { _ in WKWebsiteDataStore.nonPersistent() })
        let controller = NotchController(browser: store, settings: settings)
        defer {
            controller.shutdown()
            store.shutdown()
        }
        store.applySize(CGSize(width: 900, height: 480))
        store.attach(store.profiles[0])
        try await eventually { store.profile != nil && store.syncState == .idle }
        let tab = try #require(store.selectedTab)
        try await eventually { tab.url != nil }
        tab.webView.load(URLRequest(url: origin))
        try await eventually { !tab.isLoading && tab.title != "" }
        try await Task.sleep(for: .seconds(1))
        let clock = ContinuousClock()
        var attached: [Double] = []
        var painted: [Double] = []
        for run in 1...5 {
            controller.collapseNow()
            try await Task.sleep(for: .seconds(1))
            let collapsedSnapshot = try? await tab.webView.takeSnapshot(configuration: nil)
            let start = clock.now
            controller.openBrowser()
            while tab.webView.window == nil, clock.now - start < .seconds(10) {
                try await Task.sleep(for: .milliseconds(1))
            }
            attached.append(milliseconds(clock.now - start))
            var image: NSImage?
            while image == nil, clock.now - start < .seconds(10) {
                image = try? await tab.webView.takeSnapshot(configuration: nil)
            }
            painted.append(milliseconds(clock.now - start))
            print(
                "timing: run \(run) attached \(Int(attached[run - 1])) ms painted "
                    + "\(Int(painted[run - 1])) ms snapshot-while-collapsed "
                    + "\(collapsedSnapshot == nil ? "nil" : "image")")
            #expect(image != nil)
        }
        report("attached", attached)
        report("painted", painted)
        print("timing: hover-dwell \(Int(NotchController.openDwell * 1000)) ms")
    }

    private func report(_ label: String, _ samples: [Double]) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        print(
            "timing: \(label) min \(Int(sorted[0])) ms median \(Int(median)) ms "
                + "max \(Int(sorted[sorted.count - 1])) ms")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
    }

    private func eventually(
        _ timeout: Duration = .seconds(15), _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Condition did not become true in time")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
