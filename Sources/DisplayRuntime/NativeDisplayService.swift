import CoreGraphics
import ColorSync
import Foundation
import IOKit.graphics
import DisplayCatalog

public struct ConnectedDisplay: Sendable {
    public let id: UInt32
    public let identity: String
    public let current: DisplayMode
    public let modes: [DisplayMode]
    public let mirrored: Bool
    public let builtIn: Bool
}

public enum DisplayFailure: Error, LocalizedError, Sendable {
    case unavailable, unsupportedLayout, staleMode, changedElsewhere
    case system(Int32), changeFailed(Int32), readbackFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "The display is no longer available. Reconnect it and try again."
        case .unsupportedLayout: return "This preview supports one directly connected, non-mirrored display."
        case .staleMode: return "That exact display mode is no longer available. Choose another size."
        case .changedElsewhere: return "The display changed elsewhere. ScreenSize left that change alone."
        case .system(let code): return "macOS could not change the display (error \(code))."
        case .changeFailed(let code): return "macOS rejected the display change (error \(code))."
        case .readbackFailed: return "macOS did not report the requested display mode. Quit ScreenSize to restore the system setting."
        }
    }
}

/// Serializes public CoreGraphics calls away from the application main thread.
/// This service never writes the permanent macOS display configuration.
public actor NativeDisplayService {
    public init() {}

    public func displays() throws -> [ConnectedDisplay] {
        var count: UInt32 = 0
        let first = CGGetOnlineDisplayList(0, nil, &count)
        guard first == .success else { throw DisplayFailure.system(first.rawValue) }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let second = CGGetOnlineDisplayList(count, &ids, &count)
        guard second == .success else { throw DisplayFailure.system(second.rawValue) }
        return try ids.prefix(Int(count)).map { id in
            guard let mode = CGDisplayCopyDisplayMode(id),
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
                throw DisplayFailure.unavailable
            }
            let identity = CFUUIDCreateString(nil, uuid) as String
            return ConnectedDisplay(id: id, identity: identity, current: Self.describe(mode),
                                    modes: Self.nativeModes(id).map(Self.describe),
                                    mirrored: CGDisplayIsInMirrorSet(id) != 0,
                                    builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// Re-enumerates before applying, so stale transient IDs cannot select a
    /// different display or variant. expectedCurrent prevents late restoration
    /// from overwriting an unrelated settings change.
    public func apply(identity: String, mode: ModeIdentity,
                      expectedCurrent: ModeIdentity) throws -> DisplayMode {
        let attached = try displays()
        guard attached.count == 1, let display = attached.first,
              !display.mirrored, !display.builtIn else { throw DisplayFailure.unsupportedLayout }
        guard display.identity == identity else { throw DisplayFailure.unavailable }
        guard expectedCurrent.matches(display.current) else { throw DisplayFailure.changedElsewhere }
        guard let target = Self.nativeModes(display.id).first(where: {
            let candidate = Self.describe($0)
            return candidate.usable && !candidate.interlaced && !candidate.stretched
                && !candidate.hidden && mode.matches(candidate)
        }) else { throw DisplayFailure.staleMode }
        let result = CGDisplaySetDisplayMode(display.id, target, nil)
        guard result == .success else { throw DisplayFailure.changeFailed(result.rawValue) }
        guard let actual = CGDisplayCopyDisplayMode(display.id), mode.matches(Self.describe(actual)) else {
            throw DisplayFailure.readbackFailed
        }
        return Self.describe(actual)
    }

    private static func nativeModes(_ id: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    private static func describe(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(token: mode.ioDisplayModeID,
                    size: .init(width: mode.width, height: mode.height),
                    pixelSize: .init(width: mode.pixelWidth, height: mode.pixelHeight),
                    refreshRate: mode.refreshRate, usable: mode.isUsableForDesktopGUI(),
                    interlaced: mode.ioFlags & UInt32(kDisplayModeInterlacedFlag) != 0,
                    stretched: mode.ioFlags & UInt32(kDisplayModeStretchedFlag) != 0,
                    hidden: mode.ioFlags & UInt32(kDisplayModeNeverShowFlag) != 0)
    }
}
