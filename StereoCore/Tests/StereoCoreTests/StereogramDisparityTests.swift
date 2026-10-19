import Foundation
import Testing
@testable import StereoCore

/// End-to-end disparity check: generate a full stereogram, render it, and
/// recover the disparity purely from the two rendered images, the way a
/// measurement off the screen would, without looking at `Dot.disparity`.
///
/// The measurement is image registration: find the horizontal shift `s`
/// that best lines the right eye's image up with the left eye's inside a
/// window. Since `render` draws a dot's left copy at x + d/2 and its right
/// copy at x - d/2, the left image equals the right image moved right by d,
/// so the best shift *is* the disparity.
@Suite("stereogram disparity, measured from rendered images")
struct StereogramDisparityTests {

    static let width = 300
    static let height = 300
    static let patchRadius = 70.0

    /// Pixels at least this far inside the patch edge (in the left eye's
    /// image) are used to measure the patch. The margin keeps out
    /// background blobs whose Gaussian tails reach across the edge, and the
    /// one-eye crescents, which have no partner to match in the other image.
    static let edgeMargin = 10.0

    /// Measured horizontal shift between the eyes inside a circular window
    /// of the left image.
    ///
    /// Two stages:
    /// 1. **Whole-pixel search:** try every integer shift in `searchRange`
    ///    and keep the one with the smallest summed squared difference.
    ///    Nothing about the expected answer goes in, only a wide range.
    /// 2. **Subpixel refinement** (one Lucas-Kanade step): near the best
    ///    whole shift s0, a further shift δ changes each right-image pixel
    ///    by about -δ × (its horizontal slope). Solving that linear model
    ///    by least squares over the window gives
    ///    δ = -Σ g·(L - R_s0) / Σ g². Using the average of both images'
    ///    slopes for g keeps the estimate symmetric between the eyes.
    static func measuredShift(
        left: DotField, right: DotField,
        windowCenterX: Double, windowCenterY: Double, windowRadius: Double,
        searchRange: ClosedRange<Int> = -20...20
    ) -> Double {
        measuredShift(
            left: { left[$0, $1] }, right: { right[$0, $1] }, width: left.width,
            windowCenterX: windowCenterX, windowCenterY: windowCenterY, windowRadius: windowRadius,
            searchRange: searchRange
        )
    }

