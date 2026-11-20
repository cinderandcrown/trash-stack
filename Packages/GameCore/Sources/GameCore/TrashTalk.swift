// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// TRASH TALK — real-time 1v1. No wagers, no paid entry, no real-value prizes.
public enum TrashTalkRules {
    /// Junk rows sent for a recycle wave. 1 clear → 0, 2 → 1, 3 → 2, 4+ → 4; combo adds more.
    public static func junkRows(clears: Int, combo: Int) -> Int {
        let base: Int
        switch max(0, clears) {
        case 0, 1: base = 0
        case 2: base = 1
        case 3: base = 2
        default: base = 4
        }
        return base + max(0, combo - 1)
    }

    /// Seconds the warning meter shows before junk lands in the rival bin.
    public static let junkWarningSec: Double = 1.35

    /// Matchmaking timeout before we offer a labeled bot opponent.
    public static let matchmakingBotFallbackSec: Double = 20

    /// Countdown before both bins go live.
    public static let countdownSec: Double = 3

    public static let leaderboardAllTime = "trashstack_endless"
    public static let leaderboardWeekly = "trashstack_weekly"
    public static let leaderboardDaily = "trashstack_daily"
}

/// Tiny net payload — piece locks + junk events only.
public enum TrashTalkWire: Sendable, Equatable {
    case hello(seed: UInt64)
    case lock(pieceIndex: UInt16, x: Int8, y: Int8, rot: UInt8, hard: Bool)
    case junk(rows: UInt8)
    case boardDigest(filled: UInt8, topY: UInt8)
    case topOut
    case rematch
    case ping

    private static let version: UInt8 = 1

    public func encode() -> Data {
        var out = Data([Self.version])
        switch self {
        case .hello(let seed):
            out.append(0x10)
            var s = seed.bigEndian
            withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
        case .lock(let idx, let x, let y, let rot, let hard):
            out.append(0x01)
            var i = idx.bigEndian
            withUnsafeBytes(of: &i) { out.append(contentsOf: $0) }
            out.append(contentsOf: [UInt8(bitPattern: x), UInt8(bitPattern: y), rot, hard ? 1 : 0])
        case .junk(let rows):
            out.append(contentsOf: [0x02, rows])
        case .boardDigest(let filled, let topY):
            out.append(contentsOf: [0x05, filled, topY])
        case .topOut:
            out.append(0x03)
        case .rematch:
            out.append(0x04)
        case .ping:
            out.append(0x06)
        }
        return out
    }

    public static func decode(_ data: Data) -> TrashTalkWire? {
        guard data.count >= 2, data[0] == version else { return nil }
        let op = data[1]
        switch op {
        case 0x10:
            guard data.count >= 10 else { return nil }
            let seed = data.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return .hello(seed: seed)
        case 0x01:
            guard data.count >= 8 else { return nil }
            let idx = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            return .lock(
                pieceIndex: idx,
                x: Int8(bitPattern: data[4]),
                y: Int8(bitPattern: data[5]),
                rot: data[6],
                hard: data[7] != 0
            )
        case 0x02:
            guard data.count >= 3 else { return nil }
            return .junk(rows: data[2])
        case 0x05:
            guard data.count >= 4 else { return nil }
            return .boardDigest(filled: data[2], topY: data[3])
        case 0x03: return .topOut
        case 0x04: return .rematch
        case 0x06: return .ping
        default: return nil
        }
    }
}

public enum TrashTalkMatchPhase: String, Sendable, Equatable {
    case idle
    case matchmaking
    case countdown
    case playing
    case finished
}

public struct TrashTalkResult: Sendable, Equatable {
    public var won: Bool
    public var vsBot: Bool
    public var junkSent: Int
    public var junkReceived: Int
    public var score: Int

    public init(won: Bool, vsBot: Bool, junkSent: Int, junkReceived: Int, score: Int) {
        self.won = won
        self.vsBot = vsBot
        self.junkSent = junkSent
        self.junkReceived = junkReceived
        self.score = score
    }
}

/// ISO week seed — same puzzle for everyone that week (UTC).
public enum WeeklyTournament {
    public static func weekKey(for date: Date = Date(), calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let y = comps.yearForWeekOfYear ?? 2026
        let w = comps.weekOfYear ?? 1
        return String(format: "%04d-W%02d", y, w)
    }

    public static func seed(for date: Date = Date()) -> UInt64 {
        let key = weekKey(for: date)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in key.utf8 {
            hash ^= UInt64(b)
            hash &*= 0x100_0000_01b3
        }
        return hash == 0 ? 1 : hash
    }
}
