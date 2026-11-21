// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Junk item identities for Recycling Night Shift.
/// Named as real junk — never letter piece codes.
public enum JunkID: String, Sendable, CaseIterable, Codable {
    case can
    case bottle
    case plank
    case pipe
    case crate
    case tire
    case bentPipe
    case fridge
}

public enum Material: String, Sendable, CaseIterable, Codable {
    case metal
    case plastic
    case glass
    case paper
}

public enum HazardKind: String, Sendable, Codable, Equatable {
    /// Converts orthogonally adjacent cells toward metal over time / on lock.
    case leakingBattery
}

public struct JunkDef: Sendable, Equatable {
    public let id: JunkID
    public let material: Material
    /// Atlas / asset key — must read as this def's material (see material look map).
    public let textureName: String
    /// Rotations as lists of (dx, dy) cells relative to pivot.
    public let rotations: [[[Int]]]
    /// Spawn weight; fridge is rare.
    public let weight: Int

    public init(
        id: JunkID,
        material: Material,
        textureName: String,
        rotations: [[[Int]]],
        weight: Int = 10
    ) {
        self.id = id
        self.material = material
        self.textureName = textureName
        self.rotations = rotations
        self.weight = weight
    }

    public var isSquare: Bool {
        rotations.count == 1 && Set(rotations[0].map { $0[0] }).count == Set(rotations[0].map { $0[1] }).count
            && rotations[0].count == 4
            && rotations[0].allSatisfy { ($0[0] == 0 || $0[0] == 1) && ($0[1] == 0 || $0[1] == 1) }
    }
}

public enum JunkCatalog {
    /// Compactor-bin junk items. See docs/DESIGN.md.
    ///
    /// Material look map (one color family + icon family per material):
    /// - metal   → steel blue-gray plate · `can` icon
    /// - plastic → magenta-pink plate · `pipe` / `tire` icons (pink bottle + dark tire)
    /// - glass   → cyan plate · `glass` icon
    /// - paper   → kraft orange/tan plate · `plank` / `crate` icons
    ///
    /// Pink bottle art is plastic (never metal). Banana/cardboard silhouettes are not used
    /// for metal — metal bars/appliances share the steel `can` icon so they read as metal.
    public static let all: [JunkDef] = [
        JunkDef(id: .can, material: .metal, textureName: "can", rotations: [
            [[0, 0]],
        ], weight: 14),
        JunkDef(id: .bottle, material: .glass, textureName: "glass", rotations: [
            [[0, 0], [0, 1]],
            [[0, 0], [1, 0]],
        ], weight: 12),
        JunkDef(id: .plank, material: .paper, textureName: "plank", rotations: [
            [[0, 0], [1, 0], [2, 0]],
            [[0, 0], [0, 1], [0, 2]],
        ], weight: 10),
        // Pink bottle bar — plastic (art is plastic; never metal).
        JunkDef(id: .pipe, material: .plastic, textureName: "pipe", rotations: [
            [[0, 0], [1, 0], [2, 0]],
            [[0, 0], [0, 1], [0, 2]],
        ], weight: 10),
        JunkDef(id: .crate, material: .paper, textureName: "crate", rotations: [
            [[0, 0], [1, 0], [0, 1], [1, 1]],
        ], weight: 9),
        JunkDef(id: .tire, material: .plastic, textureName: "tire", rotations: [
            [[0, 0], [1, 0], [0, 1], [1, 1]],
        ], weight: 9),
        // L-metal — steel can icon (banana art misread as paper).
        JunkDef(id: .bentPipe, material: .metal, textureName: "can", rotations: [
            [[0, 0], [0, 1], [1, 1]],
            [[0, 1], [1, 0], [1, 1]],
            [[0, 0], [1, 0], [1, 1]],
            [[0, 0], [1, 0], [0, 1]],
        ], weight: 10),
        // Bulky metal — steel can icon (cardboard art misread as paper).
        JunkDef(id: .fridge, material: .metal, textureName: "can", rotations: [
            [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2], [1, 2]],
            [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]],
        ], weight: 3),
    ]

    public static func def(for id: JunkID) -> JunkDef {
        all.first { $0.id == id }!
    }

    public static func textureName(for id: JunkID) -> String {
        def(for: id).textureName
    }
}
