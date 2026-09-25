import Foundation
import Testing

@testable import BotchKit

private var mockChromeOutput: URL? {
    ProcessInfo.processInfo.environment["BOTCH_MOCK_CHROME_OUT"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
}

@Suite(.enabled(if: mockChromeOutput != nil))
struct MockChromeExportTests {
    @Test func writesASyntheticChromeDirectoryForMockRuns() throws {
        let output = try #require(mockChromeOutput)
        let chrome = try SyntheticChrome(profiles: [
            SyntheticChromeProfile(
                directory: "Default", name: "Mock Personal", email: "mock@example.com",
                cookies: [
                    SyntheticChromeCookie(host: ".example.com", name: "session", value: "mock")
                ],
                localStorage: ["https://example.com": ["theme": "mock"]],
                colorARGB: 0xFF1A_73E8),
            SyntheticChromeProfile(
                directory: "Profile 1", name: "Mock Work", email: "work@example.com",
                colorARGB: 0xFF34_A853),
        ])
        defer { chrome.remove() }
        #expect(SyntheticChrome.passphrase == MockEnvironment.passphrase)
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: chrome.root, to: output)
        #expect(try ChromeUserData(root: output).profiles().count == 2)
    }
}
