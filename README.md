# Stereo

An iPhone app for screening stereoacuity (fine depth perception) in children, built for school and low-resource vision screenings. The child wears red/cyan anaglyph glasses and looks at random-dot stereograms: fields of dots with a hidden disc that can only be seen when both eyes work together. Results are reported down to 40 arcseconds ("40 or better").

This is a **screening tool, not a diagnostic device**, and it is an in-progress prototype.

## How it works

Each stimulus is a random-dot stereogram drawn as a red/cyan anaglyph:

- **Disparity only.** The disc differs from the background only in its horizontal offset between the two eyes. Brightness, color, outline and dot density are the same inside and outside, so the disc is invisible to one eye. This is what separates a random-dot test from a picture test like the Titmus Fly, which leaks monocular cues.
- **Subpixel disparity.** At 40 cm on a 460 ppi iPhone, one pixel is about 28 arcsec, so the 40″ target is only 1.4 px of total disparity. Dots are Gaussian anti-aliased blobs placed at fractional positions and rendered in linear light, then gamma-encoded, so a 0.7 px shift per eye is really drawn as 0.7 px.
- **No edge cues.** Shifting a patch of dots leaves a thin gap on one side of the disc and an overlap on the other. The generator fills these crescents with dots that are visible to one eye only (the way real occluding edges look), and enforces minimum dot spacing separately for each eye. That way dot density at the disc's edge looks the same as everywhere else.
- **Clean channel separation.** The left eye's view goes in the red channel and the right eye's in green and blue. The image is tagged Display P3 so iOS doesn't color-convert it, which would leak one eye's view into the other's channels.
- **Deterministic.** Every field comes from a seeded random number generator, so any stimulus can be reproduced exactly.

## Project layout

```
StereoCore/   Swift package: stimulus engine, no UI or ARKit imports
  Sources/      dot generation, rendering, anaglyph composition, viewing geometry
  Tests/        Swift Testing suite
App/          SwiftUI app target
project.yml   XcodeGen spec (Stereo.xcodeproj is generated from it)
```

| File | Role |
|---|---|
| `Stereogram.swift` | Target patch and full stereogram generation, including the edge-crescent fill |
| `DotGeneration.swift` | Random dot placement with minimum spacing |
| `SpacingGrid.swift` | Spatial hash that makes spacing checks roughly O(n) instead of O(n²) |
| `DotField.swift` | Renders dots into a linear-light buffer for each eye |
| `Anaglyph.swift` | Combines the two eyes into an 8-bit Display P3 image; the public entry point |
| `ViewingGeometry.swift` | Arcseconds ↔ pixels from screen density and viewing distance |
| `DotStyle.swift` | Dot size and coverage, tuned on the device |

## Testing

`StereoCore` has 50 tests. They include:

- **Disparity accuracy.** The rendered offset is measured by image registration and compared with the intended one at every disparity from 400″ down to 40″. At the screening dot style, each dot's rendered centroid is measured by drawing the field with and without that dot. The mean error is under 0.002 px, against a requirement of 0.05 px.
- **Edge-cue checks.** For each eye, dot density in rings around the disc boundary is compared with the background, pooled over many seeds.
- **Control tests.** Each check is also run against something it should catch: a naive generator that leaves real gaps, or a deliberate 0.1 px error. This shows the checks can actually fail.
- **Equivalence.** The spatial-grid generator is checked against a brute-force reference and must produce identical output.
- **Encoding.** The 8-bit quantization shifts the disparity by at most 0.0002 px.

Run the tests:

```sh
cd StereoCore
swift test
```

## Building the app

Requires an Xcode with Swift 6.3 or later (developed on Xcode 27) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). It targets iOS 18 on iPhone.

```sh
xcodegen generate
open Stereo.xcodeproj
```

Before running on your own device, set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to your own values and regenerate. The scheme runs in Release because unoptimized dot generation is too slow for a smooth tap-through.

The current app is a test screen. It shows one stereogram at native pixel resolution, and each tap moves to the next disparity in the ladder (400, 200, 100, 60, 40, 0″) with a new dot pattern. The screen density is hard-coded for the iPhone 15 Pro (460 ppi).

## Status

Done:
- The stimulus engine and its accuracy tests.
- Red/cyan rendering verified on an iPhone 15 Pro. The disc vanishes with either eye covered, with no visible ghosting.
- Dot size and density tuned through the glasses.

Planned:
- Measuring viewing distance with ARKit face tracking (distance only; no camera images are stored).
- A four-choice "bubble pop" trial for kids.
- The disparity ladder with catch trials and stop rules, checked against simulated observers.
- A distance-gated pause and resume.
- Local results storage and CSV export.
- Validation against Randot or TNO, and test-retest repeatability.

The dot style was chosen by a single observer and has not been clinically validated.

## Development

Built with [Claude Code](https://claude.com/claude-code) as a pair-programming partner while learning Swift. I wrote the specification and design constraints, reviewed the code, and did all the testing on the device.
