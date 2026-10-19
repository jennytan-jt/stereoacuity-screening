/// How the dots in a stereogram look: their size and how densely they
/// fill the field. Part of the stimulus definition, so it belongs here
/// rather than in the app, and every screening uses the same one.
public struct DotStyle: Sendable, Equatable {
    /// Gaussian sigma of each blob, in pixels (see `Dot.radius`).
    public let sigma: Double
    /// Nominal coverage: dot count × dot area / field area (see
    /// `generateDots` for why it's nominal rather than measured).
    public let coverage: Double

    public init(sigma: Double, coverage: Double) {
        self.sigma = sigma
        self.coverage = coverage
    }

    /// The style every screening uses.
    ///
    /// Chosen on an iPhone 15 Pro (460 ppi, 40 cm), 2026-10-18, from nine
    /// candidates. The original 2.0 px / 30% averaged 54% linear brightness
    /// and looked washed out: overlapping blobs merge into flat bright areas
    /// with no fine edges, and small disparities couldn't be seen. Finer,
    /// sparser dots did better; 1.0 px / 10% was the only setting visible at
    /// 60" and (faintly) at 40". Denser (15%) and finer (0.75 px) variants
    /// both did worse.
    ///
    /// That's one observer, with practice effects and scratched glasses.
    /// It's a working default, not a validated one: re-check 40" with new
    /// glasses, and confirm against Randot/TNO in validation (plan step 10).
    public static let standard = DotStyle(sigma: 1.0, coverage: 0.10)
}
