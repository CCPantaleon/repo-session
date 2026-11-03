import Foundation
import Darwin
import DuplicateFinderCore

struct Manifest: Decodable {
    let mediaRoot: String
    let photoFiles: Int
    let videoFiles: Int
    let uniqueFiles: Int
    let groups: [[String]]
    let totalBytes: Int64
    let redundantBytes: Int64
}
guard CommandLine.arguments.count == 3 else { fatalError("Usage: DuplicateFinderBenchmark manifest.json report.json") }
let manifest = try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let root = URL(fileURLWithPath:manifest.mediaRoot), started = Date()
var latest = ScanProgress(phase:.ready), issues: [String] = [], printed = Date.distantPast, hashingStarted: Date?
let groups = try LocalScanCoordinator.scan(ScanConfiguration(scope:.folders([root])), emit: { event in
    switch event {
    case .progress(let p):
        latest = p
        if p.phase == .hashing && hashingStarted == nil { hashingStarted = Date() }
        if Date().timeIntervalSince(printed) > 10 { print("\(p.phase.rawValue): \(p.discovered) discovered, \(p.analyzed) hashed"); fflush(stdout); printed = Date() }
    case .issue(let issue): issues.append(issue.message)
    default: break
    }
})
let elapsed = Date().timeIntervalSince(started)
let actual = Set(groups.map { Set($0.files.map { String($0.url.path.dropFirst(root.path.count + 1)) }) })
let expected = Set(manifest.groups.map { Set($0) })
let savings = groups.reduce(Int64(0)) { $0 + $1.redundantLogicalBytes }
guard actual == expected, latest.discovered == manifest.photoFiles + manifest.videoFiles,
      savings == manifest.redundantBytes, issues.isEmpty else { throw EngineError.invalid("Benchmark result differs from generated ground truth") }
var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
let report: [String:Any] = ["files":latest.discovered,"logicalBytes":manifest.totalBytes,"duplicateGroups":groups.count,
    "duplicateMembers":groups.reduce(0){$0+$1.files.count},"uniqueFiles":manifest.uniqueFiles,"redundantLogicalBytes":savings,
    "seconds":elapsed,"enumerationSeconds":hashingStarted?.timeIntervalSince(started) ?? elapsed,"peakRSSBytes":usage.ru_maxrss,
    "issues":issues,"groundTruthMatched":true,"configuration":"Release","mode":"read-only",
    "limitations":"Generated media on this Mac; filesystem cache and APFS cloning may affect throughput. Not a cold-disk or real-library benchmark."]
let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2])); print(String(decoding:data,as:UTF8.self))
