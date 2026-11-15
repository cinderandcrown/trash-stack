// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// 7-bag style RNG over the junk catalog (not a branded tetromino bag).
public struct RNGBag: Sendable {
    private var bag: [JunkID] = []
    private var rng: SeededGenerator

    public init(seed: UInt64 = 0xC1A55) {
        self.rng = SeededGenerator(seed: seed)
        refill()
    }

    public mutating func next() -> JunkID {
        if bag.isEmpty { refill() }
        return bag.removeLast()
    }

    public mutating func peekQueue(_ n: Int) -> [JunkID] {
        var copy = self
        return (0..<n).map { _ in copy.next() }
    }

    private mutating func refill() {
        bag = JunkID.allCases
        for i in stride(from: bag.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            bag.swapAt(i, j)
        }
    }
}

/// Simple xorshift64* for deterministic tests.
public struct SeededGenerator: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    public mutating func unit() -> Double {
        Double(next() % 10_000) / 10_000.0
    }
}
