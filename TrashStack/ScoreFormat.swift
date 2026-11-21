// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

enum ScoreFormat {
    /// HUD / overlay scores with grouping separators (e.g. 8,800).
    static func commas(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
