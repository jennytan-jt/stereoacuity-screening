/// Scatters dots across a `width` x `height` canvas using rejection sampling:
/// pick a random point, keep it only if it isn't too close to an existing
/// dot, repeat. This is a simple stand-in for a true Poisson-disc sampler —
/// it doesn't guarantee the tightest possible packing, but it gives a
/// deterministic, non-clumpy scatter, which is all a random-dot field needs.
///
/// `coverage` is nominal, not measured: it's `(dot count * dot area) / canvas
/// area`, used only to pick how many dots to place. Because dots are allowed
/// to overlap (their Gaussian tails don't have a hard edge to avoid), the
/// area actually painted is somewhat less than `coverage` suggests, more so
/// as coverage climbs — that's expected, not a bug.
///
/// `coverage * minSpacingFactor²` must not exceed `maxPackingLoad`; see that
/// constant for why.
func generateDots(
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
    var grid = SpacingGrid(spacing: minSpacing)

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

        if grid.hasPoint(near: x, y) { continue }

        dots.append(Dot(x: x, y: y, radius: dotRadius))
        grid.insert(x: x, y: y)
    }

    return dots
}

/// The densest request `generateDots` accepts, measured as
/// `coverage * minSpacingFactor²`.
///
/// Canvas size doesn't matter here: the target dot count scales with canvas
/// area, so a small canvas just asks for fewer dots. What matters is how
/// much of the canvas the dots' exclusion zones (circles of diameter
/// `radius * minSpacingFactor` around each center) try to claim. Random
/// sequential placement jams once those zones cover ~55% of the area, which
/// works out to `coverage * factor²` ≈ 2.2. Empirically the generator fills
/// its target every time up to 2.0 and starts falling short around 2.25, so
/// 2.0 is the limit. The defaults (coverage ≤ 1, factor 1.2) peak at 1.44.
let maxPackingLoad = 2.0
