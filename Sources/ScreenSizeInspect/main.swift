import AppKit
import CoreGraphics
import Foundation
import IOKit.graphics
import DisplayCatalog

private struct DisplaySnapshot: Encodable {
    let name: String
    let mirrored: Bool
    let current: DisplayMode
    let returnedModeCount: Int
    let desktopUsableModeCount: Int
    let suggested: [DisplayMode]
}

private enum InspectionError: Error, CustomStringConvertible {
    case noDisplays
    case coreGraphics(CGError)

    var description: String {
        switch self {
        case .noDisplays:
            return "No displays are accessible. Run in the Mac's logged-in desktop session."
        case .coreGraphics(let error):
            return "CoreGraphics display enumeration failed (\(error.rawValue))."
        }
    }
}

private func snapshot(_ mode: CGDisplayMode) -> DisplayMode {
    DisplayMode(
        token: mode.ioDisplayModeID,
        size: DesktopSize(width: mode.width, height: mode.height),
        pixelSize: DesktopSize(width: mode.pixelWidth, height: mode.pixelHeight),
        refreshRate: mode.refreshRate,
        usable: mode.isUsableForDesktopGUI(),
        interlaced: mode.ioFlags & UInt32(kDisplayModeInterlacedFlag) != 0,
        stretched: mode.ioFlags & UInt32(kDisplayModeStretchedFlag) != 0,
        hidden: mode.ioFlags & UInt32(kDisplayModeNeverShowFlag) != 0
    )
}

@MainActor
private func inspect() throws -> [DisplaySnapshot] {
    var count: UInt32 = 0
    let countResult = CGGetOnlineDisplayList(0, nil, &count)
    guard countResult == .success else { throw InspectionError.coreGraphics(countResult) }
    guard count > 0 else { throw InspectionError.noDisplays }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    let listResult = CGGetOnlineDisplayList(count, &displays, &count)
    guard listResult == .success else { throw InspectionError.coreGraphics(listResult) }

    var names: [CGDirectDisplayID: String] = [:]
    for screen in NSScreen.screens {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            names[number.uint32Value] = screen.localizedName
        }
    }

    return displays.prefix(Int(count)).compactMap { display in
        guard let activeMode = CGDisplayCopyDisplayMode(display) else { return nil }
        let current = snapshot(activeMode)
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []).map(snapshot)
        let mirrored = CGDisplayIsInMirrorSet(display) != 0
        // Until presets exist, the current mode is the explicit Desk reference.
        let suggested = mirrored ? [] : ModeCatalog.shortlist(
            modes: modes,
            desk: current,
            preferredSizes: [DesktopSize(width: 1920, height: 1080)]
        )
        return DisplaySnapshot(
            name: names[display] ?? "External display",
            mirrored: mirrored,
            current: current,
            returnedModeCount: modes.count,
            desktopUsableModeCount: modes.filter(\.usable).count,
            suggested: suggested
        )
    }
}

private func describe(_ mode: DisplayMode) -> String {
    let rate = mode.refreshRate == 0 ? "refresh rate not reported" : String(format: "%.2f Hz", mode.refreshRate)
    return "\(mode.size.width) × \(mode.size.height) — \(mode.isHiDPI ? "HiDPI" : "standard") — \(rate) — \(mode.pixelSize.width) × \(mode.pixelSize.height) backing pixels"
}

@main
@MainActor
private struct ScreenSizeInspect {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.isEmpty || arguments == ["--json"] else {
                FileHandle.standardError.write(Data("Usage: screen-size-inspect [--json]\n".utf8))
                exit(2)
            }
            let displays = try inspect()
            guard !displays.isEmpty else { throw InspectionError.noDisplays }
            if arguments == ["--json"] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(displays))
                print()
            } else {
                print("Read-only inspection. No display settings are changed.\n")
                for display in displays {
                    print(display.name)
                    print("Current: \(describe(display.current))")
                    print("macOS returned \(display.returnedModeCount) modes; \(display.desktopUsableModeCount) are desktop-usable.")
                    if display.mirrored {
                        print("Mirrored display: preset suggestions are disabled in this prototype.")
                    } else {
                        print("Proposed choices (our policy, not Apple's Settings shortlist):")
                        display.suggested.forEach { print("  \(describe($0))") }
                    }
                }
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
