import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CoreVideo

struct DatasetManifest: Codable {
    let mediaRoot: String
    let photoFiles: Int
    let videoFiles: Int
    let uniqueFiles: Int
    let groups: [[String]]
    let totalBytes: Int64
    let redundantBytes: Int64
    let generationSeconds: Double
}
@main struct GenerateMedia {
    static func jpeg(_ url: URL, seed: UInt64) throws {
        let width = 1280, height = 960
        var state = seed
        var pixels = Data(count: width * height * 3)
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<bytes.count { state = state &* 6364136223846793005 &+ 1; bytes[i] = UInt8(truncatingIfNeeded: state >> 32) }
        }
        let provider = CGDataProvider(data: pixels as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    static func video(_ url: URL) async throws {
        let width = 1280, height = 720
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000, AVVideoMaxKeyFrameIntervalKey: 30]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var buffers: [CVPixelBuffer] = []
        for seed in 1...12 {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess, let buffer else { throw CocoaError(.coderInvalidValue) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            var state = UInt64(seed)
            for y in 0..<height { for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1
                let i = y * stride + x * 4
                ptr[i] = UInt8(truncatingIfNeeded: state >> 24); ptr[i+1] = UInt8(truncatingIfNeeded: state >> 32)
                ptr[i+2] = UInt8(truncatingIfNeeded: state >> 40); ptr[i+3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer, []); buffers.append(buffer)
        }
        for frame in 0..<180 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(buffers[frame % buffers.count], withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), try await asset.load(.duration).seconds >= 5.9 else { throw CocoaError(.coderInvalidValue) }
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileWriteInvalidFileName) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let fm = FileManager.default, start = Date()
        guard !fm.fileExists(atPath: root.path) else { throw CocoaError(.fileWriteFileExists) }
        let media = root.appendingPathComponent("Media"), seeds = root.appendingPathComponent("Seeds")
        try fm.createDirectory(at: media, withIntermediateDirectories: true); try fm.createDirectory(at: seeds, withIntermediateDirectories: true)
        try Data("DuplicateFinder generated media benchmark 0.5.0".utf8).write(to: root.appendingPathComponent("GENERATED-DATASET.txt"))
        var bases: [Data] = []
        for n in 0..<12 { let url = seeds.appendingPathComponent("seed-\(n).jpg"); try jpeg(url, seed: UInt64(n+1)); bases.append(try Data(contentsOf: url)) }
        let movie = seeds.appendingPathComponent("seed.mov"); try await video(movie)
        let movieBytes = try Data(contentsOf: movie)
        print("Generated valid JPEG and H.264 MOV seeds")
        var groups: [[String]] = [], total: Int64 = 0, redundant: Int64 = 0
        func taggedJPEG(_ number: Int) -> Data {
            let marker = Data(String(format: "DuplicateFinder fixture %08d", number).utf8)
            let length = marker.count + 2
            var out = Data([0xff, 0xd8, 0xff, 0xfe, UInt8(length >> 8), UInt8(length & 255)])
            out.append(marker); out.append(bases[number % bases.count].dropFirst(2)); return out
        }
        for group in 0..<200 {
            let folder = media.appendingPathComponent(String(format: "Photos/Set-%03d", group)); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = taggedJPEG(group), first = folder.appendingPathComponent("copy-00.jpg")
            try data.write(to: first); var paths = [String(first.path.dropFirst(media.path.count + 1))]
            for n in 1..<50 { let copy = folder.appendingPathComponent(String(format: "copy-%02d.jpg", n)); try fm.copyItem(at: first, to: copy); paths.append(String(copy.path.dropFirst(media.path.count + 1))) }
            groups.append(paths); total += Int64(data.count * 50); redundant += Int64(data.count * 49)
            if group % 50 == 49 { print("Created \((group+1)*50) duplicate photo fixtures") }
        }
        let uniques = media.appendingPathComponent("Photos/Unique"); try fm.createDirectory(at: uniques, withIntermediateDirectories: true)
        for n in 0..<2000 { let data = taggedJPEG(10_000+n); try data.write(to: uniques.appendingPathComponent(String(format:"photo-%04d.jpg",n))); total += Int64(data.count) }
        for group in 0..<20 {
            let folder = media.appendingPathComponent(String(format:"Videos/Set-%02d",group)); try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var data = movieBytes
            let tag = Data(String(format:"DuplicateFinder movie %04d",group).utf8), length = UInt32(tag.count + 8)
            data.append(contentsOf: [UInt8(length >> 24),UInt8((length >> 16)&255),UInt8((length >> 8)&255),UInt8(length&255)])
            data.append(Data("free".utf8)); data.append(tag)
            let first = folder.appendingPathComponent("copy-00.mov"); try data.write(to: first)
            var paths = [String(first.path.dropFirst(media.path.count + 1))]
            for n in 1..<10 { let copy = folder.appendingPathComponent(String(format:"copy-%02d.mov",n)); try fm.copyItem(at:first,to:copy); paths.append(String(copy.path.dropFirst(media.path.count + 1))) }
            groups.append(paths); total += Int64(data.count * 10); redundant += Int64(data.count * 9)
        }
        // Validate a tagged JPEG and tagged MOV, not just their seed encodings.
        let samplePhoto = media.appendingPathComponent(groups[0][0]), sampleMovie = media.appendingPathComponent(groups.last![0])
        guard let image = CGImageSourceCreateWithURL(samplePhoto as CFURL,nil), CGImageSourceCreateImageAtIndex(image,0,nil) != nil,
              try await AVURLAsset(url:sampleMovie).load(.isPlayable) else { throw CocoaError(.coderInvalidValue) }
        let manifest = DatasetManifest(mediaRoot: media.path, photoFiles:12000, videoFiles:200, uniqueFiles:2000, groups:groups,
                                       totalBytes:total, redundantBytes:redundant, generationSeconds:Date().timeIntervalSince(start))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(manifest).write(to:root.appendingPathComponent("manifest.json"))
        print("READY: 12,200 valid media files, \(total) logical bytes, 220 expected duplicate groups at \(media.path)")
    }
}
