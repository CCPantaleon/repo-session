import SwiftUI

struct RemovalReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming = false
    @State private var confirmingPlanID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Before Moving to Trash").font(.title)
            if model.removalBusy {
                if let progress = model.removalProgress {
                    ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    Text("\(progress.completed) of \(progress.total) processed · \(model.cancellationRequested ? "Stopping safely…" : progress.phase)")
                    Text(progress.currentURL?.path ?? "Preparing reviewed files").font(.callout).textSelection(.enabled)
                }
                Button(model.cancellationRequested ? "Cancellation Requested" : "Cancel Remaining Files") { model.cancelRemoval() }
                    .disabled(model.cancellationRequested)
                Text("Completed moves stay in Trash. Cancellation stops remaining work at the next safe point.").foregroundStyle(.secondary)
            } else if let result = model.removalResult {
                Text("Removal Summary").font(.headline)
                Text("\(result.items.filter { $0.outcome == .trashed }.count) moved · \(result.items.filter { $0.outcome == .failed }.count) failed · \(result.items.filter { $0.outcome == .skipped }.count) skipped")
                List(Array(result.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading) { Text(item.originalURL.path); Text(item.message).foregroundStyle(.secondary) }
                }
                Text("Remaining duplicates stay in Results. Changed files need a fresh scan before retrying.").font(.callout)
                if !model.selection.removalIDs.isEmpty {
                    Button("Review Remaining Selection (\(model.selection.removalIDs.count))") { model.reviewSelection() }
                }
                Button("View Operation History") { model.screen = .operations; model.refreshAudit() }
            } else if let plan = model.removalPlan {
                Text("\(plan.removalFiles.count) files · \(plan.groups.count) groups · \(formattedBytes(plan.estimatedLogicalBytes)) logical data")
                if model.selection.removalIDs.count > plan.removalIDs.count {
                    Text("This batch reviews \(plan.removalIDs.count) of \(model.selection.removalIDs.count) selected files. The rest remain selected for a later review.")
                }
                HStack(alignment: .top) {
                    GroupBox("Will Be Retained in This Batch (\(plan.retainedFiles.count))") {
                        List(plan.retainedFiles) { Text($0.url.path).textSelection(.enabled) }
                    }
                    GroupBox("Will Move to Trash") { List(plan.removalFiles) { Text($0.url.path).textSelection(.enabled) } }
                }
                Label("Internal-drive eligibility and file contents will be checked again before each move.", systemImage: "checkmark.shield")
            } else {
                EmptyState(title: "No removal plan ready", symbol: "checkmark.shield", detail: "Choose copies in Results and review them. Changing or clearing the selection cancels the previous review.")
            }
            Text("Moving files to Trash does not free their space until Trash is emptied. Actual recovered space can differ because of APFS clones, snapshots, compression, and sparse files.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Back to Results") { model.screen = .results }
                Spacer()
                Button("Move to Trash") { confirmingPlanID = model.removalPlan?.id; confirming = true }.disabled(!model.canConfirmRemoval)
            }
        }.padding(24)
        .confirmationDialog("Move the reviewed copies to Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                if let id = confirmingPlanID { model.confirmRemoval(expectedPlanID: id) }
            }.disabled(!model.canConfirmRemoval || confirmingPlanID != model.removalPlan?.id)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only the files in this review will be moved. At least one copy in each group will remain. Changed or unavailable files are left in place.") }
    }
}
