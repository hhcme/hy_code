import AppKit
import HyCodeWorkspace
import Observation
import SwiftUI

@MainActor @Observable final class LargeFileEditorState {
    var page: LargeTextPage
    var busy = false
    var message: String?
    var query = ""
    var bytePosition = "0"
    var slider = 0.0
    var nextMatch: UInt64 = 0
    var previousQuery = ""
    @ObservationIgnored private var budget: LargeEditBudget
    @ObservationIgnored weak var document: EditorDocument?
    @ObservationIgnored let history = LargeFileUndoManager()
    @ObservationIgnored var cancellation: DocumentSaveCancellation?
    init(page: LargeTextPage, document: EditorDocument) {
        self.page = page
        self.document = document
        budget = LargeEditBudget(bytes: page.remainingBytes, pieces: page.remainingPieces)
        history.owner = self
        accept(page)
    }
    func accept(_ page: LargeTextPage) {
        self.page = page
        budget = LargeEditBudget(bytes: page.remainingBytes, pieces: page.remainingPieces)
        slider = page.fraction
        bytePosition = String(page.start)
    }
    func reserve(revision: UInt64, bytes: Int) {
        budget.reserve(revision: revision, bytes: bytes)
        page.remainingBytes = budget.bytes
        page.remainingPieces = budget.pieces
        page.canUndo = true
        page.canRedo = false
    }
    func acknowledge(_ status: LargeTextStatus, revision: UInt64) {
        budget.acknowledge(bytes: status.remainingBytes, pieces: status.remainingPieces, revision: revision)
        page.remainingBytes = budget.bytes
        page.remainingPieces = budget.pieces
        page.canUndo = budget.hasPendingEdits || status.canUndo
        page.canRedo = !budget.hasPendingEdits && status.canRedo
    }
    func move(_ offset: UInt64) { document?.largeAction(.page(offset)) }
    func find() {
        if query != previousQuery {
            nextMatch = 0
            previousQuery = query
        }
        document?.largeAction(.find(query, nextMatch))
    }
    var rangeLabel: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(page.totalBytes), countStyle: .file)
        return "\(page.start.formatted())–\(page.end.formatted()) / \(total)"
    }
}
enum LargeFileAction {
    case page(UInt64)
    case history(Bool)
    case find(String, UInt64)
}

/// Large-file history has one owner in Rust, across pages and saves. AppKit must
/// not replay page-local ranges after a different page has been installed.
@MainActor final class LargeFileUndoManager: UndoManager {
    weak var owner: LargeFileEditorState?
    override var canUndo: Bool { owner?.busy == false && owner?.page.canUndo == true }
    override var canRedo: Bool { owner?.busy == false && owner?.page.canRedo == true }
    override func undo() { if canUndo { owner?.document?.largeAction(.history(false)) } }
    override func redo() { if canRedo { owner?.document?.largeAction(.history(true)) } }
}

struct LargeFileToolbar: View {
    @Bindable var state: LargeFileEditorState
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("大文件 · 分段编辑").fontWeight(.medium)
                Text(state.rangeLabel).monospacedDigit().foregroundStyle(WorkbenchColors.secondary)
                Spacer(minLength: 8)
                if state.busy { ProgressView().controlSize(.mini) }
                Button("取消") { state.cancellation?.cancel() }.disabled(!state.busy)
                Text("片段行号").foregroundStyle(WorkbenchColors.secondary)
                    .help("行号与原生查找只针对当前片段；下方查找会流式搜索整个文件。源文件没有被截断。")
            }
            HStack(spacing: 6) {
                Button {
                    state.move(0)
                } label: {
                    Image(systemName: "backward.end")
                }.disabled(state.page.start == 0)
                Button {
                    state.move(state.page.previous)
                } label: {
                    Image(systemName: "chevron.left")
                }.disabled(state.page.start == 0)
                Slider(value: $state.slider, in: 0...1) { editing in
                    if !editing { state.move(state.page.position(fraction: state.slider)) }
                }.help("定位整个文件的字节位置，松开后读取片段")
                Button {
                    state.move(state.page.end)
                } label: {
                    Image(systemName: "chevron.right")
                }.disabled(state.page.end >= state.page.totalBytes)
                Button {
                    state.move(state.page.last)
                } label: {
                    Image(systemName: "forward.end")
                }.disabled(state.page.end >= state.page.totalBytes)
                TextField("字节位置", text: $state.bytePosition).frame(width: 120).onSubmit {
                    if let position = UInt64(state.bytePosition) { state.move(position) }
                }.help("原始编码的字节位置，不含 BOM")
                TextField("查找整个文件（区分大小写）", text: $state.query).frame(minWidth: 150, maxWidth: 260)
                    .onSubmit { state.find() }
                Button("下一处") { state.find() }.disabled(state.query.isEmpty)
            }.disabled(state.busy)
            if let message = state.message {
                Text(message).foregroundStyle(WorkbenchColors.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.system(size: 11)).buttonStyle(WorkbenchActionButtonStyle())
            .padding(.horizontal, 10).padding(.vertical, 7).background(WorkbenchColors.chrome)
    }
}
