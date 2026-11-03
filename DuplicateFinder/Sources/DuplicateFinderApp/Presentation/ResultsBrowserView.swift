import SwiftUI
import DuplicateFinderCore

struct ResultsBrowserView: View {
    @EnvironmentObject private var model: AppModel
    @State private var visibleLimit = 100
    @State private var filtersVisible = false
    private var matches: [DuplicateGroup] { model.visibleGroups }
    private var copies: Int { matches.reduce(0) { $0 + $1.files.count } }
    private var savings: Int64 { matches.reduce(0) { total,group in
        let (sum,overflow) = total.addingReportingOverflow(group.redundantLogicalBytes)
        return overflow ? Int64.max : sum
    } }
    var body: some View {
        VStack(spacing:0) {
            NavigationSplitView {
                List(selection:$model.section) {
                    Section("Library") {
                        ForEach(ResultSection.allCases.filter { $0 != .recent }) { section in
                            Label(section == .largest ? "Large Files" : section.rawValue,systemImage:section.symbol)
                                .padding(.vertical,7).tag(section)
                        }
                    }
                    Section("Scan Locations") {
                        ForEach(scanRoots,id:\.self) { url in
                            Label(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,systemImage:"folder")
                                .font(.callout).help(url.path).lineLimit(1)
                        }
                        Button { model.chooseFolders() } label: { Label("Add Folder",systemImage:"plus") }.buttonStyle(.plain)
                    }
                    Section {
                        Button { model.screen = .history } label: { Label("Recent Scans",systemImage:"clock") }.buttonStyle(.plain)
                        Button { model.screen = .home } label: { Label("New Scan",systemImage:"viewfinder") }.buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min:190,ideal:230,max:320)
            } detail: {
                VStack(alignment:.leading,spacing:0) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:5) {
                            Text(model.section == .all ? "Duplicates" : model.section == .largest ? "Large Files" : model.section.rawValue)
                                .font(.system(size:26,weight:.semibold))
                            Text(model.showingSavedResults ? "Saved scan · Rescan before selecting copies" : model.groups.isEmpty ? "Scan folders to find exact copies" : model.hasStaleResults ? "Some results need a fresh scan" : "Verified exact content matches")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { filtersVisible.toggle() } label: { Image(systemName:"line.3.horizontal.decrease").font(.title3) }
                            .buttonStyle(.plain).accessibilityLabel("Sort and filter duplicates")
                            .popover(isPresented:$filtersVisible) { filterControls.padding(20).frame(width:330) }
                        Button { model.showInspector.toggle() } label: { Image(systemName:"sidebar.right").font(.title3) }
                            .buttonStyle(.plain).accessibilityLabel("Show file inspector")
                    }.padding(.bottom,28)
                    if model.hasStaleResults {
                        Button("Rescan Changed or Unavailable Results") { model.startScan() }.disabled(model.workActive).padding(.bottom, 16)
                    }
                    if model.showingSavedResults { Button("Rescan These Locations") { model.showingSavedResults = false; model.startScan() }.padding(.bottom,16) }
                    HStack {
                        metric("Groups",value:String(matches.count))
                        metric("Copies",value:String(copies))
                        metric("Potential savings",value:formattedBytes(savings))
                    }.padding(.bottom,20)
                    if matches.contains(where: { $0.files.contains { $0.removalRestriction != nil } }) {
                        Label("External, network, and read-only copies are scan-only and cannot be marked for removal.", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.callout).foregroundStyle(.secondary).padding(.bottom, 10)
                    }
                    if model.progress.skipped > 0 {
                        Button("\(model.progress.skipped) items skipped · Review issues") { model.screen = .progress }
                            .font(.callout).padding(.bottom,10)
                    }
                    if matches.isEmpty {
                        EmptyState(title:model.groups.isEmpty ? "No duplicates to display" : "No matching duplicates",symbol:"square.on.square",detail:model.groups.isEmpty ? "Choose folders and run a scan. Identical file contents will appear here." : "Try changing the category or search filter.")
                    } else {
                        ScrollView {
                            if model.useGrid {
                                LazyVGrid(columns:[GridItem(.adaptive(minimum:280))],spacing:18) {
                                    ForEach(Array(matches.prefix(visibleLimit))) { group in groupRow(group,grid:true) }
                                }
                            } else {
                                LazyVStack(spacing:0) {
                                    ForEach(Array(matches.prefix(visibleLimit))) { group in
                                        groupRow(group,grid:false)
                                        Divider()
                                    }
                                }
                            }
                            if matches.count > visibleLimit {
                                Button("Show More Groups (\(min(visibleLimit,matches.count)) of \(matches.count))") { visibleLimit += 100 }.padding()
                            }
                        }
                    }
                }.padding(.horizontal,30).padding(.top,28)
                .background(Color(nsColor:.textBackgroundColor))
                .inspector(isPresented:$model.showInspector) {
                    PreviewInspector().inspectorColumnWidth(min:240,ideal:320,max:500)
                }
            }
            Divider()
            HStack(spacing:18) {
                Text("\(model.selection.removalIDs.count) files marked for removal").foregroundStyle(.secondary)
                if model.hiddenSelectionCount > 0 {
                    Text("\(model.hiddenSelectionCount) selected outside this filter").font(.caption).foregroundStyle(.orange)
                }
                Menu {
                    Button("Keep Newest in Visible Results") { model.apply(.keepNewest) }
                    Button("Keep Oldest in Visible Results") { model.apply(.keepOldest) }
                    Button("Keep in Preferred Folder — Visible Results") {
                        if let folder = model.preferredFolder { model.apply(.preferredFolder(folder)) } else { model.choosePreferredFolder() }
                    }
                    Button("Choose Preferred Folder…") { model.choosePreferredFolder() }
                    Button("Select Redundant Copies in Visible Results") { model.apply(.allRedundant) }
                    Divider()
                    Button("Select Across Entire Scan") { model.apply(.allRedundant, allResults: true) }
                    Button("Clear Selection") { model.clearSelection() }
                } label: { Label("Selection",systemImage:"checklist") }
                .fixedSize().disabled(model.groups.isEmpty || model.workActive || model.showingSavedResults)
                Spacer()
                Button("Review Selection") { model.reviewSelection() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(model.selection.removalIDs.isEmpty || model.removalBusy)
            }.padding(.horizontal,24).padding(.vertical,16).background(.bar)
        }
        .onChange(of:model.useGrid) { _,v in UserDefaults.standard.set(v,forKey:"grid") }
        .onChange(of:model.showInspector) { _,v in UserDefaults.standard.set(v,forKey:"inspector") }
    }
    private var scanRoots: [URL] {
        switch model.configuration.scope {
        case .folders(let urls),.externalVolumes(let urls): urls
        case .homeFolder: [FileManager.default.homeDirectoryForCurrentUser]
        case .accessibleUserLocations: ["Desktop","Documents","Downloads","Pictures","Movies","Music"].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }
        }
    }
    private func metric(_ title: String,value: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(value).font(.system(size:25,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private func groupRow(_ group: DuplicateGroup,grid: Bool) -> some View {
        let file = group.files[0]
        return Button { model.compare(group) } label: {
            HStack(spacing:18) {
                FileThumbnail(url:file.url)
                    .frame(width:grid ? 72 : 88,height:grid ? 72 : 88)
                    .background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                    .clipShape(RoundedRectangle(cornerRadius:16))
                VStack(alignment:.leading,spacing:6) {
                    Text(file.url.lastPathComponent).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(group.requiresRescan ? "Rescan required · \(group.files.count) previous matches" : "\(group.files.count) identical copies").font(.title3).foregroundStyle(.secondary)
                    Text(formattedBytes(file.snapshot.logicalBytes)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength:4)
                Image(systemName:"chevron.right").font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical,18).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare \(group.files.count) copies of \(file.url.lastPathComponent)")
        .contextMenu {
            Button("Compare All Copies") { model.compare(group) }
            Button("Inspect File") { model.selectedFileID = file.id; model.showInspector = true }
            Button("Reveal in Finder") { model.selectedFileID = file.id; model.revealSelectedFile() }
            Button("Quick Look") { QuickLookPresenter.shared.show(file.url) }
        }
    }
    private var filterControls: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Sort & Filter").font(.headline)
            TextField("Search names or full paths",text:$model.query.search)
            Picker("Sort by",selection:$model.query.sort) {
                ForEach(ResultQuery.Sort.allCases) { value in Text(sortTitle(value)).tag(value) }
            }
            Toggle("Thumbnail grid",isOn:$model.useGrid)
            Toggle("Show inspector",isOn:$model.showInspector)
            Text("Potential savings are logical duplicate bytes. Actual freed space can differ.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func sortTitle(_ sort: ResultQuery.Sort) -> String {
        switch sort {
        case .wastedSpace: "Largest wasted space"; case .fileSize: "File size"; case .name: "File name"
        case .created: "Creation date"; case .modified: "Modification date"; case .type: "File type"
        case .location: "Folder / location"; case .copies: "Number of copies"
        }
    }
}
