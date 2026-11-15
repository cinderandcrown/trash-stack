// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Distinct identity: 8×15 visible compactor bin (not a 10×20 well).
public struct BoardConfig: Sendable, Equatable {
    public let cols: Int
    public let visibleRows: Int
    public let hiddenRows: Int

    public var rows: Int { visibleRows + hiddenRows }

    public static let dumpster = BoardConfig(cols: 8, visibleRows: 15, hiddenRows: 2)

    public init(cols: Int, visibleRows: Int, hiddenRows: Int) {
        self.cols = cols
        self.visibleRows = visibleRows
        self.hiddenRows = hiddenRows
    }
}
