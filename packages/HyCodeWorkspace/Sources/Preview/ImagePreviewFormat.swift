import Foundation

public enum ImagePreviewFormat {
    // Dispatch only: actual file signatures and runtime decoder support are
    // checked in the worker. Unknown/code suffixes keep their existing editor.
    private static let extensions: Set<String> = [
        "png", "apng", "jpg", "jpeg", "jpe", "jfif", "gif", "webp", "bmp", "dib", "tif", "tiff",
        "heic", "heif", "avif", "avci", "hif", "ico", "cur", "icns", "jp2", "j2k", "jpf", "jpx",
        "psd", "tga", "exr", "hdr", "pbm", "pgm", "ppm", "pnm", "sgi", "dds", "ktx", "ktx2", "jxl",
        "dng", "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "sr2", "orf", "raf", "rw2", "pef", "srw", "svg",
    ]
    public static func matches(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
    public static func isSVG(_ path: String) -> Bool { (path as NSString).pathExtension.lowercased() == "svg" }
}
