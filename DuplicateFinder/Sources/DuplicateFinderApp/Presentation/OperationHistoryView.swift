import SwiftUI
import AppKit

struct OperationHistoryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Operation History").font(.title)
                Spacer()
                Button("Refresh") { model.refreshAudit() }.disabled(model.auditLoading || model.removalBusy)
                Button("Open Full Log") { NSWorkspace.shared.open(model.journalURL) }
            }
            Text("Unresolved operations appear first. Nothing is retried automatically.").foregroundStyle(.secondary)
            if let warning = model.auditWarning { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            Text("\(model.auditUnresolvedCount) unresolved · \(model.auditTotalCount) records in the active log").font(.callout)
            if model.auditLoading { ProgressView() }
            if model.auditEntries.isEmpty && !model.auditLoading {
                EmptyState(title: "No recorded removals", symbol: "clock", detail: "Reviewed Trash operations will appear here.")
            } else {
                List(model.auditEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.file.url.path).textSelection(.enabled)
                        Text(entry.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        if entry.needsInspection {
                            Label("Interrupted — outcome unknown", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text("Check the original location and Finder’s Trash. The app stopped before recording the outcome. Rescan before selecting this file again.")
                        } else {
                            Text(entry.result?.message ?? entry.state.capitalized)
                        }
                        HStack {
                            Button("Show Original Folder") { NSWorkspace.shared.open(entry.file.url.deletingLastPathComponent()) }
                            if let destination = entry.result?.trashURL {
                                Button("Show in Trash") { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
            HStack {
                Button("Previous") { model.previousAuditPage() }.disabled(model.auditLoading || model.auditOffset == 0)
                Text("Showing \(model.auditTotalCount == 0 ? 0 : model.auditOffset + 1)–\(model.auditOffset + model.auditEntries.count) of \(model.auditTotalCount)").font(.caption)
                Button("Next") { model.nextAuditPage() }.disabled(model.auditLoading || model.auditOffset + model.auditEntries.count >= model.auditTotalCount)
                Spacer()
                Button("Open Log Archives") { NSWorkspace.shared.open(model.journalURL.deletingLastPathComponent().appendingPathComponent("Removal Log Archives")) }
                    .disabled(!FileManager.default.fileExists(atPath: model.journalURL.deletingLastPathComponent().appendingPathComponent("Removal Log Archives").path))
            }
            Text("Large logs are compacted to preserve every unresolved operation and the latest 1,000 completed outcomes. The three most recent full archives are kept.").font(.caption).foregroundStyle(.secondary)
            Text("Restore files through Finder’s Trash. This log records outcomes; it does not automatically restore or permanently delete files.").font(.callout).foregroundStyle(.secondary)
        }.padding(24).onAppear { model.refreshAudit() }
    }
}
