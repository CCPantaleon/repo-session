#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
dataset_dir="$project_dir/../Benchmarks/0.5.0-full"
cache_dir="$project_dir/.build/benchmark"
mkdir -p "$cache_dir/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$cache_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir/ModuleCache"
if [[ ! -f "$dataset_dir/manifest.json" ]]; then
  swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
    -module-cache-path "$cache_dir/ModuleCache" Tools/GenerateMedia.swift -o "$cache_dir/generate-media"
  "$cache_dir/generate-media" "$dataset_dir"
fi
swift build -c release --product DuplicateFinderBenchmark --scratch-path "$cache_dir/build" \
  --cache-path "$cache_dir/cache" --config-path "$cache_dir/config" \
  --security-path "$cache_dir/security" --manifest-cache local --disable-sandbox
benchmark_bin_dir="$(swift build -c release --show-bin-path --scratch-path "$cache_dir/build" --disable-sandbox)"
"$benchmark_bin_dir/DuplicateFinderBenchmark" "$dataset_dir/manifest.json" "$dataset_dir/report.json"
