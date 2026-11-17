// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameRender

final class GameRenderTests: XCTestCase {
    func testRenderInfo() {
        XCTAssertTrue(RenderInfo.name.contains("GameRender"))
        XCTAssertTrue(RenderInfo.guidance.contains("jetsam"))
    }
}
