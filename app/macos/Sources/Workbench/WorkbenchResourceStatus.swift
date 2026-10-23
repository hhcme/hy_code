import HyCodeWorkspace
import SwiftUI

struct WorkbenchResourceStatus: View {
    let store: WorkbenchStore
    @State private var monitor = WorkbenchResourceMonitor()
    @State private var showingDetails = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    memoryLabel
                    Text(cpu).frame(width: 76, alignment: .trailing)
                }
                memoryLabel
            }
            .font(.system(size: WorkbenchMetrics.statusFontSize)).monospacedDigit()
            .padding(.horizontal, 6).frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkbenchButtonStyle(active: showingDetails, neutral: true))
        .accessibilityLabel("HyCode 主进程性能")
        .accessibilityValue("内存 \(bytes(monitor.sample?.footprintBytes))，\(cpu)")
        .help("HyCode 主进程内存与 CPU · 点击查看详情或清理自身缓存")
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) { details }
        .task(id: scenePhase == .active, priority: .utility) { await monitor.observe(active: scenePhase == .active) }
    }

    private var memoryLabel: some View {
        Label(bytes(monitor.sample?.footprintBytes), systemImage: "memorychip")
            .frame(minWidth: 85, alignment: .trailing)
    }
    private var cpu: String {
        monitor.sample?.cpuPercent.map { String(format: "CPU %.0f%%", $0) } ?? "CPU —"
    }
    private func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "—"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HyCode 性能", systemImage: "memorychip").font(.system(size: 13, weight: .semibold))
            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                row("内存占用", bytes(monitor.sample?.footprintBytes))
                row("进程峰值", bytes(monitor.sample?.peakFootprintBytes))
                row("驻留内存", bytes(monitor.sample?.residentBytes))
                row("CPU", monitor.sample?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
            }
            WorkbenchSeparator()
            Text("仅 HyCode 主进程，每 2 秒采样。内存使用系统物理占用口径；不含语言服务器和预览子进程。CPU 单核满载为 100%。")
                .foregroundStyle(WorkbenchColors.secondary).fixedSize(horizontal: false, vertical: true)
            Button {
                Task(priority: .utility) {
                    await monitor.cleanCaches {
                        await store.editing.releaseInactiveCaches { store.tabs.active?.location.path }
                    }
                }
            } label: {
                Label(monitor.cleaning ? "正在清理…" : "清理自身闲置缓存", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(WorkbenchButtonStyle(active: true, neutral: true)).disabled(monitor.cleaning)
            Text("释放非活动文档的语法树、闲置语法查询。保留未保存内容、撤销记录及当前文件缓存。")
                .foregroundStyle(WorkbenchColors.secondary).fixedSize(horizontal: false, vertical: true)
            if let cleanup = monitor.cleanup {
                Text(
                    cleanup.documents + cleanup.grammars == 0
                        ? "本次没有清理缓存。" : "已清理 \(cleanup.documents) 个文档缓存、\(cleanup.grammars) 个闲置语法查询。")
                if cleanup.failures > 0 { Text("\(cleanup.failures) 项未能清理，可稍后重试。") }
                Text("清理前 \(bytes(monitor.beforeCleanup)) → 清理后 \(bytes(monitor.afterCleanup))")
                    .monospacedDigit()
                Text("内存回收由系统分配器决定，读数可能不会立即下降。")
                    .foregroundStyle(WorkbenchColors.secondary)
            }
            if let error = monitor.error { Text("采样暂不可用：\(error)").foregroundStyle(WorkbenchColors.secondary) }
        }
        .font(.system(size: 12)).foregroundStyle(WorkbenchColors.text)
        .padding(16).frame(width: 332).background(WorkbenchColors.chrome)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(WorkbenchColors.secondary).gridColumnAlignment(.leading)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}
