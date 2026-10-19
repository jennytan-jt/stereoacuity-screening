// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A deterministic pseudo-random number generator (splitmix64).
///
/// Unlike `SystemRandomNumberGenerator`, this is fully reproducible: the
/// same seed always produces the same sequence. That reproducibility is
/// what lets us verify disparity accuracy against a known dot field, and
/// (later) regenerate a specific trial's stimulus deterministically.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
