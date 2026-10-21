import AppKit
import HyCodeWorkspace

/// One source for toolbar tiles and drag images. Cache at most six fixed 30pt
/// bitmaps per button; clear on appearance/scale change. Symbols are never passed
/// directly to NSDraggingItem, which can otherwise reinterpret them as templates.
@MainActor
final class WorkbenchToolArtwork {
    enum State: Hashable { case idle, hover, pressed, selected, selectedHover, selectedPressed }
    private let symbol: NSImage?
    private var images: [State: NSImage] = [:]
    private var glyphCache: CGImage?
    private var scale: CGFloat = 0
    private var appearanceName: NSAppearance.Name?

    init(symbolName: String) {
        symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 19, weight: .regular))
    }

    func image(state: State, appearance: NSAppearance, scale: CGFloat) -> NSImage? {
        let name = appearance.bestMatch(from: [.darkAqua, .aqua])
        if self.scale != scale || appearanceName != name {
            images.removeAll(keepingCapacity: true)
            glyphCache = nil
            self.scale = scale
            appearanceName = name
        }
        if let cached = images[state] { return cached }
        guard let symbol else { return nil }
        let interval = WorkbenchPerformance.begin("ToolTileRaster")
        defer { WorkbenchPerformance.end("ToolTileRaster", interval) }
        if glyphCache == nil {
            var proposed = NSRect(origin: .zero, size: symbol.size)
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            glyphCache = symbol.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: transform])
        }
        guard let glyph = glyphCache else { return nil }
        var result: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let background: NSColor
            switch state {
            case .idle: background = WorkbenchColors.nativeChrome
            case .hover: background = WorkbenchColors.nativeControlHover
            case .pressed: background = WorkbenchColors.nativeControlPressed
            case .selected: background = WorkbenchColors.nativeToolSelection
            case .selectedHover: background = WorkbenchColors.nativeToolHover
            case .selectedPressed: background = WorkbenchColors.nativeToolPressed
            }
            let highlighted = state == .selected || state == .selectedHover || state == .selectedPressed
            let foreground =
                highlighted
                ? NSColor.white : state == .idle ? WorkbenchColors.nativeSecondary : WorkbenchColors.nativeText
            if let bitmap = WorkbenchToolTile.render(
                glyph: glyph, glyphSize: symbol.size, background: background.cgColor,
                foreground: foreground.cgColor, scale: Double(scale))
            {
                let image = NSImage(cgImage: bitmap, size: NSSize(width: 30, height: 30))
                image.isTemplate = false
                result = image
            }
        }
        images[state] = result
        return result
    }
}
