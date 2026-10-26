import Foundation

/// What a custom app looks like, as its manifest declares it.
///
/// Mirrors `ConnectorIconSpec` in `@notchmetrics/core`. It lives in
/// `MetricsCore` rather than beside the manifest because three modules need
/// it: the manifest decodes it, the catalogue carries it, and the icon view
/// draws it.
///
/// The arms exist because the author is usually an agent writing one JSON
/// file. Requiring artwork meant every agent-authored app fell back to the
/// generic mark — naming an SF Symbol is something an LLM does easily and
/// drawing a square PNG is not.
public enum CustomAppIcon: Sendable, Hashable {
    /// An SF Symbol, which is what most custom apps should use: vector, in
    /// keeping with the rest of the interface, and no file to ship.
    case symbol(name: String, tint: String?)
    case emoji(String)
    /// A mark the app already ships, named by app id.
    ///
    /// The icon *and* the tile colour come from `AppCatalog`, so a connector
    /// built against a known service looks like that service without shipping
    /// a copy of its logo that drifts from ours.
    case app(id: String)
    /// A file **name** inside the app's own directory. Resolved against that
    /// directory by `LoadedConnector`, never used as a path on its own.
    case file(name: String)
    /// An arm added after this build shipped.
    ///
    /// Kept rather than refused, so a manifest from a newer core still loads
    /// and the app simply draws its generic mark. The asymmetry the house
    /// rules ask for: strict on the server, an `unknown` fallback here.
    case unknown
}

extension CustomAppIcon: Codable {
    private enum Keys: String, CodingKey { case type, name, tint, value, path, appId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "symbol":
            self = .symbol(
                name: try c.decode(String.self, forKey: .name),
                tint: try c.decodeIfPresent(String.self, forKey: .tint))
        case "emoji":
            self = .emoji(try c.decode(String.self, forKey: .value))
        case "app":
            self = .app(id: try c.decode(String.self, forKey: .appId))
        case "file":
            self = .file(name: try c.decode(String.self, forKey: .path))
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .symbol(name, tint):
            try c.encode("symbol", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(tint, forKey: .tint)
        case let .emoji(value):
            try c.encode("emoji", forKey: .type)
            try c.encode(value, forKey: .value)
        case let .app(id):
            try c.encode("app", forKey: .type)
            try c.encode(id, forKey: .appId)
        case let .file(name):
            try c.encode("file", forKey: .type)
            try c.encode(name, forKey: .path)
        case .unknown:
            try c.encode("unknown", forKey: .type)
        }
    }
}

extension CustomAppIcon {
    /// The app whose mark and colour this borrows, for the one arm that does.
    public var borrowedAppId: String? {
        if case let .app(id) = self { return id }
        return nil
    }

    /// The file name, for the one arm that has one.
    public var fileName: String? {
        if case let .file(name) = self { return name }
        return nil
    }

    /// Resolved against the directory the app was installed into.
    ///
    /// Appends a single path component and refuses anything containing a
    /// separator, so a manifest naming `../../../../etc/passwd` cannot reach
    /// outside its own directory even if it gets past the schema's pattern.
    public func fileURL(in directory: URL) -> URL? {
        guard let name = fileName, !name.isEmpty else { return nil }
        guard !name.contains("/"), name != ".", name != ".." else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
