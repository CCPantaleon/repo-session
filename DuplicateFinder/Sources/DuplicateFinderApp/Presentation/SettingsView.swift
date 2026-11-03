import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section("Safety") {
                LabeledContent("Duplicate matching", value: "Exact binary contents")
                LabeledContent("Removal", value: "Move to Trash only")
                LabeledContent("Managed libraries", value: "Excluded")
            }
            Section("Preferences") {
                Toggle("Show Inspector",isOn:$model.showInspector)
                Toggle("Thumbnail Grid",isOn:$model.useGrid)
                Button("Choose Preferred Keeper Folder…") { model.choosePreferredFolder() }
                Text(model.preferredFolder?.path ?? "No preferred folder")
                Button("Save Current Scan Folders") { model.saveLocations() }
                Button("Clear Saved Scans and Their Databases") { model.clearScanHistory() }.disabled(model.workActive)
                Text("Keeps up to 50 scans for 30 days. Clearing saved scans removes their stored paths and hashes; original files are never touched.").font(.caption)
                Button("View Operation History") { model.screen = .operations }
                Text("The removal log is kept separately for recovery and remains when saved scans are cleared.").font(.caption)
            }
            Section("Privacy") {
                Text("Local processing. No account, network service, or telemetry.")
                Text("Removal is limited to verified internal local volumes. Similar Photos is reserved for version 2.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
