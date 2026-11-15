// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum ConfigLoader {
    public static func economy() throws -> EconomyConfig {
        try decode("economy", as: EconomyConfig.self)
    }

    public static func activeSeason() throws -> SeasonConfig {
        let index: SeasonIndex = try decode("seasons/index", as: SeasonIndex.self)
        let name = index.seasons.first ?? "season-1-neon-dumpster"
        return try decode("seasons/\(name)", as: SeasonConfig.self)
    }

    private static func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try resourceURL(named: name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func resourceURL(named name: String) throws -> URL {
        let bundle = Bundle.module
        let parts = name.split(separator: "/").map(String.init)
        let file = parts.last ?? name
        let sub = parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil

        let lookups: [URL?] = [
            bundle.url(forResource: file, withExtension: "json", subdirectory: sub),
            bundle.url(forResource: file, withExtension: "json", subdirectory: sub.map { "Resources/\($0)" }),
            bundle.url(forResource: file, withExtension: "json", subdirectory: "Resources"),
            bundle.url(forResource: name, withExtension: "json"),
            bundle.resourceURL?.appendingPathComponent("Resources/\(name).json"),
            bundle.resourceURL?.appendingPathComponent("\(name).json"),
        ]
        for url in lookups {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        throw ConfigError.missing(name)
    }
}

public enum ConfigError: Error, Sendable {
    case missing(String)
}
