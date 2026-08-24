import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420)
    }
}

private struct GeneralSettings: View {
    @AppStorage("detectCopiedLinks") private var detectCopiedLinks = true
    @AppStorage(DockPresence.defaultsKey) private var showDockIcon = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, _ in DockPresence.apply() }
            Text("With the Dock icon off, Dogear lives only in the menu bar.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Detect copied links", isOn: $detectCopiedLinks)
            Text("Dogear checks if the clipboard holds a link. It reads the clipboard only when you save.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enable in
                    try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
        }
        .padding(20)
    }
}

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Dogear").font(.headline)
            Text("Version \(version)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Dogear is free and open source, MIT license.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Dogear on GitHub", destination: URL(string: "https://github.com/northamf/dogear")!)
                .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
