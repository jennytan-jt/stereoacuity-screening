import Foundation

/// A single-channel linear-light pixel buffer: one eye's view of a dot
/// field. Values are *not* gamma-encoded (see `Gamma`) — 0 is empty
/// background, 1.0 is full brightness. Overlapping dots add light rather
/// than replacing it, since that's what happens physically when you
/// combine linear-light intensities; the total is clamped to 1.0 only
/// once, after every dot has been drawn, which is why clamping lives in
/// `render` rather than inside `splat`.
struct DotField {
    let width: Int
    let height: Int
    private(set) var buffer: [Double]

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "canvas must be non-empty")
        self.width = width
        self.height = height
        self.buffer = [Double](repeating: 0, count: width * height)
    }

    /// Linear-light intensity at (x, y), 0...1.
    subscript(x: Int, y: Int) -> Double {
        buffer[y * width + x]
    }

    /// How many sigma out to rasterize a Gaussian blob before its
    /// contribution is treated as negligible. Past 3 sigma a Gaussian is
    /// under 0.1% of its peak — invisible, but skipping it means we only
    /// ever touch a small box of pixels per dot instead of the whole
    /// canvas.
    fileprivate static let gaussianCutoffSigmas = 3.0

    /// Adds one Gaussian blob centered at (centerX, centerY) — subpixel,
    /// not snapped to the grid — into this buffer. Only the bounding box
    /// within `gaussianCutoffSigmas` of the center is touched, clipped to
    /// the canvas; pixels that fall outside the canvas are simply skipped,
    /// which is what gives a dot near the edge its correctly truncated
    /// "bite" instead of wrapping or crashing.
    fileprivate mutating func splat(centerX: Double, centerY: Double, sigma: Double) {
        let reach = sigma * DotField.gaussianCutoffSigmas
        let twoSigmaSquared = 2 * sigma * sigma

        let minX = max(0, Int((centerX - reach).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + reach).rounded(.up)))
        let minY = max(0, Int((centerY - reach).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + reach).rounded(.up)))

        guard minX <= maxX, minY <= maxY else { return }

        for py in minY...maxY {
            for px in minX...maxX {
                let dx = Double(px) - centerX
                let dy = Double(py) - centerY
                let distanceSquared = dx * dx + dy * dy
                buffer[py * width + px] += exp(-distanceSquared / twoSigmaSquared)
            }
        }
    }

    fileprivate mutating func clampToDisplayRange() {
        for i in buffer.indices {
            buffer[i] = min(1.0, buffer[i])
        }
    }
}

/// Renders a dot field into a pair of linear-light buffers, one per eye,
/// applying each dot's disparity as a horizontal offset between them.
///
/// Positive `disparity` means the dot appears nearer than the screen: the
/// left eye's copy is drawn at `x + disparity / 2` and the right eye's
/// copy at `x - disparity / 2`, so the two copies move toward each other
/// ("crossed" disparity — tracing each eye's line of sight to a point
/// nearer than the screen, the lines cross before they reach it, which is
/// exactly the geometry this offset reproduces). Negative disparity pushes
/// the dot behind the screen instead, with the copies moving apart.
///
/// A dot is only drawn into the eyes listed in its `visibleIn`.
func render(dots: [Dot], width: Int, height: Int) -> (left: DotField, right: DotField) {
    var left = DotField(width: width, height: height)
    var right = DotField(width: width, height: height)

    for dot in dots {
        if dot.visibleIn.contains(.left) {
            left.splat(centerX: dot.x + dot.disparity / 2, centerY: dot.y, sigma: dot.radius)
        }
        if dot.visibleIn.contains(.right) {
            right.splat(centerX: dot.x - dot.disparity / 2, centerY: dot.y, sigma: dot.radius)
        }
    }

    left.clampToDisplayRange()
    right.clampToDisplayRange()

    return (left, right)
}
