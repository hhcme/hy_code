import Foundation

/// Keep user-authorized display paths at the client boundary while tools use
/// the physical workspace identity (notably /var vs /private/var on macOS).
public struct NativeLanguageURIs: Sendable {
    public let root: URL
    public let serverRoot: URL
    public init(root: URL) throws {
        self.root = root
        self.serverRoot = try NativeWorkspacePaths.physical(root)
    }
    private func replace(_ value: String, from: URL, to: URL) -> String {
        guard let url = URL(string: value), url.isFileURL, url.host == nil || url.host == "localhost", url.query == nil,
            url.fragment == nil
        else { return value }
        if url.path == from.path { return to.absoluteString }
        guard url.path.hasPrefix(from.path + "/") else { return value }
        return to.appendingPathComponent(String(url.path.dropFirst(from.path.count + 1))).absoluteString
    }
    public func toServer(_ value: String) -> String { replace(value, from: root, to: serverRoot) }
    public func toClient(_ value: String) -> String { replace(value, from: serverRoot, to: root) }
    public func project(_ value: JSONValue, outgoing: Bool) -> JSONValue {
        func uri(_ value: String) -> String { outgoing ? toServer(value) : toClient(value) }
        switch value {
        case .array(let items): return .array(items.map { project($0, outgoing: outgoing) })
        case .object(let fields):
            return .object(
                fields.mapValues { $0 }.reduce(into: [String: JSONValue]()) { result, item in
                    let (key, child) = item
                    if ["uri", "targetUri", "oldUri", "newUri"].contains(key), let string = child.string {
                        result[key] = .string(uri(string))
                    } else if key == "changes", case .object(let changes) = child {
                        result[key] = .object(
                            changes.reduce(into: [:]) { $0[uri($1.key)] = project($1.value, outgoing: outgoing) })
                    } else {
                        result[key] = project(child, outgoing: outgoing)
                    }
                })
        default: return value
        }
    }
}
