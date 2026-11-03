import SwiftUI
import DuplicateFinderCore

struct ScanConfigurationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var customExtensions = ""
    var body: some View {
        Form {
            Section("Scan Locations") {
                Text(scopeDescription).foregroundStyle(.secondary)
                if model.isExternalScope {
                    if let message = model.volumeMessage { Text(message).foregroundStyle(.secondary) }
                    if case .externalVolumes(let savedURLs) = model.configuration.scope {
                        ForEach(savedURLs.filter { url in !model.externalVolumes.contains { $0.url == url } }, id: \.self) { url in
                            Text("Saved drive: \(url.path) — connection will be checked during the scan").font(.caption)
                        }
                    }
                    ForEach(model.externalVolumes) { volume in
                        Toggle(volume.name, isOn: Binding(get: { model.volumeIDs.contains(volume.id) }, set: {
                            if $0 { model.volumeIDs.insert(volume.id) } else { model.volumeIDs.remove(volume.id) }
                        }))
                    }
                }
                ForEach(visibleFolders, id: \.self) { url in
                    HStack {
                        Label(url.path, systemImage: "folder").textSelection(.enabled)
                        Spacer()
                        Button { model.removeFolder(url) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove \(url.lastPathComponent) from scan")
                    }
                }
                Button("Add Folders…") { model.chooseFolders() }
            }
            Section("File Filters") {
                HStack {
                    ForEach(FileCategory.allCases) { category in
                        Toggle(category.title, isOn: Binding(get: { model.configuration.categories.contains(category) }, set: {
                            if $0 { model.configuration.categories.insert(category) } else { model.configuration.categories.remove(category) }
                        }))
                    }
                }
                TextField("Extensions (comma separated, optional)", text: $customExtensions)
                    .onChange(of: customExtensions) { _, value in
                        model.configuration.extensions = Set(value.lowercased().split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        }.filter { !$0.isEmpty })
                    }
                TextField("Minimum file size (bytes)", value: $model.configuration.minimumBytes, format: .number)
                Text("Zero-byte files are excluded by default. Content matching always uses full file hashes.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded Folders") {
                ForEach(model.configuration.excludedFolders, id: \.self) { url in
                    HStack {
                        Text(url.path); Spacer()
                        Button("Remove") { model.configuration.excludedFolders.removeAll { $0 == url } }
                    }
                }
                Button("Exclude Folders…") { model.chooseFolders(excluded: true) }
                Text("System locations, application bundles, managed photo libraries, symbolic links, and cloud placeholders are excluded by policy.").foregroundStyle(.secondary)
            }
            Section("Permissions") {
                Text("Access is checked during enumeration. Denied and disconnected locations appear in scan issues.")
                Text("External and network drives can be scanned and compared. Removal is available only for writable internal local drives.")
                Text("If protected user folders are needed, enable Duplicate Finder in System Settings → Privacy & Security → Full Disk Access, then retry. This build does not inspect or change that setting.").font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Start Scan") { model.startScan() }.buttonStyle(.borderedProminent)
                    .disabled(model.workActive || model.configuration.minimumBytes < 0 || model.configuration.categories.isEmpty || !hasRoots)
                Text("Scans are read-only. Files that cannot be accessed are reported and skipped.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .onAppear {
            customExtensions = model.configuration.extensions.sorted().joined(separator: ", ")
            if model.isExternalScope { model.refreshExternalVolumes() }
        }
        .dropDestination(for: URL.self) { urls, _ in model.addFolders(urls); return !model.folders.isEmpty }
    }
    private var visibleFolders: [URL] {
        if case .folders = model.configuration.scope { return model.folders }
        return []
    }
    private var hasRoots: Bool {
        switch model.configuration.scope {
        case .accessibleUserLocations, .homeFolder: true
        case .folders: !model.folders.isEmpty
        case .externalVolumes: !model.volumeIDs.isEmpty
        }
    }
    private var scopeDescription: String {
        switch model.configuration.scope {
        case .accessibleUserLocations: "This Mac: accessible user data only, not the entire filesystem."
        case .homeFolder: "Your home folder, subject to macOS access permissions."
        case .folders: "Only the folders listed below."
        case .externalVolumes: "Selected external volumes only."
        }
    }
}
struct ScanProgressView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Scan Progress").font(.largeTitle)
            Text(model.isPaused ? "Paused" : model.progress.phase.rawValue.capitalized).font(.headline)
            if model.scanActive {
                if let fraction = model.progress.fraction { ProgressView(value: fraction) }
                else { ProgressView().controlSize(.small) }
            }
            Text(model.progress.currentLocation?.path ?? "No location is being scanned").foregroundStyle(.secondary).textSelection(.enabled)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                row("Files discovered", "\(model.progress.discovered)")
                row("Files analyzed", "\(model.progress.analyzed)")
                row("Candidate files", "\(model.progress.candidates)")
                row("Potential redundant data", formattedBytes(model.progress.redundantLogicalBytes))
                row("Skipped / inaccessible", "\(model.progress.skipped)")
                row("Elapsed", "\(Int(model.progress.elapsedSeconds)) seconds")
            }
            Text("Logical duplicate bytes are an estimate, not a promise of freed disk space.").font(.caption).foregroundStyle(.secondary)
            if let message = model.scanMessage { Label(message, systemImage: "info.circle").textSelection(.enabled) }
            HStack {
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }.disabled(!model.scanActive)
                Button("Cancel") { model.cancelScan() }.disabled(!model.scanActive)
                Button("View Results") { model.screen = .results }
                Button("Edit Scan") { model.screen = .configuration }.disabled(model.scanActive)
            }
            if !model.issues.isEmpty {
                List(model.issues) { issue in VStack(alignment:.leading) { Text(issue.url.path).textSelection(.enabled); Text(issue.message).font(.caption).foregroundStyle(.secondary) } }
            }
            Spacer()
        }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func row(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(value).monospacedDigit() }
    }
}
