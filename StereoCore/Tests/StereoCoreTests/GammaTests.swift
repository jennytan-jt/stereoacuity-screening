import Testing
@testable import StereoCore

@Suite("Gamma")
struct GammaTests {

    @Test("toLinear and toSRGB are inverses", arguments: [0.0, 0.01, 0.04045, 0.1, 0.5, 0.9, 1.0])
    func roundTrip(value: Double) {
        let linear = Gamma.toLinear(value)
        let backToSRGB = Gamma.toSRGB(linear)
        #expect(abs(backToSRGB - value) < 1e-6)
    }

    @Test("endpoints map to endpoints")
    func endpoints() {
        #expect(Gamma.toLinear(0) == 0)
        #expect(abs(Gamma.toLinear(1) - 1) < 1e-9)
        #expect(Gamma.toSRGB(0) == 0)
        #expect(abs(Gamma.toSRGB(1) - 1) < 1e-9)
    }

    @Test("continuous across the linear/power piecewise boundary")
    func continuity() {
        let justBelow = Gamma.toLinear(0.04045 - 1e-6)
        let justAbove = Gamma.toLinear(0.04045 + 1e-6)
        #expect(abs(justBelow - justAbove) < 1e-6)
    }

    @Test("toLinear darkens midtones (linear light adds up faster than gamma-encoded values suggest)")
    func midtoneDarkening() {
        // A "50% gray" pixel is much less than 50% of the light energy.
        #expect(Gamma.toLinear(0.5) < 0.3)
    }

    @Test("monotonically increasing")
    func monotonic() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map { Gamma.toLinear($0) }
        #expect(samples == samples.sorted())
    }
}
