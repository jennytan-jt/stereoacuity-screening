import Foundation

/// Converts between the angular disparities the ladder is specified in
/// (arcseconds) and the on-screen pixel offsets `Dot.disparity` is
/// specified in.
///
/// The conversion depends on two physical facts: how big a pixel is
/// (`pixelsPerInch`, the panel's *physical* pixel density, not UIKit
/// points) and how far away the eyes are. Distance is fixed at the
/// nominal value rather than tracked live: the distance state machine
/// pauses the test outside ±10% of it, and the measured distance is
/// logged with each trial, so analysis can correct for drift afterwards
/// without the stimulus itself depending on a noisy live reading.
public struct ViewingGeometry: Sendable {
    public static let nominalViewingDistanceCm = 40.0

    public let pixelsPerInch: Double
    public let viewingDistanceCm: Double

    public init(pixelsPerInch: Double, viewingDistanceCm: Double = ViewingGeometry.nominalViewingDistanceCm) {
        precondition(pixelsPerInch > 0, "pixel density must be positive")
        precondition(viewingDistanceCm > 0, "viewing distance must be positive")
        self.pixelsPerInch = pixelsPerInch
        self.viewingDistanceCm = viewingDistanceCm
    }

    /// Total on-screen disparity, in pixels, for an angular disparity in
    /// arcseconds. This is the *total* offset between the eyes' images;
    /// `render` splits it in half per eye.
    ///
    /// Uses the exact `tan` rather than the small-angle shortcut. Even at
    /// 400 arcsec the two differ by about one part in a million (0.00002 px),
    /// far below anything that matters, but the exact form costs nothing and
    /// leaves no approximation to argue about.
    public func pixels(forArcsec arcsec: Double) -> Double {
        let radians = arcsec / 3600 * .pi / 180
        let distanceInches = viewingDistanceCm / 2.54
        return distanceInches * tan(radians) * pixelsPerInch
    }

    /// How many arcseconds one pixel subtends: the finest disparity step
    /// the screen could show if dots had to sit on whole pixels. The
    /// Gaussian blobs exist to get below it.
    public var arcsecPerPixel: Double {
        1 / pixels(forArcsec: 1)
    }
}
