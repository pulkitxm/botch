import AppKit
import SwiftUI

struct SettingsView: View {
    var settings: BotchSettings
    var openBrowser: () -> Void
    var detachProfile: () -> Void
    var profileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            toggles
            Divider()
            engine
            Divider()
            profile
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Botch")
                    .font(.title2.weight(.semibold))
                Text(
                    "A tabbed browser that lives in the notch, signed in with one of your Google Chrome profiles. Hover the notch to open it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enabled", isOn: enabled)
                .toggleStyle(.switch)
                .font(.body.weight(.medium))
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Open on hover", isOn: binding(\.openOnHover))
            Toggle("Require the Option key to open", isOn: binding(\.requireOption))
            Toggle("Show on external displays", isOn: binding(\.showOnExternal))
        }
        .disabled(false)
    }

    private var engine: some View {
        Picker("Search engine", selection: binding(\.searchEngine)) {
            ForEach(BrowserSearchEngine.allCases, id: \.self) { engine in
                Text(engine.title).tag(engine)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var profile: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(profileName.map { "Chrome profile: \($0)" } ?? "No Chrome profile attached")
                    .font(.body)
                Text(
                    profileName == nil
                        ? "Open the notch to pick a profile."
                        : "Cookies and site storage copied from Chrome stay on this Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if profileName == nil {
                Button("Open Notch", action: openBrowser)
                    .disabled(!settings.enabled)
            } else {
                Button("Detach and Clear Data", role: .destructive, action: detachProfile)
            }
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: {
                settings.enabled = $0
                settings.onboarded = true
            })
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<BotchSettings, Value>)
        -> Binding<Value>
    {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}
