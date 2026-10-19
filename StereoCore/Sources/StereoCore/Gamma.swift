import Foundation

/// sRGB gamma transfer functions.
///
/// A display's pixel values are gamma-encoded (roughly value^(1/2.2)) for
/// historical/perceptual reasons, but light itself adds up linearly. If you
/// anti-alias a dot by blending gamma-encoded values directly — e.g. pixel =
/// 0.5 * dotValue + 0.5 * backgroundValue — the result is *too dark*, and
/// worse for us, the blob's brightness-weighted centroid shifts away from
/// its true subpixel center. That would corrupt the very disparity we're
/// trying to present. So every blend in the renderer happens in linear
/// light: decode to linear, accumulate, re-encode once at the very end (and
/// for this package, we don't even re-encode — see `render` in DotField.swift,
/// which leaves the buffer in linear space for the app target to handle).
enum Gamma {
    /// Decodes a gamma-encoded sRGB channel value (0...1) to linear light.
    static func toLinear(_ value: Double) -> Double {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    /// Encodes a linear light value (0...1) to gamma-encoded sRGB.
    static func toSRGB(_ value: Double) -> Double {
        if value <= 0.0031308 {
            return value * 12.92
        }
        return 1.055 * pow(value, 1.0 / 2.4) - 0.055
    }
}
