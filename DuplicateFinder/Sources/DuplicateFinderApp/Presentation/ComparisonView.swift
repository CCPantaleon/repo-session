import SwiftUI
import DuplicateFinderCore
struct ComparisonView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Compare All Copies").font(.title2)
                Spacer()
                Button("Back to Results") { model.screen = .results }
                Button("Review Selection") { model.reviewSelection() }
            }
            Text("Every copy is shown below with its full path. Unchecked copies will be kept.").foregroundStyle(.secondary)
            if model.selectedGroups.contains(where: { $0.requiresRescan }) {
                Label("Files in this group changed or became unavailable. Rescan before making another selection.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Rescan Locations") { model.startScan() }.disabled(model.workActive)
            }
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:300),alignment:.top)],alignment:.leading,spacing:20) {
                    ForEach(model.selectedGroups.flatMap(\.files)) { file in
                        VStack(alignment:.leading,spacing:10) {
                            FileThumbnail(url:file.url).frame(height:200)
                            ImageProperties(url:file.url)
                            Text(file.url.lastPathComponent).font(.headline)
                            Text(file.url.path).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            Text(formattedBytes(file.snapshot.logicalBytes)+" · "+file.snapshot.modifiedAt.formatted()).font(.caption)
                            Label(model.needsRescan(file) ? "Rescan required" : model.selection.keeperIDs.contains(file.id) ? "Locked keeper" : model.selection.removalIDs.contains(file.id) ? "Marked for removal" : "Keep",systemImage:model.selection.removalIDs.contains(file.id) ? "trash" : "checkmark.shield")
                            if let restriction = file.removalRestriction {
                                Text(restriction).font(.callout).foregroundStyle(.secondary)
                            }
                            Toggle("Move this copy to Trash",isOn:Binding(get:{ model.selection.removalIDs.contains(file.id) },set:{ model.mark(file,removal:$0) })).disabled(model.workActive || model.showingSavedResults || model.needsRescan(file) || file.removalRestriction != nil || file.snapshot.linkCount > 1)
                            HStack {
                                Button(model.selection.keeperIDs.contains(file.id) ? "Unlock" : "Keep") {
                                    if model.selection.keeperIDs.contains(file.id) { model.unlockKeeper(file) } else { model.keep(file) }
                                }.disabled(model.workActive || model.showingSavedResults || model.needsRescan(file))
                                Button("Quick Look") { QuickLookPresenter.shared.show(file.url) }
                                Button("Reveal") { model.selectedFileID = file.id; model.revealSelectedFile() }
                            }
                        }.padding().frame(maxWidth:.infinity,alignment:.topLeading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }
        }.padding(20)
    }
}
