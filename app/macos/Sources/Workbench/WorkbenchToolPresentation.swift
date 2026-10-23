import HyCodeWorkspace

extension WorkbenchCorner {
    var title: String {
        switch self {
        case .topLeading: "左上"
        case .topTrailing: "右上"
        case .bottomLeading: "左下"
        case .bottomTrailing: "右下"
        }
    }
}

extension WorkbenchTool {
    var title: String {
        switch self {
        case .project: "项目"
        case .search: "搜索"
        case .structure: "结构"
        case .git: "Git"
        case .terminal: "终端"
        case .debug: "调试"
        case .analysis: "分析"
        case .problems: "问题"
        case .information: "文件信息"
        case .openTabs: "已打开标签"
        case .workspace: "项目概览"
        }
    }
    var symbol: String {
        switch self {
        case .project: "folder"
        case .search: "magnifyingglass"
        case .structure: "list.bullet.indent"
        case .git: "point.3.connected.trianglepath.dotted"
        case .terminal: "terminal"
        case .debug: "ladybug"
        case .analysis: "chart.xyaxis.line"
        case .problems: "exclamationmark.circle"
        case .information: "info.circle"
        case .openTabs: "rectangle.stack"
        case .workspace: "square.grid.2x2"
        }
    }
    var shortcut: Character? {
        switch self {
        case .project: "1"
        case .information: "2"
        case .openTabs: "3"
        case .workspace: "4"
        case .debug: "5"
        case .analysis: "6"
        case .problems: "7"
        case .structure: "8"
        case .git: "9"
        case .terminal: "0"
        case .search: nil
        }
    }
}
