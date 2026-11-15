// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Material recycle: 3+ connected same-material cells pop (signature Trash Stack mechanic).
public struct RecycleGroup: Sendable, Equatable {
    public let material: Material
    public let cells: [(Int, Int)]

    public static func == (lhs: RecycleGroup, rhs: RecycleGroup) -> Bool {
        guard lhs.material == rhs.material, lhs.cells.count == rhs.cells.count else { return false }
        for i in 0..<lhs.cells.count {
            if lhs.cells[i].0 != rhs.cells[i].0 || lhs.cells[i].1 != rhs.cells[i].1 { return false }
        }
        return true
    }
}

public enum RecycleMatcher {
    public static func findGroups(on board: Board, minSize: Int = 3) -> [RecycleGroup] {
        var seen = Set<String>()
        var groups: [RecycleGroup] = []
        for y in 0..<board.config.rows {
            for x in 0..<board.config.cols {
                let key = "\(x),\(y)"
                guard !seen.contains(key), let cell = board[x, y] else { continue }
                var stack = [(x, y)]
                var cluster: [(Int, Int)] = []
                seen.insert(key)
                while let (cx, cy) = stack.popLast() {
                    cluster.append((cx, cy))
                    for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)] {
                        let nk = "\(nx),\(ny)"
                        guard !seen.contains(nk), board.inBounds(x: nx, y: ny),
                              let n = board[nx, ny], n.material == cell.material else { continue }
                        seen.insert(nk)
                        stack.append((nx, ny))
                    }
                }
                if cluster.count >= minSize {
                    groups.append(RecycleGroup(material: cell.material, cells: cluster))
                }
            }
        }
        return groups
    }
}
