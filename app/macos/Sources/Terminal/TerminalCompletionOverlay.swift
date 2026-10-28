import HyCodeWorkspace
import SwiftUI

struct TerminalCompletionOverlay: View {
    @Bindable var session: TerminalPaneSession
    var body: some View {
        GeometryReader { geometry in
            if !session.completions.isEmpty {
                let width = min(370, max(0, geometry.size.width - 12))
                let height = CGFloat(min(8, session.completions.count) * 28 + 30)
                let available = min(height, max(0, geometry.size.height - 8))
                let origin = session.completionOrigin
                let below = origin.y + height <= geometry.size.height - 4
                VStack(spacing: 0) {
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(session.completions.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        session.completionChoice = index
                                        session.acceptCompletion()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: symbol(item.kind)).font(.system(size: 11))
                                                .foregroundStyle(WorkbenchColors.secondary).frame(width: 16)
                                            Text(item.value).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text(item.detail).font(.system(size: 10))
                                                .foregroundStyle(WorkbenchColors.secondary).lineLimit(1)
                                        }.padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
                                    }.buttonStyle(WorkbenchButtonStyle(active: index == session.completionChoice))
                                        .id(index)
                                }
                            }.background(WorkbenchScrollStyle())
                        }.onChange(of: session.completionChoice) { _, index in reader.scrollTo(index) }
                    }
                    WorkbenchSeparator()
                    HStack(spacing: 8) {
                        Text("Tab 插入").foregroundStyle(WorkbenchColors.text)
                        Text("↑↓ 选择 · Esc 收起")
                        Spacer(minLength: 0)
                    }.font(.system(size: 10)).foregroundStyle(WorkbenchColors.secondary)
                        .padding(.horizontal, 9).frame(height: 27)
                }
                .frame(width: width, height: available)
                .background(WorkbenchColors.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchColors.tabBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
                .offset(
                    x: min(max(4, origin.x), max(4, geometry.size.width - width - 4)),
                    y: min(
                        max(4, below ? origin.y : origin.y - available - 22),
                        max(4, geometry.size.height - available - 4)))
            }
        }
    }
    private func symbol(_ kind: TerminalCompletionCandidate.Kind) -> String {
        switch kind {
        case .command: "terminal"
        case .subcommand: "chevron.right"
        case .option: "slider.horizontal.3"
        case .folder: "folder"
        case .file: "doc"
        }
    }
}
