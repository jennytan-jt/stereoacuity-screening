import Foundation
import Testing
@testable import StereoCore

@Suite("generateStereogram")
struct StereogramTests {

    static let width = 300
    static let height = 300
    static let dotRadius = 2.0
    static let coverage = 0.3

    static func patch(disparity: Double) -> TargetPatch {
        TargetPatch(centerX: 150, centerY: 150, radius: 70, disparity: disparity)
    }

    static func stereogram(
        seed: UInt64, disparity: Double,
        dotRadius: Double = dotRadius, coverage: Double = coverage
    ) -> [Dot] {
        generateStereogram(
            seed: seed, width: width, height: height,
            dotRadius: dotRadius, coverage: coverage,
            patch: patch(disparity: disparity)
        )
    }

    /// Where each dot lands in one eye's image, worked out from the dot's
    /// own fields the same way `render` places it. Dots that eye can't see
    /// are left out.
    static func imagePositions(of dots: [Dot], in eye: Eyes) -> [(x: Double, y: Double)] {
        let sign: Double = eye == .left ? 1 : -1
        return dots
            .filter { $0.visibleIn.contains(eye) }
            .map { (x: $0.x + sign * $0.disparity / 2, y: $0.y) }
    }

    /// Dot density in one half (left or right of the vertical through the
    /// center) of the ring `inner..<outer` around (centerX, centerY), as a
    /// ratio to the density of the whole disc of radius `reference`.
    /// Counts are pooled across every image in `images` before dividing,
    /// so per-image sampling noise averages out.
    static func pooledDensityRatio(
        _ images: [[(x: Double, y: Double)]],
        centerX: Double, centerY: Double,
        inner: Double, outer: Double, rightHalf: Bool,
        reference: Double
    ) -> Double {
        var ringCount = 0
        var referenceCount = 0
        for points in images {
            for p in points {
                let distance = hypot(p.x - centerX, p.y - centerY)
                if distance < reference { referenceCount += 1 }
                if distance >= inner && distance < outer && (p.x >= centerX) == rightHalf {
                    ringCount += 1
                }
            }
        }
        let ringArea = Double.pi * (outer * outer - inner * inner) / 2
        let referenceArea = Double.pi * reference * reference
        return (Double(ringCount) / ringArea) / (Double(referenceCount) / referenceArea)
    }

    @Test("same seed produces the same stereogram")
    func determinism() {
        #expect(Self.stereogram(seed: 4, disparity: 14) == Self.stereogram(seed: 4, disparity: 14))
    }

    @Test("zero disparity gives both eyes an identical image")
    func zeroDisparityIsInvisible() {
        let dots = Self.stereogram(seed: 6, disparity: 0)
        #expect(dots.allSatisfy { $0.visibleIn == .both })

        let (left, right) = render(dots: dots, width: Self.width, height: Self.height)
        #expect(left.buffer == right.buffer)
    }

    @Test("patch dots carry the patch's disparity and lie inside it; the rest are zero-disparity background")
    func dotRoles() {
        let patch = Self.patch(disparity: 14)
        let dots = Self.stereogram(seed: 8, disparity: 14)
        let patchDots = dots.filter { $0.disparity != 0 }
        let background = dots.filter { $0.disparity == 0 }

        #expect(!patchDots.isEmpty)
        #expect(patchDots.allSatisfy { $0.disparity == 14 && $0.visibleIn == .both })
        #expect(patchDots.allSatisfy { hypot($0.x - patch.centerX, $0.y - patch.centerY) < patch.radius })
        #expect(patchDots.count + background.count == dots.count)
    }

    @Test("with disparity, some background is seen by one eye only, and never where that eye sees the patch")
    func halfOccludedBackground() {
        let patch = Self.patch(disparity: 14)
        let background = Self.stereogram(seed: 8, disparity: 14).filter { $0.disparity == 0 }

        #expect(background.contains { $0.visibleIn == .left })
        #expect(background.contains { $0.visibleIn == .right })
        for dot in background {
            for eye in [Eyes.left, .right] where dot.visibleIn.contains(eye) {
                #expect(!patch.contains(x: dot.x, y: dot.y, in: eye))
            }
        }
    }

    @Test("minimum spacing holds within each eye's image, including across the patch edge", arguments: [Eyes.left, .right])
    func perEyeSpacing(eye: Eyes) {
        let points = Self.imagePositions(of: Self.stereogram(seed: 12, disparity: 14), in: eye)
        let minSpacingSquared = pow(Self.dotRadius * 1.2, 2)
        var violations = 0
        for i in points.indices {
            for j in points.indices where j > i {
                let dx = points[i].x - points[j].x
                let dy = points[i].y - points[j].y
                if dx * dx + dy * dy < minSpacingSquared - 1e-9 { violations += 1 }
            }
        }
        #expect(violations == 0)
    }

    /// Seeds pooled by the edge-density checks. Each image's rings hold
    /// only ~45 dots, so a single image is far too noisy to judge.
    static let pooledSeeds: [UInt64] = Array(1...40)

