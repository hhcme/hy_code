import CryptoKit
import Foundation
import HyCodeWorkspace

/// Verifies the application-owned official distribution once, off MainActor.
/// There is no PATH lookup, external-app extraction, automatic download or update.
actor CodexBundledRuntime {
    static let shared = CodexBundledRuntime()
    private var verified: URL?
    private var verification: Task<URL, Error>?
    func executable() async throws -> URL {
        if let verified { return verified }
        if let verification { return try await verification.value }
        guard let resources = Bundle.main.resourceURL else { throw LanguageServiceFailure("找不到 HyCode 运行资源") }
        let directory = resources.appendingPathComponent("codex-runtime")
        let verification = Task.detached(priority: .utility) {
            struct Manifest: Decodable {
                struct Entry: Decodable {
                    let path: String
                    let sha256: String
                }
                let version: String
                let files: [Entry]
            }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL), data.count <= 65_536,
                let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                manifest.version == "0.164.0", manifest.files.count == 4,
                Set(manifest.files.map(\.path))
                    == Set(["bin/codex", "bin/codex-code-mode-host", "codex-path/rg", "codex-package.json"])
            else { throw LanguageServiceFailure("内置 Codex 运行资源缺失，请重新构建完整 HyCode 开发包") }
            for file in manifest.files {
                guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else {
                    throw LanguageServiceFailure("内置 Codex 资源清单无效")
                }
                let url = directory.appendingPathComponent(file.path)
                guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
                    throw LanguageServiceFailure("内置 Codex 资源包含符号链接")
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest == file.sha256 else { throw LanguageServiceFailure("内置 Codex 资源校验失败，请重新构建") }
            }
            let executable = directory.appendingPathComponent("bin/codex")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw LanguageServiceFailure("内置 Codex 不可执行")
            }
            return executable
        }
        self.verification = verification
        do {
            let value = try await verification.value
            verified = value
            self.verification = nil
            return value
        } catch {
            self.verification = nil
            throw error
        }
    }
}
