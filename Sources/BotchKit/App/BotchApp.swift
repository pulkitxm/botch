import AppKit
import SwiftUI

@MainActor
public final class BotchApp: NSObject, NSApplicationDelegate {
    public static let releasesURL = URL(
        string: "https://github.com/pulkitxm/botch/releases/latest")!

    private let settings: BotchSettings
    private let browser: NotchBrowserStore
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    public override init() {
        settings = BotchSettings(defaults: MockEnvironment.defaults ?? .standard)
        browser =
            MockEnvironment.browserStore(defaults: settings.defaults)
            ?? NotchBrowserStore(defaults: settings.defaults)
        super.init()
    }

    public static func main() {
        let app = NSApplication.shared
        let delegate = BotchApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onChange = { [weak self] in self?.applySettings() }
        installStatusItem()
        applySettings()
        if let seconds = MockEnvironment.openSeconds {
            scheduleMockRun(openFor: seconds)
        } else if !settings.onboarded {
            showSettings()
        }
    }

    private func scheduleMockRun(openFor seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.controller?.openBrowser()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + seconds) { [weak self] in
            self?.controller?.collapseNow()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
        browser.shutdown()
    }

    private func applySettings() {
        if settings.enabled, controller == nil {
            controller = NotchController(browser: browser, settings: settings)
        } else if !settings.enabled, let running = controller {
            running.shutdown()
            controller = nil
        }
        controller?.rebuildPanels()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Botch")
        let menu = NSMenu()
        menu.addItem(menuItem("Open Browser", #selector(openBrowser), key: "o"))
        menu.addItem(menuItem("Settings…", #selector(showSettingsAction), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Botch", #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openBrowser() {
        if !settings.enabled {
            settings.enabled = true
            settings.onboarded = true
        }
        controller?.openBrowser()
    }

    @objc private func showSettingsAction() {
        showSettings()
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let view = SettingsView(
            settings: settings,
            openBrowser: { [weak self] in
                self?.settingsWindow?.orderOut(nil)
                self?.openBrowser()
            },
            detachProfile: { [weak self] in self?.browser.detach() },
            profileName: browser.profile?.name)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Botch"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 420))
        return window
    }
}
