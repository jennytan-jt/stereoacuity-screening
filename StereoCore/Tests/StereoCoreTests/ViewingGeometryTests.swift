import Foundation
import Testing
@testable import StereoCore

@Suite("ViewingGeometry")
struct ViewingGeometryTests {

    /// The plan's reference device: a 460 ppi iPhone viewed at 40 cm.
    let reference = ViewingGeometry(pixelsPerInch: 460)

    @Test("defaults to the nominal 40 cm viewing distance")
    func nominalDistance() {
        #expect(reference.viewingDistanceCm == 40)
    }

    @Test("460 ppi at 40 cm is about 28.5 arcsec per pixel")
    func referenceArcsecPerPixel() {
        // Worked by hand: pixel pitch 25.4 mm / 460 = 0.05522 mm; 1 arcsec
        // at 400 mm subtends 400 * tan(1/3600 deg) = 0.001939 mm; ratio
        // 28.47.
        #expect(abs(reference.arcsecPerPixel - 28.47) < 0.01)
    }

    @Test("40 arcsec, the ladder's floor, is about 1.4 px of total disparity")
    func ladderFloorInPixels() {
        #expect(abs(reference.pixels(forArcsec: 40) - 1.405) < 0.005)
    }

    @Test("disparity is effectively linear in arcsec across the ladder")
    func linearAcrossLadder() {
        // Not exactly linear: `tan` curves upward, by about 1 part in 10^6
        // at 400 arcsec. Allow 1e-5 relative, still far tighter than any
        // disparity error that could matter.
        let perArcsec = reference.pixels(forArcsec: 1)
        for arcsec in [400.0, 200, 100, 60, 40] {
            let linear = arcsec * perArcsec
            #expect(abs(reference.pixels(forArcsec: arcsec) - linear) / linear < 1e-5)
        }
    }

    @Test("one pixel's worth of arcsec converts back to one pixel")
    func roundTrip() {
        #expect(abs(reference.pixels(forArcsec: reference.arcsecPerPixel) - 1) < 1e-8)
    }

    @Test("a closer viewer or a coarser screen gets more arcsec per pixel")
    func directionOfDependence() {
        let closer = ViewingGeometry(pixelsPerInch: 460, viewingDistanceCm: 30)
        let coarser = ViewingGeometry(pixelsPerInch: 326)
        #expect(closer.arcsecPerPixel > reference.arcsecPerPixel)
        #expect(coarser.arcsecPerPixel > reference.arcsecPerPixel)
    }
}
