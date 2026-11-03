import SwiftUI
import DuplicateFinderCore

struct PreviewInspector: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let file = model.selectedFile {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FileThumbnail(url:file.url).frame(height:240)
                    ImageProperties(url:file.url)
                    Text(file.url.lastPathComponent).font(.headline)
                    LabeledContent("Extension", value: file.url.pathExtension)
                    LabeledContent("Size", value: formattedBytes(file.snapshot.logicalBytes))
                    Text(file.url.path).font(.caption).textSelection(.enabled)
                    LabeledContent("Created", value: file.createdAt?.formatted() ?? "Unavailable")
                    LabeledContent("Modified", value: file.snapshot.modifiedAt.formatted())
                    if let metadata = file.media {
                        LabeledContent("Dimensions", value: "\(metadata.width ?? 0) × \(metadata.height ?? 0)")
                        LabeledContent("Camera", value: metadata.camera ?? "Unavailable")
                        LabeledContent("Lens", value: metadata.lens ?? "Unavailable")
                    }
                    if model.needsRescan(file) { Text("Rescan required — this result is no longer verified.").foregroundStyle(.orange) }
                    else { switch file.verification {
                    case .exact(let digest, _): Text("SHA-256: \(digest.sha256)").font(.caption.monospaced()).textSelection(.enabled)
                    case .unverified: Text("Not verified")
                    case .changed: Text("Changed since scan — rescan required")
                    }
                    }
                    HStack {
                        Button("Open File") { model.openSelectedFile() }
                        Button("Reveal in Finder") { model.revealSelectedFile() }
                    }
                    Button("Quick Look") { QuickLookPresenter.shared.show(file.url) }
                    Button(model.selection.keeperIDs.contains(file.id) ? "Unlock This File" : "Keep This File") {
                        if model.selection.keeperIDs.contains(file.id) { model.unlockKeeper(file) } else { model.keep(file) }
                    }.disabled(model.workActive || model.showingSavedResults || model.needsRescan(file))
                    Button("Mark for Removal") { model.mark(file,removal:true) }.disabled(model.workActive || model.showingSavedResults || model.needsRescan(file) || file.removalRestriction != nil || file.snapshot.linkCount > 1)
                    if let restriction = file.removalRestriction { Text(restriction).font(.callout).foregroundStyle(.secondary) }
                    Text(model.needsRescan(file) ? "A fresh scan is required before removal." : "Content verified by SHA-256; reverified before removal.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
        } else {
            EmptyState(title: "Select a file", symbol: "sidebar.right", detail: "Preview, metadata, verification, and file actions appear here.")
        }
    }
}
