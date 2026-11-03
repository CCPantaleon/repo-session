import SwiftUI
import AppKit
import Quartz
import QuickLookThumbnailing
import ImageIO

@MainActor
final class QuickLookPresenter: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookPresenter()
    private var url: URL?
    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
}
struct FileThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage:image).resizable().scaledToFit() }
            else { Image(systemName:"doc").font(.largeTitle).foregroundStyle(.secondary) }
        }
        .accessibilityLabel("Preview of \(url.lastPathComponent)")
        .task(id:url) {
            let request = QLThumbnailGenerator.Request(fileAt:url,size:CGSize(width:600,height:400),scale:1,representationTypes:.thumbnail)
            let data: Data? = await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for:request) { @Sendable representation, _ in
                    let data = representation.flatMap { NSBitmapImageRep(cgImage:$0.cgImage).representation(using:.png,properties:[:]) }
                    continuation.resume(returning:data)
                }
            }
            if !Task.isCancelled { image = data.flatMap(NSImage.init(data:)) ?? NSWorkspace.shared.icon(forFile:url.path) }
        }
    }
}
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.historyLoading { ProgressView("Opening saved scan…") }
        else if model.history.isEmpty { EmptyState(title:"No saved scans",symbol:"clock",detail:"Completed scans appear here. Open saved results for reference, then rescan before removal.") }
        else {
            List(model.history) { scan in
                HStack {
                    VStack(alignment:.leading) { Text(scan.date.formatted()); Text("\(scan.groupCount) duplicate groups · Reverify before removal").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Open Results") { model.openHistory(scan) }
                    Button("Scan Again") { model.rescan(scan) }
                }
            }
        }
    }
}

struct ImageProperties: View {
    let url: URL
    @State private var values: [String:String] = [:]
    var body: some View {
        VStack(alignment:.leading) {
            ForEach(values.keys.sorted(),id:\.self) { key in LabeledContent(key,value:values[key] ?? "") }
        }.task(id:url) {
            values = await Task.detached(priority:.utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL,nil), let p = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else { return [String:String]() }
                var result:[String:String] = [:]
                if let w = p[kCGImagePropertyPixelWidth as String], let h = p[kCGImagePropertyPixelHeight as String] { result["Dimensions"] = "\(w) × \(h)" }
                if let t = p[kCGImagePropertyTIFFDictionary as String] as? [String:Any], let camera = t[kCGImagePropertyTIFFModel as String] { result["Camera"] = "\(camera)" }
                if let e = p[kCGImagePropertyExifDictionary as String] as? [String:Any], let lens = e[kCGImagePropertyExifLensModel as String] { result["Lens"] = "\(lens)" }
                return result
            }.value
        }
    }
}
