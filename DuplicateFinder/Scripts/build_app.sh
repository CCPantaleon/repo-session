#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ "${1:-}" != "--skip-tests" ]]; then
  zsh Scripts/verify.sh
fi
python3 Scripts/validate_project.py
release_dir="$project_dir/../Release-0.5.0"
mkdir -p "$release_dir" "$project_dir/.build"
xcodebuild -project DuplicateFinder.xcodeproj -scheme DuplicateFinder \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$project_dir/.build/Release" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build > "$project_dir/.build/release-build.log" 2>&1 || {
    tail -n 60 "$project_dir/.build/release-build.log"
    exit 1
  }
app_dir="$release_dir/Duplicate Finder.app"
ditto "$project_dir/.build/Release/Build/Products/Release/DuplicateFinder.app" "$app_dir"
# Local ad-hoc signatures allow execution; distribution identity/notarization are intentionally separate.
codesign --force --sign - "$app_dir/Contents/Frameworks/DuplicateFinderCore.framework"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
python3 - "$app_dir" <<'PYARCH'
import pathlib,plistlib,subprocess,sys
app=pathlib.Path(sys.argv[1])
info=plistlib.loads((app/"Contents/Info.plist").read_bytes())
if info.get("CFBundleIconFile") != "AppIcon" or not (app/"Contents/Resources/AppIcon.icns").is_file():
    raise SystemExit("The release must include and register its app icon")
for relative in ["Contents/MacOS/DuplicateFinder", "Contents/Frameworks/DuplicateFinderCore.framework/Versions/A/DuplicateFinderCore"]:
    architectures=set(subprocess.check_output(["lipo",str(app/relative),"-archs"],text=True).split())
    if not {"arm64","x86_64"}.issubset(architectures):
        raise SystemExit("Missing release architecture: "+relative)
dependencies=subprocess.check_output(["otool","-L",str(app/"Contents/MacOS/DuplicateFinder")],text=True)
if "@rpath/DuplicateFinderCore.framework/Versions/A/DuplicateFinderCore" not in dependencies or "/Library/Frameworks/DuplicateFinderCore" in dependencies:
    raise SystemExit("The app must load its bundled framework through @rpath")
print("Verified Apple Silicon/Intel code and bundled framework loading")
PYARCH
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/DuplicateFinder-0.5.0.zip"
cp "$project_dir/Documentation/SHARING.txt" "$release_dir/Read Me.txt"
python3 - "$release_dir" <<'PYREADME'
import pathlib,sys,zipfile
folder=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(folder/"DuplicateFinder-0.5.0.zip","a",compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(folder/"Read Me.txt","Read Me.txt")
PYREADME
print "Release app and shareable zip: $release_dir"
