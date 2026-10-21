import CoreGraphics

public struct WorkbenchVisibility: Equatable, Sendable {
    public var project: Bool
    public var information: Bool
    public var openTabs: Bool
    public var workspace: Bool

    public init(project: Bool = true, information: Bool = false, openTabs: Bool = false, workspace: Bool = false) {
        self.project = project
        self.information = information
        self.openTabs = openTabs
        self.workspace = workspace
    }
}

public enum WorkbenchDivider: CaseIterable, Sendable {
    case project, information, bottom, bottomSplit
    public var vertical: Bool { self != .bottom }
}

/// The native canvas owns these in-process preferences. Window fitting and visibility
/// never overwrite them. All adjacent edges use the same snapped coordinate.
public struct WorkbenchPaneSizes: Equatable, Sendable {
    public static let gutter: Double = 6
    public private(set) var projectWidth: Double
    public private(set) var informationWidth: Double
    public private(set) var bottomHeight: Double
    public private(set) var bottomFraction: Double

    public init(
        projectWidth: Double = 300, informationWidth: Double = 280,
        bottomHeight: Double = 220, bottomFraction: Double = 0.5
    ) {
        self.projectWidth = Self.length(projectWidth)
        self.informationWidth = Self.length(informationWidth)
        self.bottomHeight = Self.length(bottomHeight)
        self.bottomFraction = bottomFraction.isFinite ? min(0.8, max(0.2, bottomFraction)) : 0.5
    }

    public mutating func resize(
        _ divider: WorkbenchDivider, to value: Double, width: Double, height: Double,
        visibility: WorkbenchVisibility
    ) {
        let frames = frames(width: width, height: height, visibility: visibility)
        switch divider {
        case .project:
            if visibility.information { informationWidth = frames.information.width }
            let reserved = visibility.information ? frames.information.width + Self.gutter : 0
            projectWidth = Self.extent(
                value, available: Self.length(width) - reserved, minimum: 200, maximum: 600, reserved: 360)
        case .information:
            if visibility.project { projectWidth = frames.project.width }
            let reserved = visibility.project ? frames.project.width + Self.gutter : 0
            informationWidth = Self.extent(
                value, available: Self.length(width) - reserved, minimum: 200, maximum: 600, reserved: 360)
        case .bottom:
            bottomHeight = Self.extent(value, available: height, minimum: 140, maximum: 440, reserved: 220)
        case .bottomSplit:
            let available = max(0, Self.length(width) - Self.gutter)
            let minimum = min(220, available / 2)
            let position = min(max(minimum, Self.length(value)), max(minimum, available - minimum))
            if available > 0 { bottomFraction = position / available }
        }
    }

