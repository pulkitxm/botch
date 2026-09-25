import Foundation
import Observation
import ServiceManagement

struct LoginItem: Sendable {
    var isEnabled: @Sendable () -> Bool
    var setEnabled: @Sendable (Bool) throws -> Void

    static let live = LoginItem(
        isEnabled: { SMAppService.mainApp.status == .enabled },
        setEnabled: { enabled in
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        })

    static func fake(initial: Bool = false) -> LoginItem {
        let box = LockedBox(initial)
        return LoginItem(
            isEnabled: { box.value }, setEnabled: { box.value = $0 })
    }
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@MainActor
@Observable
final class BotchSettings {
    enum Keys {
        static let enabled = "enabled"
        static let openOnHover = "openOnHover"
        static let requireOption = "requireOption"
        static let showOnExternal = "showOnExternal"
        static let searchEngine = "searchEngine"
        static let onboarded = "onboarded"
    }

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored var onChange: (() -> Void)?

    var enabled: Bool {
        didSet { store(enabled, Keys.enabled) }
    }
    var openOnHover: Bool {
        didSet { store(openOnHover, Keys.openOnHover) }
    }
    var requireOption: Bool {
        didSet { store(requireOption, Keys.requireOption) }
    }
    var showOnExternal: Bool {
        didSet { store(showOnExternal, Keys.showOnExternal) }
    }
    var searchEngine: BrowserSearchEngine {
        didSet { store(searchEngine.rawValue, Keys.searchEngine) }
    }
    var onboarded: Bool {
        didSet { store(onboarded, Keys.onboarded) }
    }
    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard, loginItem: LoginItem = .live) {
        self.defaults = defaults
        self.loginItem = loginItem
        enabled = Self.flag(defaults, Keys.enabled, default: true)
        openOnHover = Self.flag(defaults, Keys.openOnHover, default: true)
        requireOption = Self.flag(defaults, Keys.requireOption, default: false)
        showOnExternal = Self.flag(defaults, Keys.showOnExternal, default: true)
        searchEngine =
            BrowserSearchEngine(rawValue: defaults.string(forKey: Keys.searchEngine) ?? "")
            ?? .fallback
        onboarded = Self.flag(defaults, Keys.onboarded, default: false)
        launchAtLogin = loginItem.isEnabled()
    }

    func setLaunchAtLogin(_ wanted: Bool) {
        do {
            try loginItem.setEnabled(wanted)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = loginItem.isEnabled()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = loginItem.isEnabled()
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private static func flag(_ defaults: UserDefaults, _ key: String, default fallback: Bool)
        -> Bool
    {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