    /// How far a pooled ring density may stray from 1. Set from the noise
    /// floor: at zero disparity (no edge at all) 40-seed pools of these
    /// rings landed between 0.96 and 1.05. The naive stereogram misses by
    /// far more, as its control test shows.
    static let densityTolerance = 0.07

    // The core monocular-cue check. Disparities are the ladder's extremes
    // at the reference geometry (40 and 400 arcsec at 460 ppi / 40 cm).
    /// Dot settings (Gaussian sigma, coverage) the edge check covers: the
    /// screening default plus the other candidates compared on the device. Sparse fine dots are where an edge cue is most likely
    /// to show, so each candidate gets checked before it can be chosen.
    static let dotSettings: [(sigma: Double, coverage: Double)] = [
        (DotStyle.standard.sigma, DotStyle.standard.coverage),  // follows the default if it changes
        (2.0, 0.30), (1.0, 0.15), (0.75, 0.10), (0.75, 0.15),
    ]

    /// Every combination of eye, disparity, and dot setting, flattened into
    /// one argument list (Swift Testing combines at most two collections
    /// on its own).
    static let edgeCueCases: [(eye: Eyes, disparity: Double, sigma: Double, coverage: Double)] =
        [Eyes.left, .right].flatMap { eye in
            [1.4, 14.0].flatMap { disparity in
                dotSettings.map { (eye, disparity, $0.sigma, $0.coverage) }
            }
        }

    @Test(
        "neither eye alone sees a density change at either side of the patch edge",
        arguments: edgeCueCases
    )
    func noMonocularEdgeCue(eye: Eyes, disparity: Double, sigma: Double, coverage: Double) {
        let patch = Self.patch(disparity: disparity)
        let images = Self.pooledSeeds.map { seed in
            Self.imagePositions(
                of: Self.stereogram(seed: seed, disparity: disparity, dotRadius: sigma, coverage: coverage),
                in: eye
            )
        }
        let eyeCenterX = patch.centerX + patch.offset(in: eye)

        for rightHalf in [false, true] {
            for (inner, outer) in [(patch.radius - 8, patch.radius), (patch.radius, patch.radius + 8)] {
                let ratio = Self.pooledDensityRatio(
                    images, centerX: eyeCenterX, centerY: patch.centerY,
                    inner: inner, outer: outer, rightHalf: rightHalf,
                    reference: 2 * patch.radius
                )
                #expect(abs(ratio - 1) < Self.densityTolerance, "ring \(inner)..<\(outer), \(rightHalf ? "right" : "left") half: density ratio \(ratio)")
            }
        }
    }

    // Control for the test above: the naive stereogram (scatter dots, give
    // the ones inside the disc a disparity) leaves a gap on one side of the
    // shifted disc and a pile-up on the other. If the density check
    // couldn't see that, its passing would mean nothing.
    @Test("the density check does catch the naive shift-only stereogram")
    func densityCheckDetectsNaiveShift() {
        let patch = Self.patch(disparity: 14)
        let images = Self.pooledSeeds.map { seed in
            let naive = generateDots(
                seed: seed, width: Self.width, height: Self.height,
                dotRadius: Self.dotRadius, coverage: Self.coverage
            ).map { dot -> Dot in
                var dot = dot
                if hypot(dot.x - patch.centerX, dot.y - patch.centerY) < patch.radius {
                    dot.disparity = patch.disparity
                }
                return dot
            }
            return Self.imagePositions(of: naive, in: .left)
        }
        let eyeCenterX = patch.centerX + patch.offset(in: .left)

        // Left eye, patch shifted right by 7 px. Its leading (right) edge
        // lands on background that was never removed, piling up just
        // inside the shifted disc; its trailing (left) edge vacates a
        // crescent nothing refills, just outside it.
        let pileUp = Self.pooledDensityRatio(
            images, centerX: eyeCenterX, centerY: patch.centerY,
            inner: patch.radius - 8, outer: patch.radius, rightHalf: true,
            reference: 2 * patch.radius
        )
        let gap = Self.pooledDensityRatio(
            images, centerX: eyeCenterX, centerY: patch.centerY,
            inner: patch.radius, outer: patch.radius + 8, rightHalf: false,
            reference: 2 * patch.radius
        )
        #expect(pileUp - 1 > 3 * Self.densityTolerance, "pile-up side density ratio \(pileUp)")
        #expect(1 - gap > 3 * Self.densityTolerance, "gap side density ratio \(gap)")
    }

    @Test("rejects a patch whose shifted copy would run off the canvas")
    func rejectsOffCanvasPatch() async {
        // Fits at zero disparity (edge at x = 300) but not once each eye's
        // copy shifts by 5 px.
        await #expect(processExitsWith: .failure) {
            _ = generateStereogram(
                seed: 1, width: 300, height: 300, dotRadius: 2, coverage: 0.3,
                patch: TargetPatch(centerX: 230, centerY: 150, radius: 70, disparity: 10)
            )
        }
    }
}
