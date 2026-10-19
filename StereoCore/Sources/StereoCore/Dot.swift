/// A single dot in a random-dot stereogram field.
///
/// `x` and `y` are subpixel centers (not snapped to the pixel grid) because
/// the whole point of this app is to present disparities smaller than one
/// pixel — if we rounded to integer pixel coordinates here, we could never
/// represent a 40 arcsec (~0.7px per eye) shift at all.
struct Dot: Equatable, Hashable {
    var x: Double
    var y: Double
    /// Gaussian sigma of the blob, in pixels. Not a hard-edged radius — the
    /// blob has no true edge, it just fades out with distance from center.
    var radius: Double
    /// Horizontal disparity in pixels, split evenly between the two eyes
    /// when rendered. Positive means nearer than the screen ("crossed"
    /// disparity): the left eye's copy shifts right and the right eye's
    /// copy shifts left, so the two copies move toward each other. See
    /// `render(dots:width:height:)` for the geometry this encodes.
    var disparity: Double = 0
    /// Which eyes' images this dot is drawn into. Almost every dot is seen
    /// by both; the exceptions are background dots right beside a target
    /// patch, where the shifted patch covers them in one eye only (see
    /// `generateStereogram`).
    var visibleIn: Eyes = .both
}

/// A set of eyes, used for per-dot visibility.
///
/// An `OptionSet` is Swift's type for a set of independent flags packed
/// into one integer: each static member is one bit, and the type gets set
/// operations (`contains`, `isDisjoint(with:)`, union, ...) for free.
/// `[]` means "neither eye", `.both` means `[.left, .right]`.
struct Eyes: OptionSet, Hashable {
    let rawValue: UInt8

    static let left = Eyes(rawValue: 1 << 0)
    static let right = Eyes(rawValue: 1 << 1)
    static let both: Eyes = [.left, .right]
}
