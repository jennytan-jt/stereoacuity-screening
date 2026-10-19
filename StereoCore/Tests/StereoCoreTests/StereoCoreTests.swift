import Testing
@testable import StereoCore

@Suite("SeededGenerator")
struct SeededGeneratorTests {

    @Test("same seed produces the same sequence")
    func determinism() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        let sequenceA = (0..<10).map { _ in a.next() }
        let sequenceB = (0..<10).map { _ in b.next() }
        #expect(sequenceA == sequenceB)
    }

    @Test("different seeds produce different sequences")
    func seedSensitivity() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        let sequenceA = (0..<10).map { _ in a.next() }
        let sequenceB = (0..<10).map { _ in b.next() }
        #expect(sequenceA != sequenceB)
    }

    @Test(
        "matches an independently computed reference sequence",
        arguments: [
            (seed: UInt64(0), expected: [
                UInt64(16294208416658607535), 7960286522194355700, 487617019471545679,
                17909611376780542444, 1961750202426094747,
            ]),
            (seed: UInt64(42), expected: [
                UInt64(13679457532755275413), 2949826092126892291, 5139283748462763858,
                6349198060258255764, 701532786141963250,
            ]),
            (seed: UInt64(1), expected: [
                UInt64(10451216379200822465), 13757245211066428519, 17911839290282890590,
                8196980753821780235, 8195237237126968761,
            ]),
        ]
    )
    func matchesReferenceImplementation(seed: UInt64, expected: [UInt64]) {
        var generator = SeededGenerator(seed: seed)
        let produced = (0..<expected.count).map { _ in generator.next() }
        #expect(produced == expected)
    }

    @Test("does not repeatedly emit the same value")
    func notDegenerate() {
        var generator = SeededGenerator(seed: 7)
        let values = Set((0..<1000).map { _ in generator.next() })
        #expect(values.count == 1000)
    }
}
