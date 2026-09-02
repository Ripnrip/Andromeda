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
            var colorCounts: [UInt32: Int] = [:]
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
                        colorCounts[r << 10 | g << 5 | b, default: 0] += 1
                    }
                    x += stride
                }
                y += stride
            }
            guard samples >= Self.minimumSampleCount else { continue }
            if colorCounts.count <= Self.flatColorCount {
                voids.append("\(png.lastPathComponent) — flat (\(colorCounts.count) sampled colors)")
                continue
            }
            // Near-void: a handful of incidental colors AND one color dominating.
            // Codex P2: "a void snapshot containing three or four incidental
            // colors with 99%+ of samples in one background color passes."
            // Legitimately minimal specimens (brand mark, quiet button) carry
            // 12+ distinct sampled colors in their glyphs — they spread real
            // content even though the canvas background dominates. So the
            // dominance test only condemns near-flat color counts.
            let nearFlatColorBound = Self.flatColorCount + 2
            if colorCounts.count <= nearFlatColorBound,
               let dominantShare = colorCounts.values.max(), dominantShare >= Self.minimumSampleCount,
               Double(dominantShare) / Double(samples) > Self.voidDominance {
                let share = Double(dominantShare) / Double(samples)
                voids.append(
                    "\(png.lastPathComponent) — near-void (dominant color covers \(String(format: "%.1f", share * 100))% of \(samples) samples, \(colorCounts.count) colors)"
                )
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
