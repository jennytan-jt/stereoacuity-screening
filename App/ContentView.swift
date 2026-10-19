import SwiftUI
import StereoCore

/// Step 3 spike: one anaglyph stereogram drawn at native pixel resolution,
/// for checking through the glasses that the bubble is visible, and that it
/// vanishes with either eye covered.
///
/// Tap to step through the ladder (and a zero-disparity catch field), with
/// a fresh dot pattern each time. Dots use `DotStyle.standard`, chosen on
/// this screen (see its documentation). The small label is a development
/// aid only; the real task has no text.
struct ContentView: View {
    /// Physical screen density. 460 ppi is the iPhone 15 Pro; a lookup by
    /// device model replaces this before other phones are supported.
    static let geometry = ViewingGeometry(pixelsPerInch: 460)
    static let ladder: [Double] = [400, 200, 100, 60, 40, 0]
    static let fieldSize = 900  // pixels, square

    @Environment(\.displayScale) private var displayScale
    @State private var step = 0
    @State private var seed: UInt64 = 1
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black

                if let image {
                    Image(decorative: image, scale: displayScale)
                        // One image pixel per screen pixel: no smoothing,
                        // which would blur away the subpixel disparity.
                        .interpolation(.none)
                        .position(pixelAlignedCenter(in: proxy.size))
                }

                Text("\(Int(Self.ladder[step]))″")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.gray)
                    // Clear of the home indicator and the rounded corners;
                    // the view ignores the safe area, so pad by hand.
                    .padding(.bottom, 60)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                step = (step + 1) % Self.ladder.count
                seed += 1
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        // Re-runs whenever the step or seed changes. Rendering happens off
        // the main thread so the UI never stalls while dots are placed.
        .task(id: seed) {
            let disparity = Self.geometry.pixels(forArcsec: Self.ladder[step])
            let seed = seed
            let anaglyph = await Task.detached {
                Self.renderField(seed: seed, disparity: disparity)
            }.value
            image = Self.makeCGImage(anaglyph)
        }
    }

    /// Center position (in points) that puts the image's top-left corner
    /// exactly on a screen pixel. SwiftUI would otherwise happily center it
    /// at a half-pixel, and the system would resample it to get there.
    private func pixelAlignedCenter(in size: CGSize) -> CGPoint {
        let field = Double(Self.fieldSize)
        let originX = ((size.width * displayScale - field) / 2).rounded(.down)
        let originY = ((size.height * displayScale - field) / 2).rounded(.down)
        return CGPoint(
            x: (originX + field / 2) / displayScale,
            y: (originY + field / 2) / displayScale
        )
    }

    nonisolated static func renderField(seed: UInt64, disparity: Double) -> AnaglyphImage {
        let size = Double(fieldSize)
        // About 1.25 degrees radius (a ~2.5 degree bubble) at 40 cm.
        let radius = geometry.pixels(forArcsec: 1.25 * 3600)
        return renderAnaglyph(
            seed: seed, width: fieldSize, height: fieldSize,
            patch: TargetPatch(centerX: size / 2, centerY: size / 2, radius: radius, disparity: disparity)
        )
    }

    /// Wraps the anaglyph's bytes in a CGImage tagged **Display P3**, so the
    /// channel values reach the P3 panel without color conversion (see
    /// `AnaglyphImage` for why sRGB would add crosstalk).
    static func makeCGImage(_ anaglyph: AnaglyphImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3),
              let provider = CGDataProvider(data: Data(anaglyph.rgba) as CFData)
        else { return nil }
        return CGImage(
            width: anaglyph.width,
            height: anaglyph.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: anaglyph.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

#Preview {
    ContentView()
}
