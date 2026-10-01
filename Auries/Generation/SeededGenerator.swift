import Foundation

/// SplitMix64. Extracted from `AurieGenerator` 2026-09-21 so model files
/// that merely mention the type (e.g. `PatternType.roll`) can be compiled
/// by the offline harness without dragging in the whole content layer.
/// Behaviour is byte-identical to the previous inline definition — every
/// persisted Aurie's traits depend on this sequence, so it must never change.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
