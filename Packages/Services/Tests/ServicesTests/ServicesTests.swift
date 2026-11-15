// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import Services

final class ServicesTests: XCTestCase {
    func testDayKeyFormat() {
        let key = NotificationService.dayKey(Date(timeIntervalSince1970: 1_000_000))
        XCTAssertFalse(key.isEmpty)
        XCTAssertEqual(key.count, 10)
    }
}
