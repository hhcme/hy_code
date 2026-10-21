import Foundation

/// Reads only the simple package/version/dependency fields emitted by Pub in
/// pubspec.lock. This is deliberately not a general YAML parser: unsupported
/// scalars stay unknown and never affect Pub resolution or source editing.
enum DartPackageLock {
    struct Entry {
        var version: String?
        var dependency: String?
        var source: String?
    }
    static func parse(_ text: String) -> [String: Entry] {
        var result: [String: Entry] = [:]
        var packages = false
        var name: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line == "packages:" {
                packages = true
                continue
            }
            if !line.hasPrefix(" ") && !line.hasPrefix("#") {
                packages = false
                name = nil
            }
            guard packages else { continue }
            if line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") {
                let candidate = String(line.dropFirst(2).dropLast())
                guard result.count < 5_000,
                    candidate.range(of: #"^[a-z][a-z0-9_]*$"#, options: .regularExpression) != nil
                else {
                    name = nil
                    continue
                }
                name = candidate
                result[candidate] = Entry()
            } else if let name, line.hasPrefix("    "), !line.hasPrefix("     "),
                let separator = line.firstIndex(of: ":")
            {
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                switch key {
                case "version" where value.range(of: #"^[a-zA-Z0-9.+_-]+$"#, options: .regularExpression) != nil:
                    result[name]?.version = value
                case "dependency" where ["direct main", "direct dev", "transitive"].contains(value):
                    result[name]?.dependency = value
                case "source" where ["hosted", "git", "path", "sdk"].contains(value): result[name]?.source = value
                default: break
                }
            }
        }
        return result
    }
}
