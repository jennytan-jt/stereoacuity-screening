import Foundation
import Testing
@testable import StereoCore

@Suite("generateDots")
struct DotGenerationTests {

    @Test("same seed produces the same dot field")
    func determinism() {
        let a = generateDots(seed: 7, width: 200, height: 200, dotRadius: 2, coverage: 0.3)
        let b = generateDots(seed: 7, width: 200, height: 200, dotRadius: 2, coverage: 0.3)
        #expect(a == b)
    }

    @Test("different seeds produce different dot fields")
    func seedSensitivity() {
        let a = generateDots(seed: 1, width: 200, height: 200, dotRadius: 2, coverage: 0.3)
        let b = generateDots(seed: 2, width: 200, height: 200, dotRadius: 2, coverage: 0.3)
        #expect(a != b)
    }

    @Test("all dots land within canvas bounds")
    func withinBounds() {
        let dots = generateDots(seed: 3, width: 150, height: 100, dotRadius: 1.5, coverage: 0.35)
        for dot in dots {
            #expect(dot.x >= 0 && dot.x < 150)
            #expect(dot.y >= 0 && dot.y < 100)
        }
    }

    @Test("no two dots are closer than the minimum spacing")
    func minimumSpacing() {
        let radius = 2.0
        let minSpacingFactor = 1.2
        let dots = generateDots(seed: 5, width: 200, height: 200, dotRadius: radius, coverage: 0.3, minSpacingFactor: minSpacingFactor)
        let minSpacingSquared = pow(radius * minSpacingFactor, 2)

        for i in 0..<dots.count {
            for j in (i + 1)..<dots.count where j != i {
                let dx = dots[i].x - dots[j].x
                let dy = dots[i].y - dots[j].y
                #expect(dx * dx + dy * dy >= minSpacingSquared - 1e-9)
            }
        }
    }

    @Test("dot count roughly matches the requested nominal coverage")
    func approximateDensity() {
        let width = 400
        let height = 400
        let radius = 2.0
        let coverage = 0.25
        let dots = generateDots(seed: 11, width: width, height: height, dotRadius: radius, coverage: coverage)

        let dotArea = Double.pi * radius * radius
        let expectedCount = coverage * Double(width * height) / dotArea

        // Rejection sampling can fall short of the target as the canvas
        // fills up, so allow it to land anywhere from noticeably short of
        // the target up to the target itself.
        #expect(Double(dots.count) > expectedCount * 0.5)
        #expect(Double(dots.count) <= expectedCount)
    }

    @Test("reaches the full target at the densest allowed packing")
    func fillsAtPackingLimit() {
        // coverage * factor² = 1.96, just under `maxPackingLoad`.
        let width = 120
        let height = 120
        let radius = 2.0
        let coverage = 1.0
        let dots = generateDots(seed: 9, width: width, height: height, dotRadius: radius, coverage: coverage, minSpacingFactor: 1.4)

        let targetCount = Int((coverage * Double(width * height) / (Double.pi * radius * radius)).rounded())
        #expect(dots.count == targetCount)
    }

    @Test("rejects a packing too dense for rejection sampling to fill")
    func rejectsOverPacking() async {
        // coverage * factor² = 4.0, double `maxPackingLoad`. An exit test
        // runs the closure in a child process, so the precondition trap
        // can be observed without crashing the test runner.
        await #expect(processExitsWith: .failure) {
            _ = generateDots(seed: 9, width: 120, height: 120, dotRadius: 2, coverage: 1.0, minSpacingFactor: 2.0)
        }
    }
}
