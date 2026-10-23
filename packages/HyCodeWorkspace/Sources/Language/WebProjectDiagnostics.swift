import Foundation

public struct ProjectAnalysisScope: Sendable {
    public let total: Int
    public let failed: Int
    public let blockedVue: Int
}

public struct ProjectAnalysisReport: Sendable {
    public let checked: [String]
    public let fullSweep: Bool
}

extension WebLanguageServer {
    public func refreshProjectFiles(_ paths: Set<String>) async throws {
        let root = root
        let reader = Task.detached(priority: .utility) {
            paths.map { ($0, ProjectSourceCatalog.inspect(path: $0, root: root)) }
        }
        let values = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return await reader.value
        } onCancel: {
            reader.cancel()
        }
        for (path, file) in values {
            let uri = root.appendingPathComponent(path).absoluteString
            projectFiles[uri] = file
            if let file {
                try await documentQueue.run { try await self.registerBackground(file) }
            } else {
                try await documentQueue.run { await self.removeBackground(uri) }
            }
        }
    }
    /// Background TS files are registered with the existing tsserver, not with
    /// TLS's interactive buffer list (which requests every open buffer per edit).
    public func setProjectFiles(_ files: [ProjectSourceFile]) async throws {
        guard !stopped else { throw CancellationError() }
        var next: [String: ProjectSourceFile] = [:]
        for file in files where ProjectSourceCatalog.allows(file.path) { next[file.uri(in: root)] = file }
        let old = projectFiles
        projectFiles = next
        hasTypeScriptProject = next.values.contains { $0.language.synchronizes(with: .typescript) }
        for uri in old.keys.sorted() where next[uri] == nil {
            try await documentQueue.run { await self.removeBackground(uri) }
        }
        let changed = next.values.filter { registeredFiles[$0.uri(in: root)] != $0 }.sorted { $0.path < $1.path }
        for start in stride(from: 0, to: changed.count, by: 8) {
            try Task.checkCancellation()
            let batch = Array(changed[start..<min(start + 8, changed.count)])
            try await documentQueue.run { try await self.registerBatch(batch) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func registerBatch(_ files: [ProjectSourceFile]) async throws {
        guard !stopped else { throw CancellationError() }
        let eligible = files.filter {
            !liveURIs.contains($0.uri(in: root)) && ProjectSourceCatalog.allows($0.path)
                && ($0.language != .vue || allowProjectPlugins)
        }
        let root = root
        let reader = Task.detached(priority: .utility) {
            var loaded: [(ProjectSourceFile, String)] = []
            var failed: [String] = []
            for file in eligible {
                try Task.checkCancellation()
                do { loaded.append((file, try ProjectSourceCatalog.read(file, root: root))) } catch is CancellationError
                { throw CancellationError() } catch { failed.append(file.uri(in: root)) }
            }
            return (loaded, failed)
        }
        let (loaded, failed) = try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
        guard !stopped, !Task.isCancelled else { throw CancellationError() }
        for uri in failed {
            await removeBackground(uri)
            failedFiles.insert(uri)
        }
        let typescript = loaded.filter {
            $0.0.language.service == .typescript || ($0.0.language.isJSON && hasTypeScriptProject)
        }
        // JSON escaping can expand a one-byte control character to six bytes.
        // Bound the wire payload as well as file count (LSP body cap: 8 MiB).
        var batch: [(ProjectSourceFile, String)] = []
        var wireBudget = 1_024
        for (file, text) in typescript {
            let cost =
                6 * (text.utf8.count + root.appendingPathComponent(file.path).path.utf8.count + root.path.utf8.count)
                + 1_024
            if !batch.isEmpty && wireBudget + cost > 7 * 1_024 * 1_024 {
                try await registerTypeScriptBatch(batch)
                batch.removeAll(keepingCapacity: true)
                wireBudget = 1_024
            }
            batch.append((file, text))
            wireBudget += cost
        }
        if !batch.isEmpty { try await registerTypeScriptBatch(batch) }
        for (file, text) in loaded where file.language.service != .typescript {
            try Task.checkCancellation()
            let uri = file.uri(in: root)
            if backgroundURIs.remove(uri) != nil { await closeDocument(uri: uri) }
            try await openDocument(uri: uri, language: file.language, text: text, version: 0)
            backgroundURIs.insert(uri)
            registeredFiles[uri] = file
            failedFiles.remove(uri)
        }
    }
    private func registerTypeScriptBatch(_ files: [(ProjectSourceFile, String)]) async throws {
        _ = try await tsCommand(
            "updateOpen",
            JSONValue([
                "openFiles": files.map { file, text in
                    [
                        "file": root.appendingPathComponent(file.path).path, "projectRootPath": root.path,
                        "fileContent": text,
                    ]
                }
            ]))
        for (file, _) in files {
            registeredFiles[file.uri(in: root)] = file
            failedFiles.remove(file.uri(in: root))
        }
    }
    func registerBackground(_ file: ProjectSourceFile) async throws {
        try await registerBatch([file])
    }
    public func projectScope() -> ProjectAnalysisScope {
        ProjectAnalysisScope(
            total: projectFiles.count, failed: failedFiles.count,
            blockedVue: allowProjectPlugins ? 0 : projectFiles.values.filter { $0.language == .vue }.count)
    }
    private func removeBackground(_ uri: String) async {
        guard !liveURIs.contains(uri) else { return }
        registeredFiles[uri] = nil
        failedFiles.remove(uri)
        if backgroundURIs.remove(uri) != nil { await closeDocument(uri: uri) }
        if let url = URL(string: uri),
            WebLanguage.detect(url.path)?.service == .typescript
                || WebLanguage.detect(url.path)?.isJSON == true
        {
            _ = try? await tsCommand("updateOpen", JSONValue(["closedFiles": [url.path]]))
        }
        for service in WebLanguage.Service.allCases {
            emitter.yield(
                JSONValue([
                    "method": "textDocument/publishDiagnostics", "hycodeService": service.rawValue,
                    "params": ["uri": uri, "diagnostics": [JSONValue]()],
                ]))
        }
    }
    func tsCommand(
        _ name: String, _ arguments: JSONValue, asynchronous: Bool = false,
        expectsResult: Bool = true
    ) async throws -> JSONValue {
        guard !stopped else { throw CancellationError() }
        let target = try await connection(.typescript)
        return try await target.request(
            "workspace/executeCommand",
            params: JSONValue([
                "command": "typescript.tsserverRequest",
                "arguments": [
                    JSONValue.string(name), arguments,
                    JSONValue(["isAsync": asynchronous, "lowPriority": true, "expectsResult": expectsResult]),
                ],
            ]), timeout: 60)
    }
    /// The compiler owns resolution/caches. Follow reverse file references,
    /// including aliases and re-exports, rather than guessing imports in Swift.
    public func checkProject(changed: Set<String>? = nil) async throws -> ProjectAnalysisReport {
        await configurationFilesChanged(changed)
        let sourceChanges = changed.map { uris in
            Set(uris.filter { URL(string: $0).flatMap { WebLanguage.detect($0.path) } != nil })
        }
        let candidates = Set(
            projectFiles.compactMap { uri, file in
                (registeredFiles[uri] != nil || liveURIs.contains(uri))
                    && file.language.synchronizes(with: .typescript) && (file.language != .vue || allowProjectPlugins)
                    ? uri : nil
            })
        guard !candidates.isEmpty else { return ProjectAnalysisReport(checked: [], fullSweep: changed == nil) }
        var all = sourceChanges == nil || !(sourceChanges ?? []).subtracting(Set(projectFiles.keys)).isEmpty
        var affected = Set<String>()
        var queue = Array((sourceChanges ?? []).intersection(candidates)).sorted()
        for uri in sourceChanges ?? [] {
            let name = URL(string: uri)?.lastPathComponent ?? ""
            if projectFiles[uri]?.language.isJSON == true { all = true }
            if name == "package.json" || name.hasPrefix("tsconfig") || name.hasPrefix("jsconfig") {
                all = true
                _ = try await tsCommand("reloadProjects", JSONValue([:]), expectsResult: false)
            }
        }
        var index = 0
        while !all, index < queue.count {
            try Task.checkCancellation()
            let uri = queue[index]
            index += 1
            guard affected.insert(uri).inserted, let path = URL(string: uri)?.path else { continue }
            if index > 256 || path.hasSuffix(".d.ts") {
                all = true
                break
            }
            do {
                if changed?.contains(uri) == true {
                    let tree = try await tsCommand("navtree", JSONValue(["file": path]))
                    if tree["body"]["text"].string == "<global>"
                        || tree["body"]["childItems"].array.contains(where: { $0["text"].string == "global" })
                    {
                        all = true
                        break
                    }
                }
                let refs = try await tsCommand("fileReferences", JSONValue(["file": path]))
                for reference in refs["body"]["refs"].array {
                    guard let file = reference["file"].string else { continue }
                    let next = URL(fileURLWithPath: file).absoluteString
                    if candidates.contains(next), !affected.contains(next), !queue.contains(next) { queue.append(next) }
                }
            } catch is CancellationError { throw CancellationError() } catch { all = true }
        }
        let targets = (all ? candidates : affected).sorted()
        for start in stride(from: 0, to: targets.count, by: 32) {
            try Task.checkCancellation()
            let files = targets[start..<min(start + 32, targets.count)].compactMap { URL(string: $0)?.path }
            _ = try await tsCommand("geterr", JSONValue(["files": files, "delay": 20]), asynchronous: true)
            try await Task.sleep(for: .milliseconds(25))
        }
        return ProjectAnalysisReport(checked: targets, fullSweep: all)
    }
}