    public func frames(
        width: Double, height: Double, visibility: WorkbenchVisibility, scale: Double = 2
    ) -> WorkbenchPaneFrames {
        let pixel = WorkbenchPixelGrid(scale: scale)
        let width = pixel.snap(Self.length(width))
        let height = pixel.snap(Self.length(height))
        let gutter = min(Self.gutter, width)
        let count = (visibility.project ? 1.0 : 0) + (visibility.information ? 1.0 : 0)
        let budget = max(0, width - min(360, width) - gutter * count)
        var left = visibility.project ? min(600, max(200, projectWidth)) : 0
        var right = visibility.information ? min(600, max(200, informationWidth)) : 0
        let sum = left + right
        if sum > budget, count > 0 {
            let minimum = min(200, budget / count)
            let extraLeft = visibility.project ? max(0, left - minimum) : 0
            let extraRight = visibility.information ? max(0, right - minimum) : 0
            let extra = extraLeft + extraRight
            let spare = max(0, budget - minimum * count)
            left = visibility.project ? minimum + (extra > 0 ? spare * extraLeft / extra : 0) : 0
            right = visibility.information ? minimum + (extra > 0 ? spare * extraRight / extra : 0) : 0
        }
        left = min(pixel.snap(left), budget)
        right = min(pixel.snap(right), max(0, budget - left))
        let leftGap = visibility.project && left > 0 ? gutter : 0
        let rightGap = visibility.information && right > 0 ? gutter : 0
        let editorX = left + leftGap
        let rightX = width - right
        let editorRight = max(editorX, rightX - rightGap)
        let hasBottom = visibility.openTabs || visibility.workspace
        let bottom = pixel.snap(Self.extent(bottomHeight, available: height, minimum: 140, maximum: 440, reserved: 220))
        let bottomGap = hasBottom && bottom > 0 ? min(Self.gutter, max(0, height - bottom)) : 0
        let topHeight = hasBottom ? max(0, height - bottom - bottomGap) : height
        let bottomY = topHeight + bottomGap
        let split = visibility.openTabs && visibility.workspace
        let splitGap = split ? gutter : 0
        let bottomAvailable = max(0, width - splitGap)
        let bottomMinimum = min(220, bottomAvailable / 2)
        let splitX = pixel.snap(
            min(bottomAvailable - bottomMinimum, max(bottomMinimum, bottomAvailable * bottomFraction)))
        let tabsWidth = split ? splitX : width
        let workspaceX = split ? splitX + splitGap : 0
        return WorkbenchPaneFrames(
            project: CGRect(x: 0, y: 0, width: left, height: topHeight),
            editor: CGRect(x: editorX, y: 0, width: max(0, editorRight - editorX), height: topHeight),
            information: CGRect(x: rightX, y: 0, width: right, height: topHeight),
            openTabs: CGRect(
                x: 0, y: bottomY, width: visibility.openTabs ? tabsWidth : 0, height: hasBottom ? bottom : 0),
            workspace: CGRect(
                x: visibility.workspace ? workspaceX : width, y: bottomY,
                width: visibility.workspace ? max(0, width - workspaceX) : 0, height: hasBottom ? bottom : 0),
            projectDivider: CGRect(x: left, y: 0, width: leftGap, height: topHeight),
            informationDivider: CGRect(x: editorRight, y: 0, width: rightGap, height: topHeight),
            bottomDivider: CGRect(x: 0, y: topHeight, width: width, height: bottomGap),
            bottomSplitDivider: CGRect(x: splitX, y: bottomY, width: splitGap, height: bottom))
    }

    private static func length(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
    private static func extent(
        _ value: Double, available: Double, minimum: Double, maximum: Double, reserved: Double
    ) -> Double {
        let limit = min(maximum, max(0, length(available) - reserved - gutter))
        return min(limit, max(min(minimum, limit), length(value)))
    }
}

public struct WorkbenchPixelGrid: Sendable {
    public let scale: Double
    public init(scale: Double) { self.scale = scale.isFinite && scale >= 1 ? scale : 1 }
    public func snap(_ value: Double) -> Double { (value * scale).rounded() / scale }
    public func rect(_ rect: CGRect) -> CGRect {
        let x = snap(rect.minX)
        let y = snap(rect.minY)
        return CGRect(x: x, y: y, width: max(0, snap(rect.maxX) - x), height: max(0, snap(rect.maxY) - y))
    }
}

public struct WorkbenchPaneFrames: Equatable, Sendable {
    public var project: CGRect
    public var editor: CGRect
    public var information: CGRect
    public var openTabs: CGRect
    public var workspace: CGRect
    public var projectDivider: CGRect
    public var informationDivider: CGRect
    public var bottomDivider: CGRect
    public var bottomSplitDivider: CGRect

    public subscript(_ divider: WorkbenchDivider) -> CGRect {
        switch divider {
        case .project: projectDivider
        case .information: informationDivider
        case .bottom: bottomDivider
        case .bottomSplit: bottomSplitDivider
        }
    }

    public func interpolated(to target: Self, progress: Double, scale: Double) -> Self {
        let t = progress.isFinite ? min(1, max(0, progress)) : 1
        let grid = WorkbenchPixelGrid(scale: scale)
        func blend(_ a: CGRect, _ b: CGRect) -> CGRect {
            grid.rect(
                CGRect(
                    x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                    width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t))
        }
        return Self(
            project: blend(project, target.project), editor: blend(editor, target.editor),
            information: blend(information, target.information), openTabs: blend(openTabs, target.openTabs),
            workspace: blend(workspace, target.workspace),
            projectDivider: blend(projectDivider, target.projectDivider),
            informationDivider: blend(informationDivider, target.informationDivider),
            bottomDivider: blend(bottomDivider, target.bottomDivider),
            bottomSplitDivider: blend(bottomSplitDivider, target.bottomSplitDivider))
    }
}
