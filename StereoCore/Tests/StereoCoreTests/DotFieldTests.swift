import Foundation
import Testing
@testable import StereoCore

@Suite("render disparity accuracy")
struct DotFieldTests {

    /// Intensity-weighted centroid x-position of whatever's lit up within
    /// `halfWidth`/`halfHeight` of (nearX, nearY) in `field`. This only
    /// reads pixel values back through `DotField`'s subscript, so it
    /// doesn't depend on how `render` or `splat` do their work internally
    /// — it measures the actual rendered image, the same way a real
    /// measurement off a screen would.
    private func centroidX(
        of field: DotField,
        nearX: Double,
        nearY: Double,
        halfWidth: Double,
        halfHeight: Double
    ) -> Double {
        let minX = max(0, Int((nearX - halfWidth).rounded(.down)))
        let maxX = min(field.width - 1, Int((nearX + halfWidth).rounded(.up)))
        let minY = max(0, Int((nearY - halfHeight).rounded(.down)))
        let maxY = min(field.height - 1, Int((nearY + halfHeight).rounded(.up)))

        var weightedSum = 0.0
        var totalWeight = 0.0
        for y in minY...maxY {
            for x in minX...maxX {
                let weight = field[x, y]
                weightedSum += Double(x) * weight
                totalWeight += weight
            }
        }
        precondition(totalWeight > 0, "no lit pixels found near (\(nearX), \(nearY)) — search box too small or dot not rendered")
        return weightedSum / totalWeight
    }

    /// Renders a single isolated dot and recovers its disparity by
    /// comparing the two eyes' centroids, independent of the disparity
    /// value `render` was told to use.
    private func measuredDisparity(
        trueX: Double,
        trueY: Double,
        radius: Double,
        disparity: Double,
        width: Int = 200,
        height: Int = 200
    ) -> Double {
        let dot = Dot(x: trueX, y: trueY, radius: radius, disparity: disparity)
        let (left, right) = render(dots: [dot], width: width, height: height)

        // The search box has to be wide enough to contain the blob's full
        // extent in *either* eye: the disparity shift plus the Gaussian's
        // own 3-sigma reach, with a little margin. Too narrow and this
        // measurement would truncate the blob itself and bias its own
        // centroid — the same edge-truncation trap `splat` is subject to
        // at the canvas boundary, just self-inflicted here instead.
        let halfWidth = abs(disparity) / 2 + radius * 3 + 2
        let halfHeight = radius * 3 + 2

        let leftX = centroidX(of: left, nearX: trueX, nearY: trueY, halfWidth: halfWidth, halfHeight: halfHeight)
        let rightX = centroidX(of: right, nearX: trueX, nearY: trueY, halfWidth: halfWidth, halfHeight: halfHeight)
        return leftX - rightX
    }

    // Disparities spanning roughly the ladder's real range: the plan notes
    // 40 arcsec is about 1.4px and disparity scales with arcsec, so 400
    // arcsec lands around 14px at the same viewing geometry. Includes zero
    // (the catch-trial case) and a negative value (uncrossed) to make sure
    // the sign isn't flipped.
    @Test(
        "measured disparity matches requested disparity across the ladder's range",
        arguments: [0.0, 1.4, 2.8, 5.6, 14.0, -5.6]
    )
    func disparityAccuracy(disparity: Double) {
        let measured = measuredDisparity(trueX: 100, trueY: 100, radius: 2.0, disparity: disparity)
        #expect(abs(measured - disparity) < 0.05)
    }

    // The same check driven by the real ladder in arcsec, converted at the
    // plan's reference geometry (460 ppi, 40 cm), so the conversion and
    // the renderer are verified together.
    @Test(
        "measured disparity matches each ladder step converted from arcsec",
        arguments: [400.0, 200, 100, 60, 40]
    )
    func ladderAccuracy(arcsec: Double) {
        let disparity = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: arcsec)
        let measured = measuredDisparity(trueX: 100, trueY: 100, radius: 2.0, disparity: disparity)
        #expect(abs(measured - disparity) < 0.05)
    }

    @Test("accuracy holds at a small dot radius, where discretization error is relatively largest")
    func smallRadiusStressTest() {
        let measured = measuredDisparity(trueX: 50, trueY: 50, radius: 0.75, disparity: 3.0)
        #expect(abs(measured - 3.0) < 0.05)
    }
}
