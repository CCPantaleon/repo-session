import SwiftUI
import DuplicateFinderCore

struct EmptyState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(detail) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct ArchitectureNotice: View {
    var body: some View {
        Label("Exact duplicates · Local processing · Review required before moving to Trash.", systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }
}
func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            if model.unresolvedOperationCount > 0 || model.auditWarning != nil {
                Button("Operation history needs attention — review before retrying removal") { model.screen = .operations }
                    .padding(10).frame(maxWidth: .infinity).background(.orange.opacity(0.12))
            }
            if model.maintenanceBusy { ProgressView("Maintaining saved scans…").controlSize(.small).padding(8) }
            if model.screen != .results { ArchitectureNotice() }
            switch model.screen {
            case .home: HomeView()
            case .configuration: ScanConfigurationView()
            case .progress: ScanProgressView()
            case .results: ResultsBrowserView()
            case .comparison: ComparisonView()
            case .review: RemovalReviewView()
            case .history: HistoryView()
            case .operations: OperationHistoryView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.screen = .home } label: { Label("Home", systemImage: "house") }
            }
            ToolbarItem {
                Menu("Navigate") { ForEach(Screen.allCases) { screen in Button(screen.rawValue) { model.screen = screen } } }
            }
        }
        .alert("Duplicate Finder", isPresented: Binding(get: { model.message != nil },
                                                        set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
