import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized)
struct CodexCredentialTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "HyCodeLocalCredentials-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func localCredentialsSurviveNewClientsWithPrivateModesAndIndependentAccounts() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("vault")
        let first = CodexCredentials(directory: vault)
        #expect(try await first.read("not-configured") == nil)
        #expect(!FileManager.default.fileExists(atPath: vault.path))
        try await first.write("fixture-value-a", account: "provider-a")
        try await first.write("fixture-value-b", account: "provider-b")
        let second = CodexCredentials(directory: vault)
        #expect(try await second.read("provider-a") == "fixture-value-a")
        #expect(try await second.read("provider-b") == "fixture-value-b")
        try await second.write("replacement-value", account: "provider-a")
        #expect(try await first.read("provider-a") == "replacement-value")
        #expect(try await first.read("provider-b") == "fixture-value-b")
        let directoryMode = try FileManager.default.attributesOfItem(atPath: vault.path)[.posixPermissions] as? Int
        #expect(directoryMode == 0o700)
        let records = try FileManager.default.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil)
        #expect(records.filter { $0.pathExtension == "key" }.count == 2)
        for file in records {
            #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)
            #expect(!file.lastPathComponent.contains("provider"))
            #expect(!file.lastPathComponent.hasPrefix(".key-"))
        }
    }
    @Test func invalidOrOversizedInputKeepsThePreviousCredential() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = CodexCredentials(directory: root.appendingPathComponent("vault"))
        try await credentials.write("kept-value", account: "account")
        for value in ["", "line\nbreak", String(repeating: "x", count: 16385)] {
            await #expect(throws: LanguageServiceFailure.self) {
                try await credentials.write(value, account: "account")
            }
        }
        await #expect(throws: LanguageServiceFailure.self) { try await credentials.write("valid", account: "") }
        #expect(try await credentials.read("account") == "kept-value")
    }
    @Test func symlinkHardlinkAndOversizedRecordsAreRejectedWithoutChangingTheTarget() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("vault")
        let credentials = CodexCredentials(directory: vault)
        try await credentials.write("initial", account: "account")
        let record = vault.appendingPathComponent(try CodexCredentials.recordName("account"))
        let external = root.appendingPathComponent("external")
        try Data("must-stay".utf8).write(to: external)
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: external)
        await #expect(throws: (any Error).self) { _ = try await credentials.read("account") }
        await #expect(throws: (any Error).self) { try await credentials.write("replacement", account: "account") }
        #expect(try String(contentsOf: external, encoding: .utf8) == "must-stay")
        try FileManager.default.removeItem(at: record)
        try FileManager.default.linkItem(at: external, to: record)
        await #expect(throws: (any Error).self) { _ = try await credentials.read("account") }
        await #expect(throws: (any Error).self) { try await credentials.write("replacement", account: "account") }
        #expect(try String(contentsOf: external, encoding: .utf8) == "must-stay")
        try FileManager.default.removeItem(at: record)
        try Data(repeating: 1, count: 16385).write(to: record)
        await #expect(throws: (any Error).self) { _ = try await credentials.read("account") }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: vault)
        let redirected = CodexCredentials(directory: alias)
        await #expect(throws: (any Error).self) { try await redirected.write("replacement", account: "another") }
    }
    @Test func aBusyLocalVaultFailsWithoutOverwritingAnExistingRecord() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("vault")
        let credentials = CodexCredentials(directory: vault)
        try await credentials.write("kept-value", account: "account")
        let lock = open(vault.appendingPathComponent(".lock").path, O_RDWR | O_CLOEXEC)
        #expect(lock >= 0)
        defer { if lock >= 0 { close(lock) } }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: LanguageServiceFailure.self) {
            try await credentials.write("other-value", account: "account")
        }
        #expect(flock(lock, LOCK_UN) == 0)
        #expect(try await credentials.read("account") == "kept-value")
    }
    @Test func aBroadWorkspaceCannotReadOrMoveTheCredentialVault() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("private")
        let vault = parent.appendingPathComponent("vault")
        let credentials = CodexCredentials(directory: vault)
        try await credentials.write("fixture-vault-value", account: "account")
        let record = vault.appendingPathComponent(try CodexCredentials.recordName("account"))
        let home = root.appendingPathComponent("home")
        let runtime = root.appendingPathComponent("runtime")
        for folder in [home, runtime] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let policy = try CodexSandbox.policy(
            runtime: runtime, root: root, home: home, mode: .workspaceWrite, protectedDirectories: [vault])
        let script = """
            if cat "$1" >/dev/null 2>&1; then printf ESCAPED; else printf READ_DENIED; fi
            if mv "$2" "$3" 2>/dev/null; then printf MOVED; else printf MOVE_DENIED; fi
            if ln "$1" "$5" 2>/dev/null; then printf LINK_ESCAPED; else printf LINK_DENIED; fi
            printf allowed > "$4"
            """
        let task = DeveloperToolTask()
        let result = try await task.run(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: [
                "-p", policy, "/bin/sh", "-c", script, "probe", record.path, parent.path,
                root.appendingPathComponent("moved").path, root.appendingPathComponent("ordinary-file").path,
                root.appendingPathComponent("linked-key").path,
            ], directory: root
        ) { _ in }
        #expect(result.exitCode == 0 && result.stdout == "READ_DENIEDMOVE_DENIEDLINK_DENIED")
        #expect(try await credentials.read("account") == "fixture-vault-value")
        #expect(try String(contentsOf: root.appendingPathComponent("ordinary-file"), encoding: .utf8) == "allowed")
    }
}
