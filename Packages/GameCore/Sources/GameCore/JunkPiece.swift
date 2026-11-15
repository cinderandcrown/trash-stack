// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Junk tri/pentomino set — cans, boxes, pipes, tubes, tires, bags. Not classic tetromino branding.
public enum JunkID: String, Sendable, CaseIterable, Codable {
    case can, box, pipe, crate, tube, tire, bag, scrap
}

public enum Material: String, Sendable, CaseIterable, Codable {
    case metal, plastic, paper, glass, rubber
}

public struct JunkDef: Sendable, Equatable {
    public let id: JunkID
    public let material: Material
    /// Rotations as lists of (dx, dy) cells relative to pivot.
    public let rotations: [[[Int]]]

    public init(id: JunkID, material: Material, rotations: [[[Int]]]) {
        self.id = id
        self.material = material
        self.rotations = rotations
    }
}

public enum JunkCatalog {
    /// Compact shapes sized for an 8-wide bin.
    public static let all: [JunkDef] = [
        JunkDef(id: .can, material: .metal, rotations: [
            [[0, 0], [0, 1], [0, 2]],
            [[0, 0], [1, 0], [2, 0]],
        ]),
        JunkDef(id: .box, material: .paper, rotations: [
            [[0, 0], [1, 0], [0, 1], [1, 1]],
        ]),
        JunkDef(id: .pipe, material: .metal, rotations: [
            [[0, 0], [1, 0], [2, 0], [1, 1]],
            [[1, 0], [0, 1], [1, 1], [1, 2]],
            [[1, 0], [0, 1], [1, 1], [2, 1]],
            [[0, 0], [0, 1], [1, 1], [0, 2]],
        ]),
        JunkDef(id: .crate, material: .paper, rotations: [
            [[0, 0], [0, 1], [0, 2], [1, 2]],
            [[0, 0], [1, 0], [2, 0], [0, 1]],
            [[0, 0], [1, 0], [1, 1], [1, 2]],
            [[2, 0], [0, 1], [1, 1], [2, 1]],
        ]),
        JunkDef(id: .tube, material: .plastic, rotations: [
            [[0, 0], [1, 0], [2, 0], [3, 0]],
            [[0, 0], [0, 1], [0, 2], [0, 3]],
        ]),
        JunkDef(id: .tire, material: .rubber, rotations: [
            [[1, 0], [0, 1], [1, 1], [2, 1], [1, 2]],
        ]),
        JunkDef(id: .bag, material: .plastic, rotations: [
            [[0, 0], [0, 1], [1, 1], [0, 2]],
            [[0, 1], [1, 0], [1, 1], [2, 1]],
            [[1, 0], [0, 1], [1, 1], [1, 2]],
            [[0, 0], [1, 0], [2, 0], [1, 1]],
        ]),
        JunkDef(id: .scrap, material: .glass, rotations: [
            [[0, 0], [1, 0], [1, 1]],
            [[1, 0], [0, 1], [1, 1]],
            [[0, 0], [0, 1], [1, 1]],
            [[0, 0], [1, 0], [0, 1]],
        ]),
    ]

    public static func def(for id: JunkID) -> JunkDef {
        all.first { $0.id == id }!
    }
}
