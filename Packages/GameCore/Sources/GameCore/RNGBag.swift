// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Weighted junk-item bag (fridge rare). Deterministic from seed.
public struct RNGBag: Sendable {
    private var state: UInt64
    private var bag: [JunkID] = []

    public init(seed: UInt64) {
        state = seed == 0 ? 0xC0FFEE : seed
        refill()
    }

    public mutating func next() -> JunkID {
        if bag.isEmpty { refill() }
        return bag.removeLast()
    }

    public mutating func peekQueue(_ n: Int) -> [JunkID] {
        while bag.count < n { refill() }
        return Array(bag.suffix(n).reversed())
    }

    private mutating func refill() {
        var pool: [JunkID] = []
        for def in JunkCatalog.all {
            for _ in 0..<def.weight {
                pool.append(def.id)
            }
        }
        // Fisher–Yates with LCG
        for i in stride(from: pool.count - 1, through: 1, by: -1) {
            state = state &* 636_413_622_384_679_3005 &+ 1
            let j = Int(state % UInt64(i + 1))
            pool.swapAt(i, j)
        }
        bag.append(contentsOf: pool)
    }
}
