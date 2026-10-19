import Foundation

/// The disparity-defined target in a random-dot stereogram: a disc of dots
/// that, once the eyes fuse, floats in front of (or behind) the
/// zero-disparity background.
///
/// Coordinates are *cyclopean*, the position the fused percept is seen at.
/// Each eye's image of the patch is the same disc shifted horizontally by
/// half the disparity: right for the left eye, left for the right eye,
/// matching how `render` places a dot's two copies.
public struct TargetPatch: Sendable {
    public var centerX: Double
    public var centerY: Double
    public var radius: Double
    /// Total disparity in pixels, positive = nearer than the screen. Zero
    /// gives a patch that is present but invisible, which is what catch
    /// trials and non-target fields use (see `generateStereogram`).
    public var disparity: Double

    // Swift's automatic memberwise initializer is only ever `internal`, even
    // on a public struct, so code outside the package needs this spelled out.
    public init(centerX: Double, centerY: Double, radius: Double, disparity: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.disparity = disparity
    }

    /// Horizontal offset of this patch in one eye's image relative to its
    /// cyclopean position.
    func offset(in eye: Eyes) -> Double {
        switch eye {
        case .left: disparity / 2
        case .right: -disparity / 2
        default: preconditionFailure("offset is per single eye, got \(eye)")
        }
    }

    /// Whether a point lies inside the patch as one eye sees it.
    func contains(x: Double, y: Double, in eye: Eyes) -> Bool {
        let dx = x - (centerX + offset(in: eye))
        let dy = y - centerY
        return dx * dx + dy * dy < radius * radius
    }
}

