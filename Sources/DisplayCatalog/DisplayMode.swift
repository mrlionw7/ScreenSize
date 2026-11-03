public struct DesktopSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A snapshot of one OS-provided mode. The token is transient and must never
/// be used to restore a mode without re-enumerating the display first.
public struct DisplayMode: Codable, Hashable, Sendable {
    public let token: Int32
    public let size: DesktopSize
    public let pixelSize: DesktopSize
    public let refreshRate: Double
    public let usable: Bool
    public let interlaced: Bool
    public let stretched: Bool
    public let hidden: Bool

    public init(token: Int32, size: DesktopSize, pixelSize: DesktopSize,
                refreshRate: Double, usable: Bool = true,
                interlaced: Bool = false, stretched: Bool = false,
                hidden: Bool = false) {
        self.token = token
        self.size = size
        self.pixelSize = pixelSize
        self.refreshRate = refreshRate
        self.usable = usable
        self.interlaced = interlaced
        self.stretched = stretched
        self.hidden = hidden
    }

    public var isHiDPI: Bool {
        pixelSize.width > size.width && pixelSize.height > size.height
    }
}
