import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("detectCopiedLinks") private var detectCopiedLinks = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Detect copied links", isOn: $detectCopiedLinks)
            Text("Dogear checks if the clipboard holds a link. It reads the clipboard only when you save.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enable in
                    try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
        }
        .padding(20)
        .frame(width: 360)
    }
}
