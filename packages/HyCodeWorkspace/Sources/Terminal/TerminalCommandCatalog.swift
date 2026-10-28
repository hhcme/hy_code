import Foundation

/// App-owned offline hints. No CLI invocation, plugin load or network lookup.
enum TerminalCommandCatalog {
    struct Entry {
        let value: String
        let detail: String
        let kind: TerminalCompletionCandidate.Kind
    }
    static func entries(words: [String], prefix: String) -> [Entry] {
        if words.isEmpty {
            return [
                ("cd", "切换目录"), ("ls", "列出文件"), ("pwd", "当前目录"), ("clear", "清屏"),
                ("git", "版本控制"), ("flutter", "Flutter 工具"), ("dart", "Dart 工具"),
                ("npm", "Node 包管理"), ("pnpm", "Node 包管理"), ("yarn", "Node 包管理"),
                ("node", "Node.js"), ("cargo", "Rust 工具"), ("rustc", "Rust 编译器"),
                ("swift", "Swift 工具"), ("python3", "Python"), ("pip3", "Python 包管理"),
                ("make", "构建目标"), ("cmake", "C/C++ 构建"), ("docker", "容器工具"),
                ("ssh", "远程 Shell"), ("curl", "网络请求"), ("cat", "查看文件"), ("rg", "搜索文本"),
                ("find", "查找文件"), ("mkdir", "创建目录"), ("touch", "创建文件"), ("echo", "输出文本"),
            ].map { Entry(value: $0.0, detail: $0.1, kind: .command) }
        }
        let command = words[0]
        let pairs: [(String, String)]
        if prefix.hasPrefix("-") {
            pairs =
                switch command {
                case "flutter", "dart":
                    [
                        ("--help", "查看帮助"), ("--version", "工具版本"), ("--verbose", "详细输出"),
                        ("--release", "发布模式"), ("--debug", "调试模式"), ("--profile", "性能分析模式"),
                    ]
                case "git":
                    [("--help", "查看帮助"), ("--version", "Git 版本"), ("--no-pager", "直接显示输出")]
                case "cargo":
                    [
                        ("--help", "查看帮助"), ("--release", "优化构建"), ("--workspace", "整个工作区"),
                        ("--locked", "保持锁文件"), ("--offline", "离线运行"),
                    ]
                default: [("--help", "查看帮助"), ("--version", "版本信息")]
                }
        } else if words.count == 1 {
            pairs =
                switch command {
                case "git":
                    [
                        ("status", "查看工作区"), ("diff", "查看差异"), ("log", "提交历史"), ("add", "添加暂存"),
                        ("commit", "提交更改"), ("switch", "切换分支"), ("checkout", "检出分支或文件"),
                        ("branch", "分支"), ("fetch", "获取远端"), ("pull", "拉取"), ("push", "推送"),
                        ("restore", "恢复文件"), ("stash", "暂存工作区"), ("show", "查看对象"),
                    ]
                case "flutter":
                    [
                        ("run", "运行应用"), ("build", "构建应用"), ("test", "运行测试"), ("analyze", "分析项目"),
                        ("doctor", "检查开发环境"), ("devices", "设备列表"), ("pub", "依赖工具"),
                        ("clean", "清理构建"), ("create", "创建项目"), ("logs", "设备日志"),
                    ]
                case "dart":
                    [
                        ("run", "运行程序"), ("test", "运行测试"), ("analyze", "分析项目"), ("format", "格式化"),
                        ("fix", "修复建议"), ("compile", "编译"), ("pub", "依赖工具"), ("create", "创建项目"),
                    ]
                case "npm", "pnpm", "yarn":
                    [
                        ("install", "安装依赖"), ("run", "运行脚本"), ("test", "运行测试"), ("build", "构建"),
                        ("add", "添加依赖"), ("remove", "移除依赖"), ("update", "更新依赖"),
                    ]
                case "cargo":
                    [
                        ("build", "构建"), ("run", "运行"), ("test", "测试"), ("check", "检查"),
                        ("clippy", "静态分析"), ("fmt", "格式化"), ("add", "添加依赖"), ("clean", "清理"),
                    ]
                case "swift":
                    [("build", "构建"), ("run", "运行"), ("test", "测试"), ("package", "包管理")]
                default: []
                }
        } else if ["flutter", "dart"].contains(command), words[1] == "pub", words.count == 2 {
            pairs = [
                ("get", "获取依赖"), ("add", "添加依赖"), ("remove", "移除依赖"),
                ("upgrade", "升级依赖"), ("outdated", "检查过期依赖"), ("deps", "依赖树"),
            ]
        } else if command == "flutter", words[1] == "build", words.count == 2 {
            pairs = [
                ("apk", "Android APK"), ("appbundle", "Android App Bundle"), ("ios", "iOS"),
                ("ipa", "iOS 归档"), ("macos", "macOS"), ("web", "Web"), ("ohos", "HarmonyOS"),
            ]
        } else {
            pairs = []
        }
        return pairs.map { Entry(value: $0.0, detail: $0.1, kind: prefix.hasPrefix("-") ? .option : .subcommand) }
    }
}
