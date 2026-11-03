/// A persistable mode signature. Resolve against freshly enumerated modes
/// rather than keeping an OS mode token across display reconfigurations.
public struct ModeIdentity: Codable, Hashable, Sendable {
    public let size: DesktopSize
    public let pixelSize: DesktopSize
    public let refreshRate: Double

    public init(_ mode: DisplayMode) {
        size = mode.size
        pixelSize = mode.pixelSize
        refreshRate = mode.refreshRate
    }

    /// Approximate matching is deliberately separate from exact equality and
    /// hashing, so tolerance does not violate Hashable's equivalence rules.
    public func matches(_ mode: DisplayMode) -> Bool {
        size == mode.size && pixelSize == mode.pixelSize
            && refreshRate.isFinite && mode.refreshRate.isFinite
            && mode.refreshRate >= refreshRate - 0.1
            && mode.refreshRate <= refreshRate + 0.1
    }
}
