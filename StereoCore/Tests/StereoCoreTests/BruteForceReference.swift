import Foundation
@testable import StereoCore

// The dot generators as they were before `SpacingGrid`: every candidate is
// checked against every placed dot. Kept here, unchanged apart from the
// names, as the reference the grid versions must match exactly. Slow, but
// obviously correct, which is the point of a reference.

func bruteForceGenerateDots(
    seed: UInt64,
    width: Int,
    height: Int,
    dotRadius: Double,
    coverage: Double,
    minSpacingFactor: Double = 1.2
) -> [Dot] {
    precondition(width > 0 && height > 0, "canvas must be non-empty")
    precondition(coverage > 0 && coverage <= 1, "coverage must be in (0, 1]")
    precondition(
        coverage * minSpacingFactor * minSpacingFactor <= maxPackingLoad,
        "coverage \(coverage) with spacing factor \(minSpacingFactor) packs too densely for rejection sampling to fill"
    )

    var rng = SeededGenerator(seed: seed)

    let canvasArea = Double(width) * Double(height)
    let dotArea = Double.pi * dotRadius * dotRadius
    let targetCount = max(1, Int((coverage * canvasArea / dotArea).rounded()))

    let minSpacing = dotRadius * minSpacingFactor
    let minSpacingSquared = minSpacing * minSpacing

    var dots: [Dot] = []
    dots.reserveCapacity(targetCount)

    // The precondition above keeps requests below the point where random
    // placement jams, so in practice the target is always reached. The cap
    // is a backstop: if an unlucky sequence ever does stall, return fewer
    // dots than requested rather than spinning forever.
    let maxAttempts = targetCount * 50
    var attempts = 0
    while dots.count < targetCount && attempts < maxAttempts {
        attempts += 1
        let x = Double.random(in: 0..<Double(width), using: &rng)
        let y = Double.random(in: 0..<Double(height), using: &rng)

        let tooClose = dots.contains { existing in
            let dx = existing.x - x
            let dy = existing.y - y
            return dx * dx + dy * dy < minSpacingSquared
        }
        if tooClose { continue }

        dots.append(Dot(x: x, y: y, radius: dotRadius))
    }

    return dots
}

func bruteForceGenerateStereogram(
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
    let minSpacingSquared = minSpacing * minSpacing

    func tooClose(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
        let dx = ax - bx
        let dy = ay - by
        return dx * dx + dy * dy < minSpacingSquared
    }

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

        if patchDots.contains(where: { tooClose($0.x, $0.y, x, y) }) { continue }
        patchDots.append(Dot(x: x, y: y, radius: dotRadius, disparity: patch.disparity))
    }

    // Background dots. Candidates are sampled over the whole canvas, but a
    // point inside *both* eyes' discs is never visible and is discarded,
    // so the dot count is sized to the area visible to at least one eye.
    // Sizing it to the full canvas would thin out the background relative
    // to the patch: a density difference either eye could see.
    let visibleArea = Double(width * height)
        - bruteForceOverlapArea(radius: patch.radius, centerDistance: abs(patch.disparity))
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

        let crowdsPatch = [Eyes.left, .right].contains { eye in
            guard visibleIn.contains(eye) else { return false }
            let shift = patch.offset(in: eye)
            return patchDots.contains { tooClose($0.x + shift, $0.y, x, y) }
        }
        if crowdsPatch { continue }

        // Two background dots only need spacing if some eye sees both.
        let crowdsBackground = backgroundDots.contains { existing in
            !existing.visibleIn.isDisjoint(with: visibleIn) && tooClose(existing.x, existing.y, x, y)
        }
        if crowdsBackground { continue }

        backgroundDots.append(Dot(x: x, y: y, radius: dotRadius, visibleIn: visibleIn))
    }

    return patchDots + backgroundDots
}

private func bruteForceOverlapArea(radius: Double, centerDistance d: Double) -> Double {
    if d >= 2 * radius { return 0 }
    return 2 * radius * radius * acos(d / (2 * radius))
        - (d / 2) * (4 * radius * radius - d * d).squareRoot()
}
