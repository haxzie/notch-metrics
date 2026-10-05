import Foundation

/// A comparable semantic version.
///
/// Exists because comparing versions as strings is wrong in a way that only
/// shows up on the tenth minor release: "0.10.0" < "0.9.0" under a string
/// compare, so an updater built on `<` would stop offering updates forever and
/// nobody would notice for months.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".").map { Int($0) }
        guard numbers.count >= 2, numbers.allSatisfy({ $0 != nil }) else { return nil }

        major = numbers[0]!
        minor = numbers[1]!
        patch = numbers.count > 2 ? numbers[2]! : 0
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A pre-release precedes its release: 1.0.0-beta < 1.0.0.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, .some): return false
        case (.some, nil): return true
        case let (.some(l), .some(r)): return l < r
        }
    }
}
