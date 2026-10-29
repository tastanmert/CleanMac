import SwiftUI

@main
struct CleanMacApp: App {
    @State private var model = AppModel()
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @AppStorage(Sounds.defaultsKey) private var soundsEnabled = true
    @AppStorage(SelfUpdateModel.autoKey) private var autoUpdate = true
    /// "" follows macOS; "tr" or "en" overrides it for CleanMac alone (takes effect at the next launch).
    @State private var language = (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first ?? ""

    var body: some Scene {
        Window("CleanMac", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Güncellemeleri Denetle…")) { model.checkForUpdates() }
            }
            CommandMenu(String(localized: "Tarama")) {
                Button(String(localized: "Tara")) { model.requestScan() }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
            }
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent().environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Form {
                Toggle(String(localized: "Menü çubuğunda göster"), isOn: $menuBarEnabled)
                Toggle(String(localized: "Sesler"), isOn: $soundsEnabled)
                Toggle(String(localized: "Güncellemeleri otomatik denetle"), isOn: $autoUpdate)
                Picker(String(localized: "Dil"), selection: $language) {
                    Text(String(localized: "Sistem dili")).tag("")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
                .onChange(of: language) { _, code in
                    if code.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                    else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
                }
                Text(String(localized: "Dil, CleanMac yeniden açılınca değişir."))
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent(String(localized: "Sürüm \(model.selfUpdate.current)")) {
                    Button(String(localized: "Şimdi denetle")) { model.checkForUpdates() }
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }
}
