// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// One hand-tuned puzzle level (Shift mode).
public struct LevelDef: Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var district: String
    public var moveLimit: Int
    /// Moves remaining ≥ this → 3 stars.
    public var starThreeMoves: Int
    /// Moves remaining ≥ this → 2 stars (else 1 if goal met).
    public var starTwoMoves: Int
    public var goal: OrderTicket
    /// Pre-placed cells (absolute board y). Empty boards are not allowed.
    public var board: [(x: Int, y: Int, cell: Cell)]
    /// Opening tray (exactly 3). Dealt again when empty.
    public var tray: [JunkID]
    public var teachHint: String?

    public init(
        id: Int,
        title: String,
        district: String,
        moveLimit: Int,
        starMoves: (Int, Int),
        goal: OrderTicket,
        board: [(Int, Int, Cell)],
        tray: [JunkID],
        teachHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.district = district
        self.moveLimit = moveLimit
        self.starThreeMoves = starMoves.0
        self.starTwoMoves = starMoves.1
        self.goal = goal
        self.board = board.map { (x: $0.0, y: $0.1, cell: $0.2) }
        self.tray = tray
        self.teachHint = teachHint
    }
}

/// 20 hand-tuned levels with an easy ramp. Level 1 teaches drag-and-place.
public enum LevelCatalog {
    public static let count = 20

    public static func level(id: Int) -> LevelDef {
        let clamped = max(1, min(count, id))
        return all[clamped - 1]
    }

    public static let all: [LevelDef] = makeLevels()

