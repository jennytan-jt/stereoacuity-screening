import Foundation
import Testing
@testable import StereoCore

@Suite("anaglyph composition")
struct AnaglyphTests {

    /// The (r, g, b, a) bytes of one pixel.
    static func pixel(_ image: AnaglyphImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = 4 * (y * image.width + x)
        return (image.rgba[i], image.rgba[i + 1], image.rgba[i + 2], image.rgba[i + 3])
    }

    static func composed(_ dots: [Dot], width: Int = 40, height: Int = 40) -> AnaglyphImage {
        let (left, right) = render(dots: dots, width: width, height: height)
        return composeAnaglyph(left: left, right: right)
    }

    @Test("buffer is width × height RGBA, fully opaque")
    func layout() {
        let image = Self.composed([], width: 30, height: 20)
        #expect(image.width == 30 && image.height == 20)
        #expect(image.rgba.count == 30 * 20 * 4)
        #expect(stride(from: 3, to: image.rgba.count, by: 4).allSatisfy { image.rgba[$0] == 255 })
    }

    @Test("a dot only the left eye sees lights only the red channel")
    func leftEyeIsRed() {
        let image = Self.composed([Dot(x: 20, y: 20, radius: 2, visibleIn: .left)])
        let center = Self.pixel(image, x: 20, y: 20)
        #expect(center.r == 255)
        #expect(stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { image.rgba[$0 + 1] == 0 && image.rgba[$0 + 2] == 0 })
    }

    @Test("a dot only the right eye sees lights only green and blue, equally")
    func rightEyeIsCyan() {
        let image = Self.composed([Dot(x: 20, y: 20, radius: 2, visibleIn: .right)])
        let center = Self.pixel(image, x: 20, y: 20)
        #expect(center.g == 255 && center.b == 255)
        #expect(stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { image.rgba[$0] == 0 })
        #expect(stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { image.rgba[$0 + 1] == image.rgba[$0 + 2] })
    }

    @Test("disparity lands in the right channels: left copy (red) right of the right copy (cyan)")
    func disparityDirection() {
        // 10 px disparity: left copy at x = 25, right copy at x = 15.
        let image = Self.composed([Dot(x: 20, y: 20, radius: 1, disparity: 10)])
        #expect(Self.pixel(image, x: 25, y: 20).r == 255 && Self.pixel(image, x: 25, y: 20).g == 0)
        #expect(Self.pixel(image, x: 15, y: 20).g == 255 && Self.pixel(image, x: 15, y: 20).r == 0)
    }

    @Test("linear light is gamma-encoded, not written raw")
    func gammaEncoded() {
        #expect(encode(0) == 0)
        #expect(encode(1) == 255)
        // Half linear light is about 73.5% encoded: 0.7354 * 255 = 187.5.
        #expect(encode(0.5) == 188)
    }

    // The renderer's subpixel disparity has to survive 8-bit gamma
    // encoding: rounding the blobs' faint tails could, in principle, skew
    // them. Decode the anaglyph back to linear light and measure it the
    // same way as the unquantized render.
    @Test(
        "patch disparity survives 8-bit encoding at every ladder step",
        arguments: [400.0, 200, 100, 60, 40, 0]
    )
    func disparitySurvivesQuantization(arcsec: Double) {
        let expected = ViewingGeometry(pixelsPerInch: 460).pixels(forArcsec: arcsec)
        let image = renderAnaglyph(
            seed: 21, width: 300, height: 300,
            patch: TargetPatch(centerX: 150, centerY: 150, radius: 70, disparity: expected),
            // The registration measurement needs smooth blobs; see
            // `StereogramDisparityTests.registrationStyle`.
            style: StereogramDisparityTests.registrationStyle
        )
        func channel(_ offset: Int) -> (Int, Int) -> Double {
            { x, y in Gamma.toLinear(Double(image.rgba[4 * (y * image.width + x) + offset]) / 255) }
        }
        let measured = StereogramDisparityTests.measuredShift(
            left: channel(0), right: channel(1), width: image.width,
            windowCenterX: 150 + expected / 2, windowCenterY: 150,
            windowRadius: 70 - abs(expected) / 2 - StereogramDisparityTests.edgeMargin
        )
        #expect(abs(measured - expected) < 0.05, "measured \(measured) px, expected \(expected) px")
    }
}
