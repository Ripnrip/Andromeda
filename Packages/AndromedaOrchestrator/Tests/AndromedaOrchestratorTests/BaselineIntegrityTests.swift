import AppKit
import Foundation
import Testing

// MARK: - Baseline integrity

//
// The vacuous-suite guard: a snapshot baseline that is a near-uniform void
// passes every verify while showing nothing. That exact failure shipped green
// on this package once (2-unique-color gallery baselines) — this suite makes
// it impossible to land again. A baseline must carry real content: more than
// `minimumUniqueColors` distinct sampled colors.
//
// Scans the committed `__Snapshots__` trees of this package (both suites).

@Suite(.serialized)
struct BaselineIntegrityTests {
    /// A near-flat image with this few distinct sampled colors is a void —
    /// unless the fourth condition (dominance) exonerates a legitimately
    /// minimal specimen (e.g. a thin bar).
    static let flatColorCount = 2

    /// A void's signature: nearly every sampled pixel is one color. A thin
    /// real specimen (ShareBar) spreads 3-4 colors over 3-4% of its canvas;
    /// the original failure was 99.9% single-color.
    static let voidDominance = 0.99

    /// An image yielding fewer samples than this is too small to judge —
    /// skip rather than condemn.
    static let minimumSampleCount = 64

    /// Adaptive stride: dense enough to hit small specimens inside wide
    /// canvases, sparse enough to keep the audit fast. The original failure
    /// (2-color 1280×900 gallery) still fails at any stride.
    static func stride(for dimension: Int) -> Int {
        max(2, dimension / 64)
    }

    @Test("No baseline is a void")
    func baselinesCarryContent() throws {
        let snapshotsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)

        let pngs = try fileManagerPNGs(under: snapshotsRoot)

        #expect(!pngs.isEmpty, "No committed baselines found under \(snapshotsRoot.path) — record first")

        var voids: [String] = []
        for png in pngs {
            guard let image = NSImage(contentsOf: png),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff)
            else {
                voids.append("\(png.lastPathComponent) — unreadable")
                continue
            }
            let width = rep.pixelsWide, height = rep.pixelsHigh
            let stride = Self.stride(for: min(width, height))
            var colors = Set<UInt32>()
            var samples = 0
            var y = 0
            while y < height {
                var x = 0
                while x < width {
                    if let c = rep.colorAt(x: x, y: y) {
                        samples += 1
                        let r = UInt32(c.redComponent * 31)
                        let g = UInt32(c.greenComponent * 31)
                        let b = UInt32(c.blueComponent * 31)
                        colors.insert(r << 10 | g << 5 | b)
                    }
                    x += stride
                }
                y += stride
            }
            guard samples >= Self.minimumSampleCount else { continue }
            if colors.count <= Self.flatColorCount {
                voids.append("\(png.lastPathComponent) — flat (\(colors.count) sampled colors)")
            }
        }
        #expect(voids.isEmpty, "Void/near-void baselines (the vacuous-suite failure): \(voids.joined(separator: "; "))")
    }

    private func fileManagerPNGs(under dir: URL) throws -> [URL] {
        var result: [URL] = []
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return result
        }
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        for item in contents {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                result += try fileManagerPNGs(under: item)
            } else if item.pathExtension.lowercased() == "png" {
                result.append(item)
            }
        }
        return result
    }
}