/// Generates a random-dot stereogram containing one `TargetPatch`, such
/// that each eye's image *on its own* is an ordinary uniform random-dot
/// field: same dot density and spacing everywhere, with nothing marking
/// where the patch is. Only comparing the two eyes reveals it.
///
/// The naive approach (scatter dots, give the ones inside the disc a
/// disparity) fails that test: shifting the disc's dots opens a gap on
/// one side of it and piles them onto the background on the other,
/// visible to either eye alone as a crescent. Instead:
///
/// 1. **Patch dots** are scattered inside the disc and given the patch's
///    disparity, so each eye sees them inside its own shifted copy of the
///    disc.
/// 2. **Background dots** (zero disparity) are drawn only into the eyes
///    where the shifted disc doesn't cover them. Near the disc's left and
///    right edges that leaves thin crescents of background visible to one
///    eye only. Those are the fresh random dots that fill the gap, and they
///    match real depth edges, where the background is half-hidden.
/// 3. Every spacing check is done **per eye**: a background dot must keep
///    `minSpacing` from patch dots *where that eye sees them*, and from
///    other background dots the same eye sees. So spacing statistics don't
///    change across the disc's edge either.
///
/// Target and non-target fields (and catch trials) should all come from
/// this function, the latter with `disparity: 0`, so they share one
/// generation path and differ in nothing but disparity.
func generateStereogram(
    seed: UInt64,
    width: Int,
    height: Int,
    dotRadius: Double,
    coverage: Double,
    patch: TargetPatch,
    minSpacingFactor: Double = 1.2
) -> [Dot] {
    precondition(width > 0 && height > 0, "canvas must be non-empty")
    precondition(coverage > 0 && coverage <= 1, "coverage must be in (0, 1]")
    precondition(
        coverage * minSpacingFactor * minSpacingFactor <= maxPackingLoad,
        "coverage \(coverage) with spacing factor \(minSpacingFactor) packs too densely for rejection sampling to fill"
    )
    precondition(patch.radius > 0, "patch must have a positive radius")
    let halfShift = abs(patch.disparity) / 2
    precondition(
        patch.centerX - patch.radius - halfShift >= 0
            && patch.centerX + patch.radius + halfShift <= Double(width)
            && patch.centerY - patch.radius >= 0
            && patch.centerY + patch.radius <= Double(height),
        "patch (including its disparity shift) must lie fully inside the canvas"
    )

    var rng = SeededGenerator(seed: seed)

    let dotArea = Double.pi * dotRadius * dotRadius
    let minSpacing = dotRadius * minSpacingFactor

    // One grid per eye holds every dot that eye sees, at the position that
    // eye sees it, so "too close in that eye's image" is a single query.
    // A third grid holds patch dots at their cyclopean positions.
    var patchGrid = SpacingGrid(spacing: minSpacing)
    var leftGrid = SpacingGrid(spacing: minSpacing)
    var rightGrid = SpacingGrid(spacing: minSpacing)

    // Patch dots. Every one shifts by the same amount in a given eye, so
    // spacing between two patch dots is the same in both eyes and can be
    // checked once, on cyclopean positions.
    let patchArea = Double.pi * patch.radius * patch.radius
    let patchTarget = Int((coverage * patchArea / dotArea).rounded())
    var patchDots: [Dot] = []
    patchDots.reserveCapacity(patchTarget)

    var attempts = 0
    while patchDots.count < patchTarget && attempts < patchTarget * 50 {
        attempts += 1
        // Uniform over the disc: radius ∝ sqrt(u), because the area of a
        // ring grows with its radius. Plain `R * u` would bunch dots at the
        // center.
        let r = patch.radius * Double.random(in: 0..<1, using: &rng).squareRoot()
        let theta = Double.random(in: 0..<(2 * .pi), using: &rng)
        let x = patch.centerX + r * cos(theta)
        let y = patch.centerY + r * sin(theta)

        if patchGrid.hasPoint(near: x, y) { continue }
        patchDots.append(Dot(x: x, y: y, radius: dotRadius, disparity: patch.disparity))
        patchGrid.insert(x: x, y: y)
        leftGrid.insert(x: x + patch.offset(in: .left), y: y)
        rightGrid.insert(x: x + patch.offset(in: .right), y: y)
    }

    // Background dots. Candidates are sampled over the whole canvas, but a
    // point inside *both* eyes' discs is never visible and is discarded,
    // so the dot count is sized to the area visible to at least one eye.
    // Sizing it to the full canvas would thin out the background relative
    // to the patch: a density difference either eye could see.
    let visibleArea = Double(width * height)
        - overlapArea(radius: patch.radius, centerDistance: abs(patch.disparity))
    let backgroundTarget = Int((coverage * visibleArea / dotArea).rounded())
    var backgroundDots: [Dot] = []
    backgroundDots.reserveCapacity(backgroundTarget)

    attempts = 0
    while backgroundDots.count < backgroundTarget && attempts < backgroundTarget * 50 {
        attempts += 1
        let x = Double.random(in: 0..<Double(width), using: &rng)
        let y = Double.random(in: 0..<Double(height), using: &rng)

        var visibleIn = Eyes.both
        if patch.contains(x: x, y: y, in: .left) { visibleIn.remove(.left) }
        if patch.contains(x: x, y: y, in: .right) { visibleIn.remove(.right) }
        if visibleIn.isEmpty { continue }

        // A background dot only has to keep its distance from dots an eye
        // sees alongside it, which is exactly what each eye's grid holds:
        // patch dots at their shifted positions, plus background dots
        // visible to that eye.
        if visibleIn.contains(.left) && leftGrid.hasPoint(near: x, y) { continue }
        if visibleIn.contains(.right) && rightGrid.hasPoint(near: x, y) { continue }

        backgroundDots.append(Dot(x: x, y: y, radius: dotRadius, visibleIn: visibleIn))
        if visibleIn.contains(.left) { leftGrid.insert(x: x, y: y) }
        if visibleIn.contains(.right) { rightGrid.insert(x: x, y: y) }
    }

    return patchDots + backgroundDots
}

/// Area where two equal circles overlap (a "lens"), given their radius and
/// the distance between their centers. Here: the region covered by the
/// patch in *both* eyes, which no background dot can show through.
private func overlapArea(radius: Double, centerDistance d: Double) -> Double {
    if d >= 2 * radius { return 0 }
    return 2 * radius * radius * acos(d / (2 * radius))
        - (d / 2) * (4 * radius * radius - d * d).squareRoot()
}
