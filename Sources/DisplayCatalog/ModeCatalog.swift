import Foundation

/// Our small-menu policy, not a reproduction of System Settings' curation.
public enum ModeCatalog {
    public static func shortlist(
        modes: [DisplayMode],
        desk: DisplayMode,
        preferredSizes: [DesktopSize]
    ) -> [DisplayMode] {
        guard validGeometryAndRate(desk) else { return [] }

        let deskAspect = Double(desk.size.width) / Double(desk.size.height)
        let eligible = modes.filter { mode in
            guard validGeometryAndRate(mode), mode.usable,
                  !mode.interlaced, !mode.stretched, !mode.hidden,
                  mode.size.width >= min(1280, desk.size.width),
                  mode.size.height >= min(720, desk.size.height),
                  mode.size.width <= desk.size.width,
                  mode.size.height <= desk.size.height else { return false }

            let aspect = Double(mode.size.width) / Double(mode.size.height)
            guard abs(aspect / deskAspect - 1) <= 0.01 else { return false }
            return desk.refreshRate == 0 || mode.refreshRate == 0
                || abs(mode.refreshRate - desk.refreshRate) <= 0.5
        }

        let bySize = Dictionary(grouping: eligible, by: \.size)
        let representatives = bySize.values.compactMap { group -> DisplayMode? in
            if group.contains(desk) { return desk }
            // A rate of zero means unknown. Prefer a known compatible rate
            // before evaluating sharpness, rather than assume zero is 60 Hz.
            let known = group.filter { $0.refreshRate > 0 }
            return (known.isEmpty ? group : known).sorted(by: prefer).first
        }

        var selected: [DesktopSize: DisplayMode] = [:]
        for divisor in [1.0, 1.25, 1.5, 2.0, 2.4] {
            let targetWidth = Double(desk.size.width) / divisor
            let nearest = representatives.min { lhs, rhs in
                let leftDistance = abs(log(Double(lhs.size.width) / targetWidth))
                let rightDistance = abs(log(Double(rhs.size.width) / targetWidth))
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if lhs.size.width != rhs.size.width { return lhs.size.width > rhs.size.width }
                if lhs.size.height != rhs.size.height { return lhs.size.height > rhs.size.height }
                return lhs.token < rhs.token
            }
            if let nearest { selected[nearest.size] = nearest }
        }

        let preferred = Set(preferredSizes)
        for mode in representatives where preferred.contains(mode.size) {
            selected[mode.size] = mode
        }

        return selected.values.sorted { lhs, rhs in
            if lhs.size.width != rhs.size.width { return lhs.size.width < rhs.size.width }
            if lhs.size.height != rhs.size.height { return lhs.size.height < rhs.size.height }
            return lhs.token < rhs.token
        }
    }

    private static func validGeometryAndRate(_ mode: DisplayMode) -> Bool {
        mode.size.width > 0 && mode.size.height > 0
            && mode.pixelSize.width > 0 && mode.pixelSize.height > 0
            && mode.refreshRate.isFinite && mode.refreshRate >= 0
    }

    private static func prefer(_ lhs: DisplayMode, _ rhs: DisplayMode) -> Bool {
        if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
        if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
        // Use Double to avoid integer overflow on malformed input snapshots.
        let leftArea = Double(lhs.pixelSize.width) * Double(lhs.pixelSize.height)
        let rightArea = Double(rhs.pixelSize.width) * Double(rhs.pixelSize.height)
        if leftArea != rightArea { return leftArea > rightArea }
        if lhs.token != rhs.token { return lhs.token < rhs.token }
        if lhs.pixelSize.width != rhs.pixelSize.width { return lhs.pixelSize.width > rhs.pixelSize.width }
        return lhs.pixelSize.height > rhs.pixelSize.height
    }
}