    private static func makeLevels() -> [LevelDef] {
        let f = BoardConfig.dumpster.rows - 1
        func metal(_ x: Int, _ y: Int) -> (Int, Int, Cell) { (x, y, Cell(piece: .can, material: .metal)) }
        func plastic(_ x: Int, _ y: Int) -> (Int, Int, Cell) { (x, y, Cell(piece: .tire, material: .plastic)) }
        func glass(_ x: Int, _ y: Int) -> (Int, Int, Cell) { (x, y, Cell(piece: .bottle, material: .glass)) }
        func paper(_ x: Int, _ y: Int) -> (Int, Int, Cell) { (x, y, Cell(piece: .plank, material: .paper)) }
        func stickyMetal(_ x: Int, _ y: Int) -> (Int, Int, Cell) {
            (x, y, Cell(piece: .can, material: .metal, sticky: true))
        }

        return [
            LevelDef(
                id: 1, title: "First Sort", district: "Alley Mouth",
                moveLimit: 8, starMoves: (6, 3),
                goal: OrderTicket(id: "l1", label: "Recycle 4 metal", kind: .recycleMaterial, target: 4, material: .metal),
                board: [metal(2, f), metal(3, f), metal(4, f), paper(6, f)],
                tray: [.can, .plank, .bottle],
                teachHint: "Drag the can next to the three metal tiles"
            ),
            LevelDef(
                id: 2, title: "Pink Pile", district: "Alley Mouth",
                moveLimit: 10, starMoves: (7, 4),
                goal: OrderTicket(id: "l2", label: "Recycle 4 plastic", kind: .recycleMaterial, target: 4, material: .plastic),
                board: [plastic(1, f), plastic(2, f), plastic(3, f), metal(5, f), metal(6, f)],
                tray: [.tire, .can, .plank]
            ),
            LevelDef(
                id: 3, title: "Glass Lane", district: "Alley Mouth",
                moveLimit: 10, starMoves: (7, 4),
                goal: OrderTicket(id: "l3", label: "Recycle 4 glass", kind: .recycleMaterial, target: 4, material: .glass),
                board: [glass(0, f), glass(1, f), glass(2, f), paper(4, f), paper(5, f), metal(7, f)],
                tray: [.bottle, .can, .plank]
            ),
            LevelDef(
                id: 4, title: "Cardboard Corner", district: "Alley Mouth",
                moveLimit: 12, starMoves: (8, 4),
                goal: OrderTicket(id: "l4", label: "Recycle 4 paper", kind: .recycleMaterial, target: 4, material: .paper),
                board: [paper(3, f), paper(4, f), paper(5, f), metal(0, f), plastic(7, f), glass(1, f)],
                tray: [.crate, .can, .tire]
            ),
            LevelDef(
                id: 5, title: "Mixed Bin", district: "Alley Mouth",
                moveLimit: 12, starMoves: (8, 4),
                goal: OrderTicket(id: "l5", label: "Recycle any 8 tiles", kind: .recycleAny, target: 8),
                board: [
                    metal(0, f), metal(1, f), metal(2, f),
                    plastic(4, f), plastic(5, f),
                    glass(6, f), paper(7, f),
                    metal(0, f - 1), plastic(4, f - 1),
                ],
                tray: [.can, .tire, .bottle]
            ),
            LevelDef(
                id: 6, title: "Two Waves", district: "Battery Yard",
                moveLimit: 14, starMoves: (9, 5),
                goal: OrderTicket(id: "l6", label: "Make a chain", kind: .recycleChain, target: 2),
                board: [
                    metal(1, f), metal(2, f), metal(3, f),
                    plastic(1, f - 1), plastic(2, f - 1), plastic(3, f - 1),
                    paper(5, f), paper(6, f), glass(7, f),
                ],
                tray: [.can, .tire, .plank]
            ),
            LevelDef(
                id: 7, title: "Tight Fit", district: "Battery Yard",
                moveLimit: 14, starMoves: (9, 5),
                goal: OrderTicket(id: "l7", label: "Recycle 12 plastic", kind: .recycleMaterial, target: 12, material: .plastic),
                board: [
                    plastic(0, f), plastic(1, f), plastic(2, f),
                    plastic(0, f - 1), plastic(1, f - 1),
                    metal(4, f), metal(5, f), metal(6, f), metal(7, f),
                    paper(3, f), glass(3, f - 1),
                ],
                tray: [.tire, .pipe, .can]
            ),
            LevelDef(
                id: 8, title: "Metal Heap", district: "Battery Yard",
                moveLimit: 14, starMoves: (8, 4),
                goal: OrderTicket(id: "l8", label: "Recycle 12 metal", kind: .recycleMaterial, target: 12, material: .metal),
                board: [
                    metal(2, f), metal(3, f), metal(4, f), metal(5, f),
                    metal(2, f - 1), metal(3, f - 1), metal(4, f - 1),
                    plastic(0, f), paper(7, f), glass(0, f - 1),
                ],
                tray: [.can, .bentPipe, .plank]
            ),
            LevelDef(
                id: 9, title: "Glass Shelf", district: "Battery Yard",
                moveLimit: 15, starMoves: (9, 5),
                goal: OrderTicket(id: "l9", label: "Recycle 8 glass", kind: .recycleMaterial, target: 8, material: .glass),
                board: [
                    glass(1, f), glass(2, f), glass(3, f),
                    glass(1, f - 1), glass(2, f - 1),
                    metal(5, f), metal(6, f), plastic(7, f), paper(0, f),
                ],
                tray: [.bottle, .can, .tire]
            ),
            LevelDef(
                id: 10, title: "Half Shift", district: "Magnet Row",
                moveLimit: 16, starMoves: (10, 5),
                goal: OrderTicket(id: "l10", label: "Recycle any 16 tiles", kind: .recycleAny, target: 16),
                board: [
                    metal(0, f), metal(1, f), metal(2, f),
                    plastic(3, f), plastic(4, f), plastic(5, f),
                    glass(6, f), glass(7, f),
                    paper(0, f - 1), paper(1, f - 1),
                    metal(3, f - 1), plastic(6, f - 1),
                ],
                tray: [.can, .tire, .bottle]
            ),
            LevelDef(
                id: 11, title: "Crowded Lip", district: "Magnet Row",
                moveLimit: 16, starMoves: (9, 5),
                goal: OrderTicket(id: "l11", label: "Recycle 12 paper", kind: .recycleMaterial, target: 12, material: .paper),
                board: [
                    paper(0, f), paper(1, f), paper(2, f), paper(3, f),
                    paper(0, f - 1), paper(1, f - 1), paper(2, f - 1),
                    metal(5, f), plastic(6, f), glass(7, f),
                    metal(5, f - 1), plastic(6, f - 1),
                ],
                tray: [.crate, .plank, .can]
            ),
            LevelDef(
                id: 12, title: "Chain Practice", district: "Magnet Row",
                moveLimit: 16, starMoves: (9, 5),
                goal: OrderTicket(id: "l12", label: "Make a chain", kind: .recycleChain, target: 2),
                board: [
                    metal(0, f), metal(1, f), metal(2, f),
                    plastic(0, f - 1), plastic(1, f - 1), plastic(2, f - 1),
                    glass(4, f), glass(5, f), glass(6, f),
                    paper(4, f - 1), paper(5, f - 1),
                ],
                tray: [.can, .tire, .bottle]
            ),
            LevelDef(
                id: 13, title: "Four Lanes", district: "Magnet Row",
                moveLimit: 18, starMoves: (10, 6),
                goal: OrderTicket(id: "l13", label: "Recycle any 20 tiles", kind: .recycleAny, target: 20),
                board: [
                    metal(0, f), metal(1, f), metal(0, f - 1),
                    plastic(2, f), plastic(3, f), plastic(2, f - 1),
                    glass(4, f), glass(5, f), glass(4, f - 1),
                    paper(6, f), paper(7, f), paper(6, f - 1),
                    metal(1, f - 2), plastic(3, f - 2),
                ],
                tray: [.can, .tire, .plank]
            ),
            LevelDef(
                id: 14, title: "L-Metal Night", district: "Conveyor Docks",
                moveLimit: 18, starMoves: (10, 5),
                goal: OrderTicket(id: "l14", label: "Recycle 16 metal", kind: .recycleMaterial, target: 16, material: .metal),
                board: [
                    metal(1, f), metal(2, f), metal(3, f), metal(4, f),
                    metal(1, f - 1), metal(2, f - 1), metal(3, f - 1),
                    metal(1, f - 2), metal(2, f - 2),
                    plastic(6, f), paper(7, f), glass(0, f),
                ],
                tray: [.bentPipe, .can, .fridge]
            ),
            LevelDef(
                id: 15, title: "Sticky Lesson", district: "Conveyor Docks",
                moveLimit: 18, starMoves: (9, 5),
                goal: OrderTicket(id: "l15", label: "Recycle 12 plastic", kind: .recycleMaterial, target: 12, material: .plastic),
                board: [
                    plastic(2, f), plastic(3, f), plastic(4, f),
                    plastic(2, f - 1), plastic(3, f - 1),
                    stickyMetal(5, f), paper(6, f), glass(0, f),
                ],
                tray: [.tire, .pipe, .can]
            ),
            LevelDef(
                id: 16, title: "Dock Crush", district: "Conveyor Docks",
                moveLimit: 18, starMoves: (9, 5),
                goal: OrderTicket(id: "l16", label: "Slam the press", kind: .pressSlam, target: 1),
                board: [
                    metal(0, f), metal(1, f), metal(2, f), metal(3, f),
                    plastic(4, f), plastic(5, f), plastic(6, f),
                    glass(7, f), paper(0, f - 1), metal(1, f - 1),
                ],
                tray: [.can, .tire, .plank]
            ),
            LevelDef(
                id: 17, title: "Deep Stack", district: "Conveyor Docks",
                moveLimit: 20, starMoves: (11, 6),
                goal: OrderTicket(id: "l17", label: "Recycle any 24 tiles", kind: .recycleAny, target: 24),
                board: [
                    metal(0, f), metal(1, f), metal(2, f), metal(0, f - 1), metal(1, f - 1),
                    plastic(3, f), plastic(4, f), plastic(3, f - 1), plastic(4, f - 1),
                    glass(5, f), glass(6, f), glass(5, f - 1),
                    paper(7, f), paper(7, f - 1), paper(6, f - 1),
                    metal(2, f - 2), plastic(3, f - 2),
                ],
                tray: [.can, .tire, .bottle]
            ),
            LevelDef(
                id: 18, title: "Forced Path", district: "Neon Crown",
                moveLimit: 16, starMoves: (8, 4),
                goal: OrderTicket(id: "l18", label: "Recycle 4 metal", kind: .recycleMaterial, target: 4, material: .metal),
                board: [
                    metal(3, f), metal(4, f), metal(5, f),
                    plastic(0, f), plastic(1, f), plastic(2, f),
                    glass(6, f), glass(7, f),
                    paper(0, f - 1), paper(7, f - 1),
                ],
                tray: [.can, .fridge, .plank]
            ),
            LevelDef(
                id: 19, title: "Crown Chain", district: "Neon Crown",
                moveLimit: 20, starMoves: (10, 5),
                goal: OrderTicket(id: "l19", label: "Make a chain", kind: .recycleChain, target: 2),
                board: [
                    metal(1, f), metal(2, f), metal(3, f),
                    plastic(1, f - 1), plastic(2, f - 1), plastic(3, f - 1),
                    glass(1, f - 2), glass(2, f - 2),
                    paper(5, f), paper(6, f), paper(5, f - 1),
                    metal(7, f), plastic(0, f),
                ],
                tray: [.can, .tire, .bottle]
            ),
            LevelDef(
                id: 20, title: "Night Cap", district: "Neon Crown",
                moveLimit: 22, starMoves: (12, 6),
                goal: OrderTicket(id: "l20", label: "Recycle any 30 tiles", kind: .recycleAny, target: 30),
                board: [
                    metal(0, f), metal(1, f), metal(2, f), metal(0, f - 1), metal(1, f - 1), metal(0, f - 2),
                    plastic(3, f), plastic(4, f), plastic(3, f - 1), plastic(4, f - 1), plastic(3, f - 2),
                    glass(5, f), glass(6, f), glass(5, f - 1), glass(6, f - 1),
                    paper(7, f), paper(7, f - 1), paper(7, f - 2), paper(6, f - 2),
                ],
                tray: [.can, .tire, .crate]
            ),
        ]
    }
}
