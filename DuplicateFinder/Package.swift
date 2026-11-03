// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DuplicateFinder",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DuplicateFinderCore", targets: ["DuplicateFinderCore"]),
               .executable(name: "DuplicateFinder", targets: ["DuplicateFinderApp"]),
               .executable(name: "DuplicateFinderBenchmark", targets: ["DuplicateFinderBenchmark"])],
    targets: [.target(name: "DuplicateFinderCore"),
              .executableTarget(name: "DuplicateFinderBenchmark", dependencies: ["DuplicateFinderCore"], path: "Tools/Benchmark"),
              .executableTarget(name: "DuplicateFinderApp", dependencies: ["DuplicateFinderCore"]),
              .testTarget(name: "DuplicateFinderCoreTests", dependencies: ["DuplicateFinderCore"]),
              .testTarget(name: "DuplicateFinderAppTests", dependencies: ["DuplicateFinderApp", "DuplicateFinderCore"])])
