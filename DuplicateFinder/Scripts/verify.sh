#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cache_dir="$project_dir/.build/verification"
mkdir -p "$cache_dir"
export CLANG_MODULE_CACHE_PATH="$cache_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir/ModuleCache"
python3 "$project_dir/Scripts/validate_project.py"
swift test --package-path "$project_dir" --scratch-path "$cache_dir/build" \
  --cache-path "$cache_dir/cache" --config-path "$cache_dir/config" \
  --security-path "$cache_dir/security" --manifest-cache local --disable-sandbox
