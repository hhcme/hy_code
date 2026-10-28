import CoreGraphics

/// Point-space targets sampled from the user-provided 2x Islands reference.
/// These are layout inputs, not a claim of native-window pixel verification.
public enum WorkbenchStyleMetrics {
    public static let headerHeight: CGFloat = 43
    public static let stripeWidth: CGFloat = 40
    public static let shellInset: CGFloat = 1
    public static let tabHeight: CGFloat = 40
    public static let panelHeaderHeight: CGFloat = 40
    public static let statusHeight: CGFloat = 36
    public static let islandRadius: CGFloat = 10
    public static let paneGap: CGFloat = 5
    public static let rowHeight: CGFloat = 24
    public static let treeTopInset: CGFloat = 5
    public static let treeOuterInset: CGFloat = 8
    public static let scrollerWidth: CGFloat = 8
    public static let uiFontSize: CGFloat = 13
    public static let statusFontSize: CGFloat = 12
    public static let toolSide: CGFloat = 30
    public static let toolStep: CGFloat = 40
    public static let railEndInset: CGFloat = 3
    public static let trafficLightLeading: CGFloat = 20
    public static let trafficLightStep: CGFloat = 20
    public static let trafficLightReserve: CGFloat = 80
    public static let editorFontSize: CGFloat = 14
    public static let editorLineHeight: CGFloat = 22
    public static let editorInset = CGSize(width: 10, height: 8)
    public static let gutterFontSize: CGFloat = 12
    public static let controlHeight: CGFloat = 28
    public static let secondaryToolbarHeight: CGFloat = 34
    public static let sectionTabHeight: CGFloat = 26
    public static let dialogHeaderHeight: CGFloat = 48
    public static let controlRadius: CGFloat = 4
    public static let popupRadius: CGFloat = 8
    public static let popupPadding: CGFloat = 6
    public static let menuSeparatorHeight: CGFloat = 9
    public static let projectPopupWidth: CGFloat = 512
    public static let projectPopupRowHeight: CGFloat = 52
}

public enum WorkbenchRailGeometry {
    /// Keep the reference spacing in ordinary windows; compact the gaps when
    /// every tool is moved to one rail at the minimum supported window height.
    public static func step(height: CGFloat) -> CGFloat {
        let available = max(0, height - 2 * WorkbenchStyleMetrics.railEndInset - WorkbenchStyleMetrics.toolSide)
        return min(
            WorkbenchStyleMetrics.toolStep,
            max(
                WorkbenchStyleMetrics.toolSide + 2, floor(available / CGFloat(max(1, WorkbenchTool.allCases.count - 1)))
            ))
    }
    public static func start(count: Int, top: Bool, height: CGFloat) -> CGFloat {
        let inset = WorkbenchStyleMetrics.railEndInset
        return top
            ? inset
            : max(
                inset,
                height - inset - WorkbenchStyleMetrics.toolSide
                    - CGFloat(max(0, count - 1)) * step(height: height))
    }
    public static func insertionIndex(y: CGFloat, count: Int, top: Bool, height: CGFloat) -> Int {
        let origin = start(count: count, top: top, height: height)
        let slot = floor((y - origin) / step(height: height) + 0.5)
        return Int(min(CGFloat(count), max(0, slot)))
    }
    public static func insertionY(index: Int, count: Int, top: Bool, height: CGFloat) -> CGFloat {
        let origin = start(count: count, top: top, height: height)
        return min(max(1, height - 3), max(1, origin + CGFloat(index) * step(height: height) - 5))
    }
}

public enum WorkbenchChromeGeometry {
    /// Keep the actual system-button size. Coordinates use the header's top-left
    /// origin; the runtime converts through public NSView coordinate APIs.
    public static func trafficLight(size: CGSize, index: Int, scale: Double) -> CGRect {
        let grid = WorkbenchPixelGrid(scale: scale)
        let centerX =
            WorkbenchStyleMetrics.trafficLightLeading + CGFloat(index) * WorkbenchStyleMetrics.trafficLightStep
        return CGRect(
            x: grid.snap(centerX - size.width / 2),
            y: grid.snap((WorkbenchStyleMetrics.headerHeight - size.height) / 2),
            width: size.width, height: size.height)
    }
}
