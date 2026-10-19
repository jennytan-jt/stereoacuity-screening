import Foundation
import Testing
@testable import StereoCore

@Suite("SpacingGrid")
struct SpacingGridTests {

    @Test("finds a point just inside the spacing, in the same or a neighboring cell")
    func findsNearPoints() {
        var grid = SpacingGrid(spacing: 2)
        grid.insert(x: 10, y: 10)
        #expect(grid.hasPoint(near: 11.9, 10))     // same cell
        #expect(grid.hasPoint(near: 8.1, 10))      // cell to the left
        #expect(grid.hasPoint(near: 11.4, 11.4))   // diagonal cell
    }

    @Test("ignores points at or beyond the spacing")
    func ignoresFarPoints() {
        var grid = SpacingGrid(spacing: 2)
        grid.insert(x: 10, y: 10)
        #expect(!grid.hasPoint(near: 12, 10))      // exactly at the spacing
        #expect(!grid.hasPoint(near: 11.5, 11.5))  // diagonal, 2.12 away
        #expect(!grid.hasPoint(near: 30, 30))
    }

    @Test("an empty grid has nothing near anything")
    func empty() {
        #expect(!SpacingGrid(spacing: 1).hasPoint(near: 0, 0))
    }

    @Test(
        "generateDots matches the brute-force version dot for dot",
        arguments: [(UInt64(1), 2.0, 0.3), (2, 1.0, 0.1), (3, 0.75, 0.15), (4, 3.0, 1.0)]
    )
    func dotsMatchBruteForce(seed: UInt64, radius: Double, coverage: Double) {
        let grid = generateDots(seed: seed, width: 160, height: 120, dotRadius: radius, coverage: coverage)
        let brute = bruteForceGenerateDots(seed: seed, width: 160, height: 120, dotRadius: radius, coverage: coverage)
        #expect(grid == brute)
    }

    @Test(
        "generateStereogram matches the brute-force version dot for dot",
        arguments: [(UInt64(1), 2.0, 0.3, 14.0), (2, 1.0, 0.1, 1.4), (3, 0.75, 0.15, 7.0), (4, 1.5, 0.08, 0), (5, 2.0, 0.3, -5.6)]
    )
    func stereogramMatchesBruteForce(seed: UInt64, radius: Double, coverage: Double, disparity: Double) {
        let patch = TargetPatch(centerX: 100, centerY: 80, radius: 50, disparity: disparity)
        let grid = generateStereogram(seed: seed, width: 200, height: 160, dotRadius: radius, coverage: coverage, patch: patch)
        let brute = bruteForceGenerateStereogram(seed: seed, width: 200, height: 160, dotRadius: radius, coverage: coverage, patch: patch)
        #expect(grid.count == brute.count)
        #expect(grid == brute)
    }
}
