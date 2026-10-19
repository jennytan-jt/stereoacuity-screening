/// A red/cyan anaglyph ready for display: the left eye's view in the red
/// channel, the right eye's in green and blue, so red/cyan glasses route
/// each view to its own eye.
///
/// Pixels are 8-bit RGBA, row-major, with no row padding, and gamma-encoded
/// for **Display P3**. The app must tag the image with the Display P3 color
/// space. iPhone panels are P3, so a P3-tagged image reaches the panel
/// unconverted, but an sRGB-tagged one gets converted, and pure sRGB red
/// becomes a P3 color with some green and blue in it: the left eye's view
/// leaking into the right eye's channels, before the glasses even start.
public struct AnaglyphImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
}

/// Combines one eye's linear-light buffer per channel into an anaglyph.
///
/// The buffers are encoded with the sRGB transfer curve. That's correct for
/// Display P3 too: P3 has different primaries (which colors "full red" and
/// "full green" are) but uses exactly the same gamma curve as sRGB.
func composeAnaglyph(left: DotField, right: DotField) -> AnaglyphImage {
    precondition(left.width == right.width && left.height == right.height, "eyes must be the same size")

    let pixelCount = left.width * left.height
    var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
    for i in 0..<pixelCount {
        let leftValue = encode(left.buffer[i])
        let rightValue = encode(right.buffer[i])
        rgba[4 * i] = leftValue
        rgba[4 * i + 1] = rightValue
        rgba[4 * i + 2] = rightValue
        rgba[4 * i + 3] = 255
    }
    return AnaglyphImage(width: left.width, height: left.height, rgba: rgba)
}

/// Linear light (0...1) to an 8-bit gamma-encoded channel value.
func encode(_ linear: Double) -> UInt8 {
    UInt8((Gamma.toSRGB(linear) * 255).rounded())
}

/// The whole pipeline, which is all the app needs: generate a stereogram,
/// render each eye, and combine them into an anaglyph.
///
/// This is StereoCore's public surface for drawing a stimulus. The steps
/// underneath (`generateStereogram`, `render`, `DotField`, `Dot`) stay
/// `internal`, so the app can't bypass the generator's guarantees, for
/// example by building a dot field with no patch handling at all.
public func renderAnaglyph(
    seed: UInt64,
    width: Int,
    height: Int,
    patch: TargetPatch,
    style: DotStyle = .standard
) -> AnaglyphImage {
    let dots = generateStereogram(
        seed: seed, width: width, height: height,
        dotRadius: style.sigma, coverage: style.coverage, patch: patch
    )
    let (left, right) = render(dots: dots, width: width, height: height)
    return composeAnaglyph(left: left, right: right)
}
