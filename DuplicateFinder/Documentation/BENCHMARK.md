# Generated photo/video benchmark — 0.5.0

31 October 2026 (Asia/Dubai). Read-only test of the same core engine included in the optimized Release app, on the current Apple Silicon Mac running macOS 27.2.

| Measure | Result |
| --- | ---: |
| Files | 12,200 |
| Valid JPEG images | 12,000 |
| Playable H.264 MOV files | 200 |
| Logical input size | 18,731,789,642 bytes (18.73 GB / 17.45 GiB) |
| Expected / detected duplicate groups | 220 / 220 |
| Duplicate-group members | 10,200 |
| Unique files | 2,000 |
| Redundant logical data | 15,561,980,604 bytes |
| Total scan time | 53.12 seconds |
| Enumeration time | 17.54 seconds |
| Peak process memory | 239,206,400 bytes (228.13 MiB) |
| Skipped / inaccessible files | 0 |
| Exact agreement with the generated manifest | Yes |

The validator compares the complete set of file paths in every detected group with the generated manifest; matching only the group count would not pass. No file selection or removal is performed by this benchmark.

## Dataset

Generated JPEG noise images are encoded with ImageIO. A six-second 1280×720 H.264 movie is encoded using AVFoundation. Both generated formats are decoded/validated, including a tagged final JPEG and a playable final MOV. The files are not arbitrary bytes with media extensions.

Photos include 200 groups of 50 exact copies plus 2,000 unique files. Video includes 20 groups of 10 exact copies. Valid JPEG comments and MOV free boxes distinguish fixture identities in the actual file contents. Similar-looking images are intentionally not treated as exact duplicates.

The dataset and full membership manifest remain in `../Benchmarks/0.5.0-full/`. Only `Media/` is scanned; generation seeds and the manifest are outside the scan root. The folder occupies approximately 17 GiB on this Mac. It contains generated test data only.

## Reproduce

On an Apple Silicon Mac with Xcode setup complete:

```sh
zsh Scripts/benchmark.sh
```

The script reuses a complete generated dataset, or generates it if absent. Generation uses the macOS media encoder and needs normal access to that service. A partial dataset is not silently overwritten. The result is saved beside the manifest as `report.json`; a copy of this run is in `BENCHMARK_RESULTS.json`.

## Limits

This is a generated dataset on one Mac. Filesystem caching, APFS copying/cloning, normal background activity, storage hardware, and file formats affect timings. It is not a cold-disk benchmark, a real customer library, an Intel runtime test, a cloud-provider test, or evidence of million-file performance. Memory is measured for the standalone core benchmark process, not the graphical app with thumbnails.
