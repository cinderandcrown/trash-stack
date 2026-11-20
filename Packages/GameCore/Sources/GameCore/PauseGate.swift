// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Single idempotent pause source for play. Auto-pause on resign; only Resume clears.
public struct PauseGate: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable {
        case none
        case user
        case resign
    }

    public private(set) var reason: Reason = .none

    public var isPaused: Bool { reason != .none }

    public init(reason: Reason = .none) {
        self.reason = reason
    }

    /// Enter pause. Idempotent — once paused, later calls do not toggle.
    @discardableResult
    public mutating func pause(as newReason: Reason) -> Bool {
        guard newReason != .none else { return false }
        if reason != .none { return false }
        reason = newReason
        return true
    }

    /// Only an explicit resume clears pause (becoming active again does not).
    @discardableResult
    public mutating func resume() -> Bool {
        guard reason != .none else { return false }
        reason = .none
        return true
    }

    /// App left the foreground — pause if currently playing.
    @discardableResult
    public mutating func noteResignActive() -> Bool {
        pause(as: .resign)
    }
}
