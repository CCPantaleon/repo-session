import SwiftUI

@main
struct DuplicateFinderApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Duplicate Finder", id: "main") {
            RootView().environmentObject(model).frame(minWidth: 980, minHeight: 640)
                .onAppear { lifecycle.model = model }
                .onDisappear { model.cancelScan(); model.cancelRemoval() }
        }
        .defaultSize(width: 1250, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Scan Folders…") { model.chooseFolders() }.keyboardShortcut("o")
            }
            CommandMenu("Scan") {
                Button("New Scan") { model.screen = .home }.keyboardShortcut("n")
                Button("Pause or Resume") { model.togglePause() }.disabled(!model.scanActive)
                Button("Cancel Scan") { model.cancelScan() }.disabled(!model.scanActive)
            }
            CommandMenu("Navigate") {
                ForEach(Screen.allCases) { screen in Button(screen.rawValue) { model.screen = screen } }
            }
            CommandMenu("Selection") {
                Button("Select Redundant Copies Across Entire Scan") { model.apply(.allRedundant, allResults: true) }.disabled(model.groups.isEmpty || model.workActive || model.showingSavedResults)
                Button("Clear Selection") { model.clearSelection() }.disabled(model.removalBusy)
                Button("Review Selection") { model.reviewSelection() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Toggle("Show Inspector", isOn: $model.showInspector).keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        Settings { SettingsView().environmentObject(model).frame(width: 520, height: 360) }
    }
}
