#!/usr/bin/env python3
"""Check Xcode references without pretending to replace an Xcode build."""
from pathlib import Path
import json
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = root / "DuplicateFinder.xcodeproj/project.pbxproj"
raw = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)])
data = json.loads(raw)
objects = data["objects"]
assert data["rootObject"] in objects
source_paths = set()
for identifier, obj in objects.items():
    if obj["isa"] == "PBXFileReference" and obj.get("sourceTree") == "<group>":
        path = root / obj["path"]
        assert path.is_file(), f"Missing file: {path}"
        if path.suffix == ".swift": source_paths.add(path.relative_to(root).as_posix())
    for key in ["fileRef", "target", "targetProxy", "containerPortal", "mainGroup", "productReference", "buildConfigurationList", "baseConfigurationReference", "productRefGroup"]:
        if key in obj: assert obj[key] in objects, f"Broken {key} in {identifier}"
    for key in ["children", "files", "targets", "buildPhases", "dependencies", "buildConfigurations"]:
        for child in obj.get(key, []): assert child in objects, f"Broken {key} in {identifier}"
actual = {p.relative_to(root).as_posix() for directory in ["Sources", "Tests"] for p in (root / directory).rglob("*.swift")}
assert source_paths == actual, f"Unregistered Swift files: {actual - source_paths}"
registered_builds = {objects[build]["fileRef"] for obj in objects.values() if obj["isa"] == "PBXSourcesBuildPhase" for build in obj["files"]}
assert len(registered_builds) == len(actual), "Sources absent from build phases"
targets = {key for key, value in objects.items() if value["isa"] == "PBXNativeTarget"}
assert len(targets) == 4
scheme = ET.parse(root / "DuplicateFinder.xcodeproj/xcshareddata/xcschemes/DuplicateFinder.xcscheme")
for ref in scheme.findall(".//BuildableReference"):
    assert ref.attrib["BlueprintIdentifier"] in targets
print(f"Project references valid: {len(actual)} Swift files, 4 targets, shared scheme. Xcode build still required.")