    /// The same measurement over any pair of images, given as functions
    /// from (x, y) to linear-light intensity, so it can also measure
    /// images that aren't `DotField`s, such as a decoded anaglyph.
    static func measuredShift(
        left: (Int, Int) -> Double, right: (Int, Int) -> Double, width: Int,
        windowCenterX: Double, windowCenterY: Double, windowRadius: Double,
        searchRange: ClosedRange<Int> = -20...20
    ) -> Double {
        // Window pixels, kept 2 px clear of where the search could push
        // them off the canvas (the slope uses x ± 2).
        var window: [(x: Int, y: Int)] = []
        let minX = Int(windowCenterX - windowRadius)
        let maxX = Int(windowCenterX + windowRadius)
        let minY = Int(windowCenterY - windowRadius)
        let maxY = Int(windowCenterY + windowRadius)
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = Double(x) - windowCenterX
                let dy = Double(y) - windowCenterY
                guard dx * dx + dy * dy <= windowRadius * windowRadius else { continue }
                precondition(
                    x - searchRange.upperBound - 2 >= 0 && x - searchRange.lowerBound + 2 < width,
                    "window plus search range runs off the canvas"
                )
                window.append((x, y))
            }
        }

        func sumSquaredDifference(shift s: Int) -> Double {
            window.reduce(0) { total, p in
                let diff = left(p.x, p.y) - right(p.x - s, p.y)
                return total + diff * diff
            }
        }
        let s0 = searchRange.min { sumSquaredDifference(shift: $0) < sumSquaredDifference(shift: $1) }!

        var numerator = 0.0
        var denominator = 0.0
        for p in window {
            let leftSlope = slope(of: left, x: p.x, y: p.y)
            let rightSlope = slope(of: right, x: p.x - s0, y: p.y)
            let g = (leftSlope + rightSlope) / 2
            numerator += g * (left(p.x, p.y) - right(p.x - s0, p.y))
            denominator += g * g
        }
        return Double(s0) - numerator / denominator
    }

    /// Horizontal slope of the image at a pixel, from the five-point
    /// central difference. The simpler three-point version,
    /// (f(x+1) - f(x-1)) / 2, underestimates the slope of blobs this
    /// small, and that error flows straight into the subpixel step.
    static func slope(of image: (Int, Int) -> Double, x: Int, y: Int) -> Double {
        (-image(x + 2, y) + 8 * image(x + 1, y) - 8 * image(x - 1, y) + image(x - 2, y)) / 12
    }

    /// Dot style for the whole-field registration tests. Deliberately *not*
    /// `DotStyle.standard`: the subpixel step estimates image slopes from
    /// neighboring pixels, which only works for smooth blobs. At 1 px sigma
    /// the estimate breaks down (a deliberate 0.1 px error reads as about
    /// 0.05 px), so the screening style is checked dot by dot instead, in
    /// `standardStyleDotsRenderAtTheirDisparity`.
    static let registrationStyle = DotStyle(sigma: 2, coverage: 0.3)

    static func renderedStereogram(seed: UInt64, disparity: Double) -> (left: DotField, right: DotField) {
        let style = registrationStyle
        let dots = generateStereogram(
            seed: seed, width: width, height: height, dotRadius: style.sigma, coverage: style.coverage,
            patch: TargetPatch(centerX: 150, centerY: 150, radius: patchRadius, disparity: disparity)
        )
        return render(dots: dots, width: width, height: height)
    }

    // Zero is the catch-trial case: the patch must measure as flat.
    @Test(
        "patch disparity measured from the rendered images matches each ladder step",
        arguments: [400.0, 200, 100, 60, 40, 0]
    )
    func patchDisparity(arcsec: Double) {
        let expected = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: arcsec)
        for seed: UInt64 in [21, 22, 23] {
            let (left, right) = Self.renderedStereogram(seed: seed, disparity: expected)
            let measured = Self.measuredShift(
                left: left, right: right,
                windowCenterX: 150 + expected / 2, windowCenterY: 150,
                windowRadius: Self.patchRadius - abs(expected) / 2 - Self.edgeMargin
            )
            #expect(abs(measured - expected) < 0.05, "seed \(seed): measured \(measured) px, expected \(expected) px")
        }
    }

    // Control: the measurement must be sharp enough to fail a renderer
    // that's off by more than the 0.05 px tolerance, not just pass a good
    // one. Render 0.1 px more disparity than the "expected" value at the
    // ladder's floor and check the error is visible.
    @Test("measurement catches a disparity that is 0.1 px off")
    func detectsDisparityError() {
        let claimed = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: 40)
        let (left, right) = Self.renderedStereogram(seed: 21, disparity: claimed + 0.1)
        let measured = Self.measuredShift(
            left: left, right: right,
            windowCenterX: 150 + claimed / 2, windowCenterY: 150,
            windowRadius: Self.patchRadius - abs(claimed) / 2 - Self.edgeMargin
        )
        #expect(measured - claimed > 0.05, "measured \(measured) px against claimed \(claimed) px")
    }

    @Test("background measured from the rendered images has zero disparity", arguments: [400.0, 40])
    func backgroundDisparity(arcsec: Double) {
        let disparity = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: arcsec)
        let (left, right) = Self.renderedStereogram(seed: 31, disparity: disparity)
        // A window in the top-left corner, well clear of the patch (which
        // spans roughly 73...227 in both x and y at 400 arcsec).
        let measured = Self.measuredShift(
            left: left, right: right,
            windowCenterX: 45, windowCenterY: 45, windowRadius: 22
        )
        #expect(abs(measured) < 0.05, "measured \(measured) px")
    }

    /// Brightness-weighted x-center of whatever `with` has and `without`
    /// lacks, near (centerX, centerY): one dot's own pixels, exactly as they
    /// ended up in the final image, overlaps and brightness capping included.
    static func centroidXOfDifference(
        _ with: DotField, _ without: DotField, centerX: Double, centerY: Double, halfSize: Double
    ) -> Double {
        var weightedSum = 0.0
        var totalWeight = 0.0
        let minX = max(0, Int((centerX - halfSize).rounded(.down)))
        let maxX = min(with.width - 1, Int((centerX + halfSize).rounded(.up)))
        let minY = max(0, Int((centerY - halfSize).rounded(.down)))
        let maxY = min(with.height - 1, Int((centerY + halfSize).rounded(.up)))
        for y in minY...maxY {
            for x in minX...maxX {
                let weight = with[x, y] - without[x, y]
                weightedSum += Double(x) * weight
                totalWeight += weight
            }
        }
        return weightedSum / totalWeight
    }

    // The screening style, checked one dot at a time: render the field with
    // and without each patch dot, measure what that dot contributes in each
    // eye, and compare the two eyes. Most dots land within 0.001 px. A few
    // percent are off by more than 0.05 px, all of them where overlapping
    // blobs exceed full brightness and get capped, which flattens a dot
    // differently in each eye. Those errors average out across the patch
    // (mean under 0.002 px), and it's the patch as a whole that's seen in
    // depth, so the requirement is on the mean and the bulk, not every dot.
    @Test(
        "screening-style patch dots render at their disparity, on average and for 95% of dots",
        arguments: [400.0, 200, 100, 60, 40]
    )
    func standardStyleDotsRenderAtTheirDisparity(arcsec: Double) {
        let style = DotStyle.standard
        let disparity = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: arcsec)
        let dots = generateStereogram(
            seed: 1, width: Self.width, height: Self.height, dotRadius: style.sigma, coverage: style.coverage,
            patch: TargetPatch(centerX: 150, centerY: 150, radius: Self.patchRadius, disparity: disparity)
        )
        let (left, right) = render(dots: dots, width: Self.width, height: Self.height)
        let halfSize = 5 * style.sigma

        // Every 3rd patch dot keeps the test quick; ~150 dots is plenty.
        var errors: [Double] = []
        for (index, dot) in dots.enumerated() where dot.disparity != 0 && index % 3 == 0 {
            var others = dots
            others.remove(at: index)
            let (leftWithout, rightWithout) = render(dots: others, width: Self.width, height: Self.height)
            let leftX = Self.centroidXOfDifference(left, leftWithout, centerX: dot.x + disparity / 2, centerY: dot.y, halfSize: halfSize)
            let rightX = Self.centroidXOfDifference(right, rightWithout, centerX: dot.x - disparity / 2, centerY: dot.y, halfSize: halfSize)
            errors.append(leftX - rightX - disparity)
        }

        let meanError = errors.reduce(0, +) / Double(errors.count)
        let sortedMagnitudes = errors.map(abs).sorted()
        let percentile95 = sortedMagnitudes[Int(Double(sortedMagnitudes.count) * 0.95)]
        #expect(errors.count > 100)
        #expect(abs(meanError) < 0.01, "mean error \(meanError) px over \(errors.count) dots")
        #expect(percentile95 < 0.05, "95th percentile error \(percentile95) px")
    }
}
