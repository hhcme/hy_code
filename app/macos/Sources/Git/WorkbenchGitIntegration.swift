import Foundation
import HyCodeWorkspace

extension WorkbenchStore {
    func configureGit(access: WorkspaceAccess?) {
        git.executionAllowed = { [weak self] in
            guard let self else { return false }
            return !self.codex.busy && !self.dart.toolRunning && !self.web.toolRunning
                && !self.terminal.hasLiveSessions
                && !self.flutter.active && !self.flutter.commandRunning && !self.editing.isClosing
                && !self.editing.preparingLanguageEdit && self.editing.editPreview == nil
        }
        git.prepareWrite = { [weak self] id, paths in
            guard let self, self.git.executionAllowed() else { return false }
            return await self.editing.prepareGitWrite(id, paths: paths)
        }
        git.finishWrite = { [weak self] id, reload in self?.editing.finishAgentWrite(id, reload: reload) }
        git.onDiskChanged = { [weak self] in self?.refresh() }
        git.openDiff = { [weak self] in self?.navigate(.gitDiff($0), preview: true) }
        git.documentForDiff = { [weak self] path in
            guard let self, !self.isReadOnlyPreview(path) else { return nil }
            self.openSharedDocument(path)
            return self.editing.documents[path]
        }
        git.reloadDocument = { [weak self] path in
            guard let self, self.activeDocument?.path == path else { return }
            self.reloadActiveDocument()
        }
        git.openSource = { [weak self] path in
            self?.open(
                WorkspaceEntry(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path, kind: .file),
                preview: false)
        }
        git.dirtyPaths = { [weak self] in
            Set(self?.editing.documents.values.filter { $0.isDirty || $0.composing }.map(\.path) ?? [])
                .union(self?.git.blockedBufferPaths ?? [])
        }
        git.savePaths = { [weak self] paths in
            guard let self, !self.git.writing, !self.editing.isClosing else { return false }
            var saved = true
            for path in paths {
                if let document = self.editing.documents[path], !(await document.save()) { saved = false }
            }
            return saved
        }
        git.configure(access: access)
    }
    func revealGitCommit() { if !docking.isVisible(.commit) { docking.toggle(.commit) } }
    func revealGitLog() { if !docking.isVisible(.git) { docking.toggle(.git) } }
}
