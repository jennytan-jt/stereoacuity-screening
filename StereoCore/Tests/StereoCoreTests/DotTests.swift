import Testing
@testable import StereoCore

@Suite("Dot")
struct DotTests {

    @Test("dots with identical fields are equal")
    func equality() {
        let a = Dot(x: 10.5, y: 20.25, radius: 1.5)
        let b = Dot(x: 10.5, y: 20.25, radius: 1.5)
        #expect(a == b)
    }

    @Test("dots differing only by subpixel position are not equal")
    func subpixelSensitivity() {
        let a = Dot(x: 10.5, y: 20.25, radius: 1.5)
        let b = Dot(x: 10.500001, y: 20.25, radius: 1.5)
        #expect(a != b)
    }
}
