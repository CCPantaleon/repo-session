import SwiftUI
import DuplicateFinderCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Make room for what matters.").font(.largeTitle).fontWeight(.semibold)
                Text("Find identical files, compare your copies, and choose what to keep.").foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    action("Scan This Mac", symbol: "desktopcomputer", detail: "Accessible user locations. Protected files remain protected.") {
                        model.configure(.accessibleUserLocations)
                    }
                    action("Choose Folders", symbol: "folder", detail: "Pick one or more folders to compare.") { model.chooseFolders() }
                    action("Scan External Drives", symbol: "externaldrive", detail: "Find and compare copies. External-drive results are scan-only; removal is unavailable.") { model.chooseExternalVolumes() }
                }
                GroupBox("Start with") {
                    HStack {
                        Button("Home Folder") { model.configure(.homeFolder) }
                        Button("Photos Only") { model.configuration.categories = [.photos]; model.configure(.homeFolder) }
                        Button("Videos Only") { model.configuration.categories = [.videos]; model.configure(.homeFolder) }
                        Button("All File Types") { model.configuration.categories = Set(FileCategory.allCases); model.configure(.homeFolder) }
                        Spacer()
                    }.padding(8)
                }
                GroupBox("Saved Locations") {
                    VStack(alignment:.leading) {
                        ForEach(model.savedPaths,id:\.self) { path in Button(path) { model.restoreLocation(path) } }
                        Button("Save Current Folders") { model.saveLocations() }.disabled(model.folders.isEmpty)
                    }
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text("Access is determined by macOS and your folder choices. Full Disk Access can broaden access to protected user data; it never grants access to everything on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Browse Results Layout") { model.screen = .results }
            }.padding(36).frame(maxWidth: 1100)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFolders(urls)
            if !model.folders.isEmpty { model.configure(.folders(model.folders)); return true }
            return false
        }
    }
    private func action(_ title: String, symbol: String, detail: String, perform: @escaping () -> Void) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title).accessibilityHidden(true)
                Button(title, action: perform).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading).padding(12)
        }
    }
}
